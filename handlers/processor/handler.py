import json
import os
import traceback
from decimal import Decimal
from urllib.parse import unquote_plus

import boto3
from botocore.exceptions import ClientError

from message_types import MessageRecord, MessageRecordDB, Sentiment
from utils import decimals_to_float

s3         = boto3.client("s3")
comprehend = boto3.client("comprehend")
dynamodb   = boto3.resource("dynamodb")
sqs        = boto3.client("sqs")

TABLE      = os.environ["RESULTS_TABLE"]
QUEUE_URLS: dict[Sentiment, str] = {
    "POSITIVE": os.environ["QUEUE_URL_POSITIVE"],
    "NEGATIVE": os.environ["QUEUE_URL_NEGATIVE"],
    "NEUTRAL":  os.environ["QUEUE_URL_NEUTRAL"],
    "MIXED":    os.environ["QUEUE_URL_MIXED"],
}

table = dynamodb.Table(TABLE)


def handler(event: dict, context) -> dict:
    record_count = len(event.get("Records", []))
    print(f"[BATCH] Received {record_count} record(s). RequestId={context.aws_request_id}")

    batch_failures = []

    for record in event["Records"]:
        msg_id = record["messageId"]
        try:
            _process_record(record)
        except Exception as exc:
            print(
                f"[FAILED] messageId={msg_id} | "
                f"error={type(exc).__name__}: {exc} | "
                f"trace={traceback.format_exc(limit=5)}"
            )
            batch_failures.append({"itemIdentifier": msg_id})

    success_count = record_count - len(batch_failures)
    print(
        f"[BATCH DONE] success={success_count} failed={len(batch_failures)} "
        f"RequestId={context.aws_request_id}"
    )
    return {"batchItemFailures": batch_failures}


def _process_record(record: dict) -> None:
    msg_id = record["messageId"]

    # --- Unwrap SQS → S3 event -------------------------------------------------
    s3_event   = json.loads(record["body"])
    s3_record  = s3_event["Records"][0]
    bucket     = s3_record["s3"]["bucket"]["name"]
    key        = unquote_plus(s3_record["s3"]["object"]["key"])
    version_id = s3_record["s3"]["object"].get("versionId", "null")
    event_time = s3_record["eventTime"]
    item_id    = f"{key}#{version_id}"

    print(f"[PROCESSING] messageId={msg_id} | s3={bucket}/{key} | eventTime={event_time}")

    # --- Fetch object body from S3 ---------------------------------------------
    try:
        body = (
            s3.get_object(Bucket=bucket, Key=key)["Body"]
            .read(5000)
            .decode("utf-8", errors="replace")
        )
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        print(f"[S3 ERROR] messageId={msg_id} | bucket={bucket} key={key} | code={code} | {exc}")
        raise

    print(f"[S3 OK] messageId={msg_id} | key={key} | body_len={len(body)}")

    # --- Sentiment scoring -----------------------------------------------------
    try:
        result = comprehend.detect_sentiment(Text=body, LanguageCode="en")
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        print(f"[COMPREHEND ERROR] messageId={msg_id} | key={key} | code={code} | {exc}")
        raise

    sentiment: Sentiment = result["Sentiment"]
    scores               = result["SentimentScore"]
    confidence           = Decimal(str(scores[sentiment.title()]))

    print(
        f"[COMPREHEND OK] messageId={msg_id} | key={key} | "
        f"sentiment={sentiment} confidence={float(confidence):.4f}"
    )

    # --- Build DynamoDB item (MessageRecordDB — Decimal scores) ----------------
    item: MessageRecordDB = {
        "id":         item_id,
        "pk":         "MSG",
        "snippet":    body[:280],
        "sentiment":  sentiment,
        "confidence": confidence,
        "scores": {
            "positive": Decimal(str(scores["Positive"])),
            "negative": Decimal(str(scores["Negative"])),
            "neutral":  Decimal(str(scores["Neutral"])),
            "mixed":    Decimal(str(scores["Mixed"])),
        },
        "source":     key,
        "receivedAt": event_time,
    }

    # --- Persist to DynamoDB (idempotent) --------------------------------------
    try:
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(id)")
        print(f"[DYNAMO OK] messageId={msg_id} | id={item_id} | sentiment={sentiment}")
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code == "ConditionalCheckFailedException":
            print(f"[DUPLICATE] messageId={msg_id} | id={item_id} — already processed, skipping route")
            return
        print(f"[DYNAMO ERROR] messageId={msg_id} | id={item_id} | code={code} | {exc}")
        raise

    # --- Route to sentiment queue (MessageRecord — float scores) ---------------
    payload: MessageRecord = decimals_to_float(item)  # type: ignore[assignment]
    queue_url = QUEUE_URLS[sentiment]
    try:
        sqs.send_message(QueueUrl=queue_url, MessageBody=json.dumps(payload))
        print(f"[ROUTED] messageId={msg_id} | sentiment={sentiment} | queue={queue_url}")
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        print(
            f"[SQS ROUTE ERROR] messageId={msg_id} | sentiment={sentiment} | "
            f"queue={queue_url} | code={code} | {exc}"
        )
        raise
