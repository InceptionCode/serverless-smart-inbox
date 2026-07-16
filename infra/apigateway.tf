###############################################################################
# API Gateway HTTP API  —  Phase 7.
#
# HTTP API (v2) is used over REST API (v1):
#   - ~70% cheaper per million requests
#   - Built-in Lambda proxy integration (no mapping templates)
#   - Lower latency for simple GET endpoints
#
# Route: GET /messages → read_api Lambda (proxy integration)
# Stage: $default — auto-deployed, no manual stage management needed
###############################################################################

# ---------------------------------------------------------------------------
# HTTP API
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "read_api" {
  name          = "${var.project_name}-read-api"
  protocol_type = "HTTP"
  description   = "Read API for the smart inbox dashboard."

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
    max_age       = 300
  }
}

# ---------------------------------------------------------------------------
# Lambda integration — proxy mode forwards the full request to Lambda and
# returns whatever the function returns as the HTTP response.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_integration" "read_api" {
  api_id             = aws_apigatewayv2_api.read_api.id
  integration_type   = "AWS_PROXY"
  integration_uri    = aws_lambda_function.read_api.invoke_arn
  integration_method = "POST" # API GW always uses POST when invoking Lambda

  payload_format_version = "2.0" # matches event["version"] = "2.0" in the handler
}

# ---------------------------------------------------------------------------
# Route: GET /messages
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_route" "get_messages" {
  api_id    = aws_apigatewayv2_api.read_api.id
  route_key = "GET /messages"
  target    = "integrations/${aws_apigatewayv2_integration.read_api.id}"
}

# ---------------------------------------------------------------------------
# Stage: $default — auto-deployed on every change, no manual deploys needed.
# ---------------------------------------------------------------------------

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.read_api.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      durationMs     = "$context.responseLatency"
      sourceIp       = "$context.identity.sourceIp"
      errorMessage   = "$context.error.message"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/${var.project_name}-read-api"
  retention_in_days = 30
}

# ---------------------------------------------------------------------------
# Lambda resource-based policy — grants API Gateway permission to invoke the
# read_api Lambda. Without this, API GW gets a 403 from Lambda even if the
# execution role is correct. This is separate from IAM — it's a resource
# policy on the Lambda function itself.
# ---------------------------------------------------------------------------

resource "aws_lambda_permission" "apigw_invoke_read_api" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.read_api.function_name
  principal     = "apigateway.amazonaws.com"

  # Scope to this specific API only — prevents other APIs in the account
  # from invoking this function without an explicit permission.
  source_arn = "${aws_apigatewayv2_api.read_api.execution_arn}/*/*"
}
