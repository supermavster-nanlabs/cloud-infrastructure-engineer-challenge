"""Runs the real handler once, in this process, and prints the response.

The DB_* environment variables choose the database; see local/.env.example.
Exit status is 0 only when the handler answers 200.
"""

import json
import sys
from pathlib import Path
from types import SimpleNamespace

import handler


def main() -> int:
    event = json.loads((Path(__file__).parent / "events" / "get-info.json").read_text())

    response = handler.lambda_handler(event, SimpleNamespace(aws_request_id="local-invoke"))

    print(f"HTTP {response['statusCode']}")
    print(json.dumps(json.loads(response["body"]), indent=2))
    return 0 if response["statusCode"] == 200 else 1


if __name__ == "__main__":
    sys.exit(main())
