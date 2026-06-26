###############################################################################
# DynamoDB  —  Phase 3 (results table).
#
# Design notes:
#   Primary key  : id (S)  — set by the processor as "{s3_key}#{version_id}".
#                            The ConditionExpression "attribute_not_exists(id)"
#                            on put_item makes writes idempotent.
#
#   GSI by-recency          — enables cheap newest-first reads in the read API.
#     hash_key  : pk (S)   — every item gets pk = "MSG" (single logical shard).
#                            Fine for demo traffic; for prod, shard by date.
#     range_key : receivedAt (S) — ISO 8601 string; lexicographic sort == time.
#     projection: ALL       — the dashboard needs every attribute.
#
#   Query vs Scan talking point:
#     Without the GSI, read_api must Scan the whole table and sort in Python —
#     O(n) reads and RCUs. With the GSI, a single Query with
#     ScanIndexForward=False returns the N newest items directly — O(log n)
#     plus exactly the RCUs you consume. This is the senior-engineer story.
###############################################################################

resource "aws_dynamodb_table" "results" {
  name         = "${var.project_name}-results"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  # Only attributes used as key or index keys are declared here.
  # DynamoDB is schemaless — all other fields (snippet, sentiment, etc.)
  # are written by the processor without needing to be declared.
  attribute {
    name = "id"
    type = "S"
  }

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "receivedAt"
    type = "S"
  }

  global_secondary_index {
    name            = "by-recency"
    hash_key        = "pk"
    range_key       = "receivedAt"
    projection_type = "ALL"
  }
}
