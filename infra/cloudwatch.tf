###############################################################################
# CloudWatch  —  Phase 9.  Alarms + dashboard.
#
# Log groups for both Lambdas are managed in lambda.tf (co-located with the
# functions that write to them). This file owns:
#   - SNS topic + email subscription for alarm notifications
#   - DLQ depth alarm  (anything here means a message failed all 5 retries)
#   - CloudWatch dashboard  (the portfolio screenshot)
###############################################################################

# ---------------------------------------------------------------------------
# SNS topic — alarm notifications
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alarms" {
  name = "${var.project_name}-alarms"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# ---------------------------------------------------------------------------
# DLQ depth alarm
#
# Fires when ApproximateNumberOfMessagesVisible > 0 on the ingest DLQ.
# This means at least one message exhausted all 5 retries — something the
# processor couldn't handle even with retries. Requires investigation.
#
# Period = 60 s, 1 datapoint to alarm: catches failures within one minute.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.project_name}-ingest-dlq-depth"
  alarm_description   = "One or more messages have exhausted all retries and landed in the ingest DLQ."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.ingest_dlq.name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
}

# ---------------------------------------------------------------------------
# CloudWatch dashboard
#
# Sections:
#   Row 1 — Processor Lambda: invocations/errors/throttles, duration p50/p99
#   Row 1 — Read API Lambda:  invocations/errors, duration p50/p99
#   Row 2 — Ingest queue:     messages sent, backlog (visible + in-flight)
#   Row 2 — DLQ:              depth (should always be 0)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-overview"

  dashboard_body = jsonencode({
    widgets = [

      # ── Processor: Invocations / Errors / Throttles ───────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 6
        height = 6
        properties = {
          title  = "Processor — Invocations & Errors"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-processor"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-processor", { color = "#d62728" }],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-processor", { color = "#ff7f0e" }]
          ]
        }
      },

      # ── Processor: Duration ───────────────────────────────────────────────
      {
        type   = "metric"
        x      = 6
        y      = 0
        width  = 6
        height = 6
        properties = {
          title  = "Processor — Duration p50 / p99 (ms)"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-processor", { stat = "p50" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-processor", { stat = "p99", color = "#d62728" }]
          ]
        }
      },

      # ── Read API: Invocations / Errors ────────────────────────────────────
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 6
        height = 6
        properties = {
          title  = "Read API — Invocations & Errors"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-read-api"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-read-api", { color = "#d62728" }]
          ]
        }
      },

      # ── Read API: Duration ────────────────────────────────────────────────
      {
        type   = "metric"
        x      = 18
        y      = 0
        width  = 6
        height = 6
        properties = {
          title  = "Read API — Duration p50 / p99 (ms)"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-read-api", { stat = "p50" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-read-api", { stat = "p99", color = "#d62728" }]
          ]
        }
      },

      # ── Ingest Queue: Messages Sent ───────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Ingest Queue — Messages Sent"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/SQS", "NumberOfMessagesSent", "QueueName", "${var.project_name}-ingest"]
          ]
        }
      },

      # ── Ingest Queue: Backlog ─────────────────────────────────────────────
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Ingest Queue — Backlog"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-ingest"],
            ["AWS/SQS", "ApproximateNumberOfMessagesNotVisible", "QueueName", "${var.project_name}-ingest", { color = "#ff7f0e" }]
          ]
        }
      },

      # ── DLQ Depth (should always be 0) ───────────────────────────────────
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "DLQ — Depth (should be 0)"
          view   = "timeSeries"
          region = var.aws_region
          period = 60
          stat   = "Maximum"
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", "${var.project_name}-ingest-dlq", { color = "#d62728" }]
          ]
          annotations = {
            horizontal = [{ value = 1, label = "ALARM threshold", color = "#d62728" }]
          }
        }
      }

    ]
  })
}
