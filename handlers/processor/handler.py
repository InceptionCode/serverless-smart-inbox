"""
Processor Lambda — Phase 5.

Trigger: SQS event source mapping carrying S3 ObjectCreated notifications
         (batch_size=10, function_response_types=["ReportBatchItemFailures"]).

Data contract: apps/web/lib/types.ts  (MessageRecord shape).
"""

import json
import os
from decimal import Decimal
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError

s3         = boto3.client("s3")
comprehend = boto3.client("comprehend")
dynamodb   = boto3.resource("dynamodb")
sqs        = boto3.client("sqs")

TABLE        = os.environ["RESULTS_TABLE"]
QUEUE_URLS   = {
    "POSITIVE": os.environ["QUEUE_URL_POSITIVE"],
    "NEGATIVE": os.environ["QUEUE_URL_NEGATIVE"],
    "NEUTRAL":  os.environ["QUEUE_URL_NEUTRAL"],
    "MIXED":    os.environ["QUEUE_URL_MIXED"],
}

table = dynamodb.Table(TABLE)


def handler(event, context):
    """
    Process a batch of SQS records.

    Each SQS record wraps an S3 ObjectCreated notification.
    Returns batchItemFailures so the ESM retries only the failed records.

    Pseudocode flow per record:
        parse SQS record
            → extract S3 bucket + key + version_id + event_time
        fetch object from S3
            → truncate body to 5000 bytes
        call Comprehend DetectSentiment
            → get top-level sentiment + score map
        build DynamoDB item  (all scores as Decimal, not float)
        write item impotently
            → PutItem with attribute_not_exists(id)
            → skip ConditionalCheckFailedException (already processed)
        forward to routing queue
            → send_message to QUEUE_URLS[sentiment]
    """
    batch_failures = []

    for record in event["Records"]:
        try:
            _process_record(record)
        except Exception as exc:
            print(f"ERROR processing {record['messageId']}: {exc}")
            batch_failures.append({"itemIdentifier": record["messageId"]})

    return {"batchItemFailures": batch_failures}


def _process_record(record):
    s3_event   = json.loads(record["body"])
    s3_record  = s3_event["Records"][0]
    bucket     = s3_record["s3"]["bucket"]["name"]
    key        = unquote_plus(s3_record["s3"]["object"]["key"])
    version_id = s3_record["s3"]["object"].get("versionId", "null")
    event_time = s3_record["eventTime"]

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read(5000).decode("utf-8", errors="replace")

    result    = comprehend.detect_sentiment(Text=body, LanguageCode="en")
    sentiment = result["Sentiment"]
    scores    = result["SentimentScore"]
    confidence = Decimal(str(scores[sentiment.title()]))

    item = {
        "id": f"{key}#{version_id}",
        "pk": "MSG",
        "snippet": body[:280],
        "sentiment": sentiment,
        "confidence": confidence,
        "scores": {
            "positive": Decimal(str(scores["Positive"])),
            "negative": Decimal(str(scores["Negative"])),
            "neutral":  Decimal(str(scores["Neutral"])),
            "mixed":    Decimal(str(scores["Mixed"])),
        },
        "source": key,
        "receivedAt": event_time
    }

    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            print(f"Duplicate skipped: {item['id']}")
            return   # already processed — skip routing too
        raise        # any other error bubbles up → batchItemFailure

    payload = json.dumps(_decimals_to_float(item))
    sqs.send_message(QueueUrl=QUEUE_URLS[sentiment], MessageBody=payload) # routing to the correct sentiment queue


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _decimals_to_float(obj):
    """Recursively convert Decimal → float so json.dumps can serialize."""
    if isinstance(obj, Decimal):
        return float(obj)
    if isinstance(obj, dict):
        return {k: _decimals_to_float(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [_decimals_to_float(v) for v in obj]
    return obj
