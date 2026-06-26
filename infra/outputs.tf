###############################################################################
# outputs.tf  —  Uncomment each block when its resource exists.
#
# Phase 2: inbox_bucket
# Phase 7: api_endpoint
# Phase 8: frontend_bucket, dashboard_url
###############################################################################

output "inbox_bucket" {
  description = "Name of the S3 inbox bucket."
  value       = aws_s3_bucket.inbox.bucket
}

output "results_table" {
  description = "Name of the DynamoDB results table."
  value       = aws_dynamodb_table.results.name
}

# output "api_endpoint" {
#   description = "Base URL for the API Gateway HTTP API (no trailing slash)."
#   value       = aws_apigatewayv2_api.read_api.api_endpoint
# }

# output "frontend_bucket" {
#   description = "Name of the CloudFront frontend S3 bucket."
#   value       = aws_s3_bucket.frontend.bucket
# }

# output "dashboard_url" {
#   description = "HTTPS URL of the live dashboard via CloudFront."
#   value       = "https://${aws_cloudfront_distribution.frontend.domain_name}"
# }
