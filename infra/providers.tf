###############################################################################
# providers.tf  —  Terraform core config + AWS provider.
#
# Backend lives in backend.tf (gitignored — copy from backend.tf.example).
# Pin the provider version here; bump deliberately, never automatically.
###############################################################################

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.90"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

# Available to any resource that needs the current account ID or region.
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
