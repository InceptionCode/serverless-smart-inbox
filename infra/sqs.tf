###############################################################################
# SQS  —  SKELETON. You build the resource bodies (PHASE 2 + PHASE 6).
#
# Queues:
#   ingest                  — S3 dumps ObjectCreated events here. The processor
#                             Lambda polls it (event source mapping in lambda.tf).
#   ingest_dlq              — dead-letter for ingest; redrive after N failures.
#   routing: positive / negative / neutral / mixed
#                           — processor send_message()s into the matching one.
#                             This is the "message routing" requirement.
#   (optional) routing DLQs — one per routing queue if you want full coverage.
#
# Why a queue between S3 and Lambda (Option B): retry buffer, batching,
# backpressure, and a DLQ for poison messages. Direct S3->Lambda gives you none
# of that. This is the senior-engineer story for the portfolio.
###############################################################################

# --- Ingest queue + DLQ -----------------------------------------------------

# resource "aws_sqs_queue" "ingest_dlq" {
#   name = "${var.project_name}-ingest-dlq"
# }
#
# resource "aws_sqs_queue" "ingest" {
#   name                       = "${var.project_name}-ingest"
#   visibility_timeout_seconds = 180   # MUST be >= processor Lambda timeout
#   redrive_policy = jsonencode({
#     deadLetterTargetArn = aws_sqs_queue.ingest_dlq.arn
#     maxReceiveCount     = 5
#   })
# }

# Let the inbox S3 bucket send messages to the ingest queue.
# resource "aws_sqs_queue_policy" "ingest_from_s3" {
#   queue_url = aws_sqs_queue.ingest.id
#   policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "s3.amazonaws.com" }
#       Action    = "sqs:SendMessage"
#       Resource  = aws_sqs_queue.ingest.arn
#       Condition = {
#         ArnEquals   = { "aws:SourceArn" = aws_s3_bucket.inbox.arn }
#         StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
#       }
#     }]
#   })
# }
# (add `data "aws_caller_identity" "current" {}` somewhere, e.g. in main/iam.tf)

# --- Sentiment routing queues (PHASE 6) -------------------------------------
# for_each over the four labels keeps this DRY:
#
# resource "aws_sqs_queue" "routing" {
#   for_each = toset(["positive", "negative", "neutral", "mixed"])
#   name     = "${var.project_name}-route-${each.key}"
# }
#
# Pass the URLs to the processor as env vars (see lambda.tf):
#   QUEUE_URL_POSITIVE = aws_sqs_queue.routing["positive"].url   ...etc
