"""
Read API Lambda — STUB. Implement this in Phase 7.

Trigger: API Gateway HTTP API  GET /messages

Query string parameters:
  limit   int, optional — default 60, capped at 200.

Logic:
  1. Read optional ?limit= from event["queryStringParameters"].
     Clamp to [1, 200]; default 60 if absent or invalid.
  2. Fetch records from RESULTS_TABLE newest-first:
       - Preferred : Query the "by-recency" GSI (sort key = receivedAt DESC)
                     with Limit=limit.
       - Fallback  : Scan the table, sort descending by receivedAt in Python,
                     take the first `limit` items.
  3. Convert every decimal.Decimal in each item to float/int before serialising
     (json.dumps raises TypeError on Decimal).
  4. Return a Lambda proxy response:
       {
         "statusCode": 200,
         "headers": {
           "Content-Type": "application/json",
           "Access-Control-Allow-Origin": "*"
         },
         "body": json.dumps({"items": [...]})
       }
     The "items" array must match the MessagesResponse shape in
     apps/web/lib/types.ts.

Environment variables (set in infra/lambda.tf):
  RESULTS_TABLE   DynamoDB table name

Pure boto3 — no extra dependencies.
"""

# TODO: implement in Phase 7
