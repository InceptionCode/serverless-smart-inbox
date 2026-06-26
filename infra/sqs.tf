###############################################################################
# SQS  —  Phase 2 (ingest + DLQ) and Phase 6 (routing queues).
#
# Why a queue between S3 and Lambda: the queue gives you a retry buffer,
# batching, backpressure, and a DLQ for poison messages. Direct S3→Lambda
# invocation gives you none of that. This is the senior-engineer story.
###############################################################################

# --- Ingest DLQ (Phase 2) ----------------------------------------------------
# Receives messages that have failed maxReceiveCount times on the ingest queue.
# Phase 9 adds a CloudWatch alarm on ApproximateNumberOfMessagesVisible > 0.

resource "aws_sqs_queue" "ingest_dlq" {
  name = "${var.project_name}-ingest-dlq"
}

# --- Ingest queue (Phase 2) --------------------------------------------------
# visibility_timeout_seconds must be >= the processor Lambda timeout (set to
# 60 s in lambda.tf). 180 s gives 3× headroom so a slow invocation never makes
# the message re-visible while still being processed.

resource "aws_sqs_queue" "ingest" {
  name                       = "${var.project_name}-ingest"
  visibility_timeout_seconds = 180

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.ingest_dlq.arn
    maxReceiveCount     = 5
  })
}

# --- SQS resource policy (Phase 2) ------------------------------------------
# Allows the inbox S3 bucket to call sqs:SendMessage on the ingest queue.
# Scoped to both the exact source ARN and the account ID — prevents confused-
# deputy attacks from other accounts' S3 buckets.
#
# Build this BEFORE aws_s3_bucket_notification.inbox; the notification resource
# depends_on it explicitly to enforce apply ordering.

resource "aws_sqs_queue_policy" "ingest_from_s3" {
  queue_url = aws_sqs_queue.ingest.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowInboxBucketSend"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.ingest.arn
      Condition = {
        ArnEquals    = { "aws:SourceArn" = aws_s3_bucket.inbox.arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}

# --- Sentiment routing queues (Phase 6) -------------------------------------
# Uncomment when building Phase 6. for_each keeps this DRY.
#
# resource "aws_sqs_queue" "routing" {
#   for_each = toset(["positive", "negative", "neutral", "mixed"])
#   name     = "${var.project_name}-route-${each.key}"
# }
#
# Pass the URLs into the processor Lambda as env vars (see lambda.tf):
#   QUEUE_URL_POSITIVE = aws_sqs_queue.routing["positive"].url
#   QUEUE_URL_NEGATIVE = aws_sqs_queue.routing["negative"].url
#   QUEUE_URL_NEUTRAL  = aws_sqs_queue.routing["neutral"].url
#   QUEUE_URL_MIXED    = aws_sqs_queue.routing["mixed"].url
