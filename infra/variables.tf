###############################################################################
# variables.tf  —  All input variables for the project.
#
# Required variables (no default) must be set in terraform.tfvars (gitignored).
# Copy terraform.tfvars.example → terraform.tfvars and fill in unique names.
###############################################################################

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short prefix applied to every resource name (e.g. smart-inbox)."
  type        = string
  default     = "smart-inbox"
}

variable "inbox_bucket_name" {
  description = "Globally unique S3 bucket name for incoming messages."
  type        = string
}

variable "frontend_bucket_name" {
  description = "Globally unique S3 bucket name for the CloudFront-served dashboard."
  type        = string
}

variable "alarm_email" {
  description = "Email address to notify when the ingest DLQ receives a failed message."
  type        = string
}
