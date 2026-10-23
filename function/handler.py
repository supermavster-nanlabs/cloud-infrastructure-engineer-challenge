"""Lambda behind GET /info: connects to PostgreSQL over TLS and reports its status."""

import json
import logging
import os
import ssl
import time
from datetime import UTC, datetime
from pathlib import Path

import boto3
import pg8000.exceptions
import pg8000.native
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Public RDS certificate bundle: https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
CA_BUNDLE = Path(__file__).parent / "certs" / "global-bundle.pem"

# SQLSTATE codes: invalid_password, invalid_authorization_specification.
AUTH_CODES = {"28P01", "28000"}
QUERY_CANCELED = "57014"  # raised when statement_timeout is hit

PROBE_SQL = """
SELECT
    current_setting('server_version'),
    current_database(),
    pg_is_in_recovery(),
    EXTRACT(EPOCH FROM (now() - pg_postmaster_start_time()))::bigint,
    COALESCE((SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()), false)
"""


class CredentialsError(Exception):
    """The database password could not be read."""


def get_credentials() -> tuple[str, str]:
    """Read the password on every call: RDS rotates it, so nothing is cached."""
    secret_arn = os.environ.get("DB_SECRET_ARN")
    if not secret_arn:  # local runs
        return os.environ["DB_USER"], os.environ["DB_PASSWORD"]
    try:
        client = boto3.client(
            "secretsmanager",
            config=Config(connect_timeout=1, read_timeout=1, retries={"max_attempts": 2}),
        )
        secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
        return secret["username"], secret["password"]
    except Exception as exc:
        raise CredentialsError from exc


def connect(user: str, password: str) -> pg8000.native.Connection:
    # create_default_context verifies the certificate chain and the hostname.
    verify = os.environ.get("DB_SSL_MODE") != "disable"
    return pg8000.native.Connection(
        user=user,
        password=password,
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        database=os.environ["DB_NAME"],
        ssl_context=ssl.create_default_context(cafile=str(CA_BUNDLE)) if verify else None,
        timeout=3,
        startup_params={"statement_timeout": "2000"},
        application_name="info-api",
    )


def classify(exc: Exception) -> str:
    """A short, safe reason. Hosts, users and exception text never reach the caller."""
    if isinstance(exc, CredentialsError):
        return "credentials"
    if isinstance(exc, KeyError):
        return "configuration"
    if isinstance(exc, ssl.SSLError):
        return "tls"
    if isinstance(exc, TimeoutError):
        return "timeout"
    if isinstance(exc, pg8000.exceptions.DatabaseError):
        detail = exc.args[0] if exc.args and isinstance(exc.args[0], dict) else {}
        code = detail.get("C")
        if code in AUTH_CODES:
            return "authentication"
        return "timeout" if code == QUERY_CANCELED else "unavailable"
    if isinstance(exc, pg8000.exceptions.InterfaceError) and "SSL" in str(exc):
        return "tls"
    return "unavailable"


def instance_details() -> dict | None:
    """Facts about the instance, passed in by Terraform. None when running locally."""
    if "DB_INSTANCE_CLASS" not in os.environ:
        return None
    return {
        "class": os.environ["DB_INSTANCE_CLASS"],
        "multi_az": os.environ.get("DB_MULTI_AZ") == "true",
        "availability_zone": os.environ.get("DB_AZ"),
        "backup_retention_days": int(os.environ.get("DB_BACKUP_DAYS", "0")),
    }


def respond(status_code: int, body: dict) -> dict:
    headers = {"content-type": "application/json", "cache-control": "no-store"}
    return {"statusCode": status_code, "headers": headers, "body": json.dumps(body)}


def lambda_handler(event, context):
    request_id = context.aws_request_id
    now = datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        user, password = get_credentials()
        started = time.perf_counter()
        conn = connect(user, password)
        try:
            row = conn.run(PROBE_SQL)[0]
        finally:
            conn.close()
        latency_ms = round((time.perf_counter() - started) * 1000, 1)
    except Exception as exc:
        category = classify(exc)
        logger.warning(
            "database unavailable",
            extra={"request_id": request_id, "category": category, "error": type(exc).__name__},
        )
        return respond(
            503,
            {
                "status": "degraded",
                "timestamp": now,
                "request_id": request_id,
                "database": {"connected": False, "error": category},
            },
        )

    return respond(
        200,
        {
            "status": "ok",
            "timestamp": now,
            "request_id": request_id,
            "database": {
                "connected": True,
                "engine": "postgres",
                "version": row[0],
                "database": row[1],
                "in_recovery": row[2],
                "uptime_seconds": int(row[3]),
                "tls": row[4],
                "latency_ms": latency_ms,
            },
            "instance": instance_details(),
        },
    )
