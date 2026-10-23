"""Runs the real handler against a real PostgreSQL.

Set DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD and DB_SSL_MODE=disable,
then run: make integration. Without DB_HOST the whole module is skipped.
"""

import json
import os
from types import SimpleNamespace

import pytest

import handler

pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(not os.environ.get("DB_HOST"), reason="DB_HOST is not set"),
]


def call():
    response = handler.lambda_handler({}, SimpleNamespace(aws_request_id="req-it"))
    return response["statusCode"], json.loads(response["body"])


@pytest.fixture(autouse=True)
def no_secret(monkeypatch):
    monkeypatch.delenv("DB_SECRET_ARN", raising=False)
    monkeypatch.delenv("DB_INSTANCE_CLASS", raising=False)


def test_reads_the_real_server():
    status, body = call()

    assert status == 200
    assert body["database"]["connected"] is True
    assert body["database"]["database"] == os.environ["DB_NAME"]
    assert body["database"]["in_recovery"] is False
    assert body["database"]["latency_ms"] > 0


def test_a_wrong_password_is_reported_as_authentication(monkeypatch):
    monkeypatch.setenv("DB_PASSWORD", "definitely-not-the-password")

    status, body = call()

    assert status == 503
    assert body["database"]["error"] == "authentication"


def test_a_closed_port_is_reported_as_unavailable(monkeypatch):
    monkeypatch.setenv("DB_PORT", "1")

    status, body = call()

    assert status == 503
    assert body["database"]["error"] == "unavailable"
