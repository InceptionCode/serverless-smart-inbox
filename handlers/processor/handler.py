"""
Processor Lambda — STUB. Implement this in Phase 5.

Trigger: SQS event source mapping carrying S3 ObjectCreated notifications
         (batch_size=10, function_response_types=["ReportBatchItemFailures"]).

For each SQS record:
  1. Parse the S3 bucket name and object key from the embedded S3 event JSON.
  2. s3.get_object(Bucket=bucket, Key=key) — read and truncate body to 5 000 bytes.
  3. comprehend.detect_sentiment(Text=body, LanguageCode="en").
  4. Build a record matching the MessageRecord shape in apps/web/lib/types.ts.
     Use decimal.Decimal for every score field — DynamoDB rejects plain float:
       id         = f"{key}#{version_id}"          (idempotency key)
       snippet    = body[:280]
       sentiment  = top-level Sentiment string     ("POSITIVE" | "NEGATIVE" | …)
       confidence = SentimentScore[sentiment.title()]   as Decimal
       scores     = {positive, negative, neutral, mixed}  all Decimal
       source     = key
       receivedAt = S3 event timestamp (ISO 8601)
  5. dynamodb.put_item(ConditionExpression="attribute_not_exists(id)")
     Catch ConditionalCheckFailedException and skip — idempotent on key+versionId.
  6. sqs.send_message(QueueUrl=QUEUE_URL_<SENTIMENT>, MessageBody=json.dumps(record))
     QUEUE_URL_POSITIVE / QUEUE_URL_NEGATIVE / QUEUE_URL_NEUTRAL / QUEUE_URL_MIXED
     come from environment variables.

Return {"batchItemFailures": [{"itemIdentifier": record["messageId"]}]}
for any record that raises, so the event source mapping retries only
the failed items (not the whole batch).

Environment variables (set in infra/lambda.tf):
  RESULTS_TABLE       DynamoDB table name
  QUEUE_URL_POSITIVE  SQS URL — positive routing queue
  QUEUE_URL_NEGATIVE  SQS URL — negative routing queue
  QUEUE_URL_NEUTRAL   SQS URL — neutral routing queue
  QUEUE_URL_MIXED     SQS URL — mixed routing queue

Pure boto3 — no extra dependencies.
"""

# TODO: implement in Phase 5
