###############################################################################
# CloudFront  —  Phase 8.  Static dashboard via S3 + OAC.
#
# Architecture:
#   Browser → CloudFront distribution → S3 frontend bucket (private)
#
# Origin Access Control (OAC) is the modern replacement for Origin Access
# Identity (OAI). OAC signs requests to S3 with SigV4, scoped to this
# specific distribution — no other CloudFront distribution can read the bucket
# even if they know its name.
#
# Price class PriceClass_100 (US + Europe edge locations) keeps this inside
# the free tier footprint and is appropriate for a portfolio project.
###############################################################################

# ---------------------------------------------------------------------------
# Origin Access Control
# ---------------------------------------------------------------------------

resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-frontend-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------------------------------------------------------------------------
# CloudFront distribution
# ---------------------------------------------------------------------------

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  default_root_object = "index.html"
  comment             = "${var.project_name} dashboard"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS managed CachingOptimized policy — good defaults for static assets.
    # ID is stable across all accounts/regions.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  # S3 with OAC returns 403 (not 404) when an object doesn't exist, because
  # the bucket denies all unauthenticated requests. Map both to the root so
  # the dashboard always loads cleanly on any path.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ---------------------------------------------------------------------------
# S3 bucket policy — grants this CloudFront distribution read access.
# Must live here (not s3.tf) because it references the distribution ARN,
# which is only known after the distribution resource is created.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "frontend_oac" {
  statement {
    sid    = "AllowCloudFrontOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    # Scope to this specific distribution — prevents any other CloudFront
    # distribution from reading the bucket using the same OAC service principal.
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_oac" {
  bucket = aws_s3_bucket.frontend.id
  policy = data.aws_iam_policy_document.frontend_oac.json

  # Block public access must be configured before a bucket policy can be applied.
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}
