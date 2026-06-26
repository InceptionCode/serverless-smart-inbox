###############################################################################
# IAM  —  Phase 4.  Least-privilege execution roles for both Lambdas.
#
# Hard rule: no Resource = "*" except where AWS forces it.
# Comprehend has no resource-level permission support — the service rejects
# scoped ARNs, so "*" is required there and only there.
#
# Note on routing queues: they are created in Phase 6, but their ARNs are
# fully predictable from the naming convention in sqs.tf.  Computing them
# here avoids a circular dependency and keeps the policy correct from day one.
###############################################################################

locals {
  routing_queue_arns = [
    for s in ["positive", "negative", "neutral", "mixed"] :
    "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${var.project_name}-route-${s}"
  ]
}

# ---------------------------------------------------------------------------
# Shared: Lambda trust policy
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ---------------------------------------------------------------------------
# Processor role + inline policy
# ---------------------------------------------------------------------------

resource "aws_iam_role" "processor" {
  name               = "${var.project_name}-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "processor" {

  # Logs — CreateLogGroup needs account scope; streams are scoped to this
  # function's log group only.
  statement {
    sid       = "LogsCreateGroup"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    sid     = "LogsWriteStreams"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-processor:*",
    ]
  }

  # SQS — poll and acknowledge messages from the ingest queue.
  # ChangeMessageVisibility is required for ReportBatchItemFailures so Lambda
  # can extend visibility on a failed item without re-hiding the whole batch.
  statement {
    sid = "SQSConsume"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.ingest.arn]
  }

  # SQS — fan-out to the four sentiment routing queues (Phase 6).
  # ARNs are computed deterministically; no wildcard needed.
  statement {
    sid       = "SQSRoute"
    actions   = ["sqs:SendMessage"]
    resources = local.routing_queue_arns
  }

  # S3 — read the object that triggered the event.  Scoped to objects
  # inside the inbox bucket only (bucket ARN + /*).
  statement {
    sid       = "S3GetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.inbox.arn}/*"]
  }

  # Comprehend — AWS does not support resource-level permissions for this
  # API; the service rejects any ARN other than "*".  This is the one
  # forced exception to our no-wildcard rule.
  statement {
    sid       = "Comprehend"
    actions   = ["comprehend:DetectSentiment"]
    resources = ["*"]
  }

  # DynamoDB — write processed records to the results table.
  statement {
    sid       = "DynamoDBWrite"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.results.arn]
  }
}

resource "aws_iam_role_policy" "processor" {
  name   = "${var.project_name}-processor-policy"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor.json
}

# ---------------------------------------------------------------------------
# Read API role + inline policy
# ---------------------------------------------------------------------------

resource "aws_iam_role" "read_api" {
  name               = "${var.project_name}-read-api"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "read_api" {

  statement {
    sid       = "LogsCreateGroup"
    actions   = ["logs:CreateLogGroup"]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }

  statement {
    sid     = "LogsWriteStreams"
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-read-api:*",
    ]
  }

  # DynamoDB — read records from the table and the by-recency GSI.
  # Both ARNs are required: the table ARN for GetItem/Scan, the GSI ARN
  # for Query (AWS enforces the GSI ARN separately in the resource policy).
  statement {
    sid = "DynamoDBRead"
    actions = [
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:GetItem",
    ]
    resources = [
      aws_dynamodb_table.results.arn,
      "${aws_dynamodb_table.results.arn}/index/by-recency",
    ]
  }
}

resource "aws_iam_role_policy" "read_api" {
  name   = "${var.project_name}-read-api-policy"
  role   = aws_iam_role.read_api.id
  policy = data.aws_iam_policy_document.read_api.json
}
