import json
import os
import traceback

import boto3
from botocore.exceptions import ClientError

from message_types import MessageQueryParams, MessageRecord, MessagesResponse
from utils import decimals_to_float

dynamodb = boto3.resource("dynamodb")

TABLE    = os.environ["RESULTS_TABLE"]
GSI_NAME = "by-recency" 

table = dynamodb.Table(TABLE)

# Query defaults / caps
DEFAULT_LIMIT = 60
MAX_LIMIT     = 200

# CORS header — allows the Next.js dashboard (any origin) to call this API.
CORS_HEADERS = {
    "Content-Type":                "application/json",
    "Access-Control-Allow-Origin": "*",
}


def handler(event: dict, context) -> dict:
    print(f"[REQUEST] GET /messages | RequestId={context.aws_request_id}")

    # event["queryStringParameters"] is None when no query string is sent.
    query_params: MessageQueryParams = event.get("queryStringParameters") or {"limit": DEFAULT_LIMIT}
    print(f"[PARAMS] query_params={query_params}")

    try:
        limit = _parse_limit(query_params)
        messages = _query_gsi(limit)
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        print(
            f"[DYNAMO ERROR] code={code} | {exc} | "
            f"trace={traceback.format_exc(limit=5)}"
        )
        return _proxy_response(500, {"error": "Failed to read messages", "detail": str(exc)})
    except Exception as exc:
        print(
            f"[ERROR] {type(exc).__name__}: {exc} | "
            f"trace={traceback.format_exc(limit=5)}"
        )
        return _proxy_response(500, {"error": "Internal server error"})

    print(f"[SUCCESS] returning {len(messages)} message(s)")
    return _proxy_response(200, {"items": messages})


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_limit(params: MessageQueryParams) -> int:
    """Parse and clamp the limit param. Falls back to DEFAULT_LIMIT on invalid input."""
    try:
        n = int(params.get("limit", DEFAULT_LIMIT))
    except (ValueError, TypeError):
        return DEFAULT_LIMIT

    clamped = max(1, min(n, MAX_LIMIT))
    print(f"[PARAMS] limit={clamped}")
    return clamped


def _query_gsi(limit: int) -> list[MessageRecord]:
    """Query the by-recency GSI newest-first. Converts Decimal → float before returning."""
    print(f"[DYNAMO] querying GSI={GSI_NAME} limit={limit}")

    response = table.query(
        IndexName=GSI_NAME,
        KeyConditionExpression="pk = :pk",
        ExpressionAttributeValues={":pk": "MSG"},
        ScanIndexForward=False,
        Limit=limit,
    )

    items = response.get("Items", [])

    if not items:
        print("[DYNAMO] no items found")

    return [decimals_to_float(item) for item in items]


def _proxy_response(status: int, body: dict | MessagesResponse) -> dict:
    """Wrap a dict into a Lambda proxy response. CORS headers on every response."""
    return {
        "statusCode": status,
        "headers":    CORS_HEADERS,
        "body":       json.dumps(body),
    }
