###############################################################################
# S3  —  Phase 2 (inbox bucket) and Phase 8 (frontend bucket).
###############################################################################

# --- Inbox bucket (Phase 2) -------------------------------------------------

resource "aws_s3_bucket" "inbox" {
  bucket = var.inbox_bucket_name
}

# Block all forms of public access. Messages are internal pipeline data —
# nothing here should ever be public.
resource "aws_s3_bucket_public_access_block" "inbox" {
  bucket = aws_s3_bucket.inbox.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Fire an SQS notification for every object created in the bucket.
# depends_on enforces that the queue policy exists before this resource is
# applied; without it, S3 will reject the notification config because it
# can't verify send permission on the queue.
resource "aws_s3_bucket_notification" "inbox" {
  bucket = aws_s3_bucket.inbox.id

  queue {
    queue_arn = aws_sqs_queue.ingest.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sqs_queue_policy.ingest_from_s3]
}

# --- Frontend bucket (Phase 8) -----------------------------------------------
# Serves the Next.js static export via CloudFront with OAC.
# The bucket itself stays fully private — CloudFront is the only reader.

resource "aws_s3_bucket" "frontend" {
  bucket = var.frontend_bucket_name
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket = aws_s3_bucket.frontend.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# OAC bucket policy lives in cloudfront.tf (needs the distribution ARN).
