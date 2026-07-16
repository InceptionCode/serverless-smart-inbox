###############################################################################
# Lambda  —  Phase 5 (processor) + Phase 7 (read_api).
#
# Packaging: the handler directory is zipped on-the-fly by Terraform using
# the archive_file data source.  boto3/botocore ship with the Lambda managed
# runtime (python3.12) — no extra layer needed.
#
# ESM notes (processor only):
#   batch_size = 10          — process up to 10 S3 notifications per invocation.
#   function_response_types  — "ReportBatchItemFailures" lets the handler return
#                              { batchItemFailures: [...] } so only failed records
#                              go back to the queue, not the whole batch.
###############################################################################

# ---------------------------------------------------------------------------
# Package the processor handler directory into a zip
# ---------------------------------------------------------------------------

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../handlers/processor"
  output_path = "${path.module}/.terraform/processor.zip"
}

# ---------------------------------------------------------------------------
# CloudWatch log group — explicit so Terraform controls retention (30 days).
# Without this, Lambda auto-creates it with no expiry and Terraform can't
# manage it cleanly.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# Processor Lambda function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor"
  description   = "Scores incoming messages with Comprehend and routes by sentiment."

  # Packaging
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"

  # Execution role (Phase 4)
  role = aws_iam_role.processor.arn

  # Keep cold-start snappy — sentiment scoring is fast
  timeout     = 30  # seconds
  memory_size = 256 # MB

  environment {
    variables = {
      RESULTS_TABLE      = aws_dynamodb_table.results.name
      QUEUE_URL_POSITIVE = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.project_name}-route-positive"
      QUEUE_URL_NEGATIVE = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.project_name}-route-negative"
      QUEUE_URL_NEUTRAL  = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.project_name}-route-neutral"
      QUEUE_URL_MIXED    = "https://sqs.${data.aws_region.current.name}.amazonaws.com/${data.aws_caller_identity.current.account_id}/${var.project_name}-route-mixed"
    }
  }

  # Ensure the log group exists before Lambda tries to write to it
  depends_on = [aws_cloudwatch_log_group.processor]
}

# ---------------------------------------------------------------------------
# Event Source Mapping: ingest SQS queue → processor Lambda
# ---------------------------------------------------------------------------

resource "aws_lambda_event_source_mapping" "ingest" {
  event_source_arn = aws_sqs_queue.ingest.arn
  function_name    = aws_lambda_function.processor.arn

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

# ===========================================================================
# Phase 7 — Read API Lambda
# ===========================================================================

data "archive_file" "read_api" {
  type        = "zip"
  source_dir  = "${path.module}/../handlers/read_api"
  output_path = "${path.module}/.terraform/read_api.zip"
}

resource "aws_cloudwatch_log_group" "read_api" {
  name              = "/aws/lambda/${var.project_name}-read-api"
  retention_in_days = 30
}

resource "aws_lambda_function" "read_api" {
  function_name = "${var.project_name}-read-api"
  description   = "Returns scored messages from DynamoDB for the dashboard."

  filename         = data.archive_file.read_api.output_path
  source_code_hash = data.archive_file.read_api.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"

  role        = aws_iam_role.read_api.arn
  timeout     = 10
  memory_size = 128

  environment {
    variables = {
      RESULTS_TABLE = aws_dynamodb_table.results.name
    }
  }

  depends_on = [aws_cloudwatch_log_group.read_api]
}
