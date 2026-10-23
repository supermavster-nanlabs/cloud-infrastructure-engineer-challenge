import json
import ssl
from types import SimpleNamespace

import pg8000.exceptions
import pytest

import handler

ROW = ("17.4", "appdb", False, 3600, True)
CONTEXT = SimpleNamespace(aws_request_id="req-123")


class FakeConnection:
    def __init__(self, error=None):
        self.error = error
        self.closed = False

    def run(self, sql):
        if self.error:
            raise self.error
        return [ROW]

    def close(self):
        self.closed = True


@pytest.fixture(autouse=True)
def database_env(monkeypatch):
    for key in ("DB_SECRET_ARN", "DB_INSTANCE_CLASS", "DB_SSL_MODE"):
        monkeypatch.delenv(key, raising=False)
    monkeypatch.setenv("DB_HOST", "db.internal.example")
    monkeypatch.setenv("DB_NAME", "appdb")
    monkeypatch.setattr(handler, "get_credentials", lambda: ("dbadmin", "s3cret-pw"))


def call(monkeypatch, connection=None, connect_error=None):
    def fake_connect(user, password):
        if connect_error:
            raise connect_error
        return connection

    monkeypatch.setattr(handler, "connect", fake_connect)
    response = handler.lambda_handler({}, CONTEXT)
    return response, json.loads(response["body"])


def test_success_reports_the_database(monkeypatch):
    connection = FakeConnection()

    response, body = call(monkeypatch, connection)

    assert response["statusCode"] == 200
    assert response["headers"]["cache-control"] == "no-store"
    assert body["status"] == "ok"
    assert body["request_id"] == "req-123"
    assert body["database"] | {"latency_ms": 0} == {
        "connected": True,
        "engine": "postgres",
        "version": "17.4",
        "database": "appdb",
        "in_recovery": False,
        "uptime_seconds": 3600,
        "tls": True,
        "latency_ms": 0,
    }
    assert body["instance"] is None
    assert connection.closed


def test_instance_details_come_from_the_environment(monkeypatch):
    monkeypatch.setenv("DB_INSTANCE_CLASS", "db.t4g.micro")
    monkeypatch.setenv("DB_MULTI_AZ", "true")
    monkeypatch.setenv("DB_AZ", "us-east-1a")
    monkeypatch.setenv("DB_BACKUP_DAYS", "7")

    _, body = call(monkeypatch, FakeConnection())

    assert body["instance"] == {
        "class": "db.t4g.micro",
        "multi_az": True,
        "availability_zone": "us-east-1a",
        "backup_retention_days": 7,
    }


@pytest.mark.parametrize(
    ("error", "category"),
    [
        (ssl.SSLCertVerificationError("certificate verify failed"), "tls"),
        (TimeoutError("timed out"), "timeout"),
        (pg8000.exceptions.DatabaseError({"C": "28P01", "M": "bad password"}), "authentication"),
        (pg8000.exceptions.DatabaseError({"C": "57014", "M": "canceled"}), "timeout"),
        (OSError("connection refused"), "unavailable"),
        (handler.CredentialsError(), "credentials"),
    ],
)
def test_failures_become_a_503_with_a_category(monkeypatch, error, category):
    response, body = call(monkeypatch, connect_error=error)

    assert response["statusCode"] == 503
    assert body["database"] == {"connected": False, "error": category}


def test_error_bodies_never_contain_connection_details(monkeypatch):
    error = pg8000.exceptions.DatabaseError({"C": "28P01", "M": "password for dbadmin failed"})

    response, _ = call(monkeypatch, connect_error=error)

    for secret in ("db.internal.example", "dbadmin", "s3cret-pw", "Traceback"):
        assert secret not in response["body"]


def test_tls_verifies_certificate_and_hostname(monkeypatch):
    captured = {}
    monkeypatch.setattr(handler.pg8000.native, "Connection", lambda **kw: captured.update(kw))

    handler.connect("dbadmin", "pw")

    context = captured["ssl_context"]
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert context.check_hostname is True


def test_tls_can_only_be_disabled_explicitly(monkeypatch):
    captured = {}
    monkeypatch.setattr(handler.pg8000.native, "Connection", lambda **kw: captured.update(kw))
    monkeypatch.setenv("DB_SSL_MODE", "disable")

    handler.connect("dbadmin", "pw")

    assert captured["ssl_context"] is None
