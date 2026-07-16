"""
Python types — mirrors apps/web/lib/types.ts.

Keep this file identical to handlers/read_api/message_types.py.
When the data contract changes, update apps/web/lib/types.ts first,
then both copies of this file, then the DynamoDB write path.

Two variants exist for the same record shape:
  MessageRecordDB  — Decimal scores, written to DynamoDB (boto3 rejects float)
  MessageRecord    — float scores, serialised to JSON for SQS / API responses
"""

from decimal import Decimal
from typing import Literal, TypedDict

# ---------------------------------------------------------------------------
# Sentiment type
# Mirrors: export type Sentiment = "POSITIVE" | "NEUTRAL" | "NEGATIVE" | "MIXED"
# ---------------------------------------------------------------------------

Sentiment = Literal["POSITIVE", "NEGATIVE", "NEUTRAL", "MIXED"]

# ---------------------------------------------------------------------------
# JSON / API / SQS variant  (float scores)
# Mirrors: export interface MessageRecord
# ---------------------------------------------------------------------------


class SentimentScores(TypedDict):
    positive: float
    negative: float
    neutral:  float
    mixed:    float


class MessageQueryParams(TypedDict):
    limit: int


class MessageRecord(TypedDict):
    id:         str        # "{s3_key}#{versionId}"
    pk:         str        # always "MSG" — GSI partition key
    snippet:    str        # body[:280]
    sentiment:  Sentiment
    confidence: float      # winning score, 0–1
    scores:     SentimentScores
    source:     str        # raw S3 key
    receivedAt: str        # ISO 8601 — S3 eventTime


class MessagesResponse(TypedDict):
    """Shape returned by the Read API. Mirrors: export interface MessagesResponse."""
    items: list[MessageRecord]


# ---------------------------------------------------------------------------
# DynamoDB write variant  (Decimal scores)
# boto3 raises TypeError on float for the DynamoDB Number type.
# Use Decimal(str(float_value)) when building this struct.
# ---------------------------------------------------------------------------


class SentimentScoresDB(TypedDict):
    positive: Decimal
    negative: Decimal
    neutral:  Decimal
    mixed:    Decimal


class MessageRecordDB(TypedDict):
    id:         str
    pk:         str
    snippet:    str
    sentiment:  Sentiment
    confidence: Decimal
    scores:     SentimentScoresDB
    source:     str
    receivedAt: str
