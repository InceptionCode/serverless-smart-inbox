# Serverless Smart Inbox

Real-time sentiment monitoring for incoming messages, built serverless on AWS.
Messages land in S3, a Lambda scores them with Amazon Comprehend, the result is
routed by sentiment through SQS and persisted to DynamoDB, and a Next.js console
visualizes the stream live.

A portfolio project for cloud / DevOps: event-driven architecture, IaC, least-
privilege IAM, a dead-letter queue, observability, and a gated CI/CD pipeline,
designed to run inside the AWS Free Tier.

> **Status: example project, not actively deployed.**
> This stack was built, deployed end-to-end to AWS, recorded, and then torn down
> with `terraform destroy` so it doesn't keep costing money. There is no live URL.
> The video below shows it running for real. Everything needed to bring it back
> up is in this repo (see [Deploy](#deploy)).

## Video proof of deployment

**[▶ Watch the deployment walkthrough (Google Drive)](https://drive.google.com/file/d/1-fF4w0n-dECjFi3nNe3KW-pgyT2zmief/view?usp=sharing)**

The recording shows the deployed stack working end to end: messages seeded into
the S3 inbox, scored by the processor Lambda, and showing up live on the
CloudFront-hosted dashboard.

## Architecture

```
                    ObjectCreated
   ┌─────────┐  event   ┌──────────────┐   poll    ┌───────────────────────┐
   │   S3    │─────────▶│  SQS ingest  │──────────▶│   Lambda: processor   │
   │  inbox  │          │  (+ DLQ)     │  (batch)  │  Comprehend sentiment │
   └─────────┘          └──────────────┘           └───────────┬───────────┘
                                                                │
                                  route by sentiment ┌──────────┴──────────┐
                                                     ▼                     ▼
                                          ┌────────────────────┐    ┌──────────┐
                                          │ SQS route-positive │    │ DynamoDB │
                                          │ / negative /       │    │ results  │
                                          │ neutral / mixed    │    └────┬─────┘
                                          └────────────────────┘         │ Query (GSI)
                                                                         ▼
   ┌───────────────────┐   GET /messages   ┌────────────────────────────┐
   │ CloudFront + S3   │◀──────────────────│  API Gateway + read Lambda │
   │ (Next.js console) │   (poll every 4s) └────────────────────────────┘
   └───────────────────┘
```

**Why S3 → SQS → Lambda** (instead of S3 triggering Lambda directly): the queue
gives you a retry buffer, batching, backpressure, and a dead-letter queue for
poison messages. Direct invocation gives you none of that.

## How a message flows through the system

1. **Ingest.** A text file is written to the private inbox S3 bucket (the seeder
   script does this for demos). S3 fires an `ObjectCreated` notification to the
   ingest SQS queue. A queue resource policy only accepts messages from that
   exact bucket in that exact account, which blocks confused-deputy attacks.
2. **Buffer and retry.** The ingest queue has a 180 s visibility timeout (well
   above the Lambda's 30 s timeout) and a redrive policy: after 5 failed receives
   a message moves to the dead-letter queue.
3. **Process.** An event source mapping hands the processor Lambda batches of up
   to 10 messages (5 s batching window). For each record it:
   - unwraps the S3 event from the SQS body and reads up to 5 KB of the object,
   - calls `comprehend:DetectSentiment` to get a label (`POSITIVE`, `NEGATIVE`,
     `NEUTRAL`, `MIXED`) and per-class scores,
   - writes the record to DynamoDB with `attribute_not_exists(id)`, so
     redelivered messages are detected and skipped (idempotent writes),
   - forwards the record to the matching `route-<sentiment>` SQS queue, where
     downstream consumers (alerts, support tooling, etc.) could subscribe.
4. **Partial batch failure.** The handler returns `batchItemFailures`, so one bad
   record goes back to the queue on its own and the rest of the batch still
   succeeds.
5. **Read.** The dashboard calls `GET /messages` on an API Gateway HTTP API. The
   read Lambda queries the `by-recency` GSI newest-first (`ScanIndexForward=False`,
   default 60 items, capped at 200), converts DynamoDB `Decimal`s to floats and
   returns JSON with CORS headers.
6. **Visualize.** The Next.js console, a static export served from a private S3
   bucket through CloudFront, polls the API every 4 seconds and renders the live
   feed, per-sentiment counts and filters.

## Component breakdown

| Layer | AWS service | Where | Notes |
| --- | --- | --- | --- |
| Inbox storage | S3 | [infra/s3.tf](infra/s3.tf) | Public access fully blocked; `ObjectCreated:*` → ingest queue |
| Queueing | SQS (ingest + DLQ + 4 routing queues) | [infra/sqs.tf](infra/sqs.tf) | Redrive after 5 receives; routing queues created with `for_each` |
| Sentiment scoring | Lambda (Python 3.12) + Comprehend | [handlers/processor/](handlers/processor/), [infra/lambda.tf](infra/lambda.tf) | 256 MB / 30 s; partial batch failure reporting |
| Results store | DynamoDB (on-demand) | [infra/dynamodb.tf](infra/dynamodb.tf) | PK `id` = `{s3_key}#{version_id}`; GSI `by-recency` on `pk` + `receivedAt` |
| Read API | API Gateway HTTP API + Lambda | [handlers/read_api/](handlers/read_api/), [infra/apigateway.tf](infra/apigateway.tf) | HTTP API (v2) for lower cost than REST; access logs to CloudWatch |
| Dashboard | Next.js 15 static export on S3 + CloudFront | [apps/web/](apps/web/), [infra/cloudfront.tf](infra/cloudfront.tf) | Origin Access Control (SigV4) scoped to the one distribution; HTTPS redirect |
| Permissions | IAM | [infra/iam.tf](infra/iam.tf) | One role per Lambda, each action scoped to specific ARNs |
| Observability | CloudWatch + SNS | [infra/cloudwatch.tf](infra/cloudwatch.tf) | 30-day log retention, DLQ-depth alarm → email, overview dashboard |
| CI/CD | GitHub Actions + OIDC | [.github/workflows/](.github/workflows/) | No long-lived AWS keys; deploy is manual and confirmed |
| Demo driver | Python + boto3 (uv) | [tooling/](tooling/) | Uploads sample messages to the inbox bucket |

### The data contract

[apps/web/lib/types.ts](apps/web/lib/types.ts) defines the record shape. The
processor writes it, the read API returns it, and the dashboard renders it:

```ts
interface MessageRecord {
  id: string;          // "{s3_key}#{version_id}"
  snippet: string;     // first 280 chars of the message
  sentiment: "POSITIVE" | "NEUTRAL" | "NEGATIVE" | "MIXED";
  confidence: number;  // Comprehend score for the winning label, 0–1
  source: string;      // S3 object key
  receivedAt: string;  // ISO 8601 S3 event time
}
```

DynamoDB stores scores as `Decimal`. Both Lambdas share a `decimals_to_float`
helper so JSON serialization works on the way out.

### Security decisions

- **Least-privilege IAM.** The processor can only `GetObject` in the inbox bucket,
  consume the ingest queue, `SendMessage` to the four routing queues, `PutItem` on
  the results table and write to its own log group. The read API only has
  read access (`Query`, `Scan`, `GetItem`) to the results table. The single `"*"` resource is `comprehend:DetectSentiment`,
  because Comprehend has no resource-level permissions.
- **No public buckets.** Both buckets block all public access. CloudFront reads
  the frontend bucket through OAC, conditioned on the distribution ARN.
- **Scoped invoke permissions.** API Gateway can invoke the read Lambda only from
  this API's execution ARN.
- **No secrets in the repo.** `backend.tf`, `*.tfvars` and `.env` files are
  gitignored. CI authenticates to AWS with GitHub OIDC and writes backend and
  variable files from repository secrets at runtime.

### Observability

- Structured, prefixed log lines (`[PROCESSING]`, `[COMPREHEND OK]`, `[DUPLICATE]`,
  `[ROUTED]`, `[FAILED]`…) make a single message easy to trace in CloudWatch Logs.
- A CloudWatch alarm fires by email (SNS) if anything reaches the dead-letter
  queue.
- A CloudWatch dashboard tracks Lambda invocations, errors, throttles and p50/p99
  duration, plus ingest queue throughput, backlog and DLQ depth.

### CI/CD

- **`ci.yml`** runs on every push and PR: frontend lint, type-check, Vitest unit
  tests and static build; `terraform fmt -check` and `validate`; `ruff` and a
  compile check on the Python handlers.
- **`deploy.yml`** runs only on manual dispatch, and you have to type `deploy` to
  confirm. It assumes an AWS role over OIDC, runs `terraform plan` and `apply`,
  builds the dashboard with the live API URL, syncs it to S3 with separate cache
  headers for hashed assets and for HTML/JSON, and invalidates CloudFront.

Operational details (OIDC setup, secrets, rollback, teardown) are in
[runbook.md](runbook.md).

## Repo layout

```
apps/web/        Next.js dashboard (static export → S3 + CloudFront)
handlers/        Lambda source (Python): processor + read_api
infra/           Terraform: one file per concern (s3, sqs, lambda, iam, ...)
tooling/         Python seeder + sample messages (uv)
.github/         CI and gated deploy workflows
runbook.md       Deploy, verify, rollback and teardown procedures
```

Who built what: I wrote the Lambda handlers, the Terraform and the CI/CD
pipelines. The dashboard UI was AI-generated, and the seeder was a joint effort.

## Run the dashboard locally (no AWS needed)

```bash
cd apps/web
npm install
npm run dev          # http://localhost:3000
```

With no `NEXT_PUBLIC_API_URL` set, the dashboard runs on built-in mock data, so
you can explore the UI without a backend. Since the project is no longer
deployed, this is the easiest way to see it.

## Prerequisites for a full deploy

- Node 20+ (`apps/web/.nvmrc`)
- Terraform ≥ 1.7
- AWS CLI, configured with credentials (`aws configure`)
- Python 3.12 + [`uv`](https://docs.astral.sh/uv/) (for the seeder)
- An AWS account (everything here targets the Free Tier)

## Deploy

To redeploy it yourself, either run the `Deploy` GitHub Actions workflow (see
[runbook.md](runbook.md)) or do it by hand:

```bash
# 1. State backend (one-time): create an S3 state bucket + DynamoDB lock table,
#    then: cd infra && cp backend.tf.example backend.tf  (fill in names)

# 2. Vars
cp infra/terraform.tfvars.example infra/terraform.tfvars   # set unique bucket names + alarm email

# 3. Build the infra
cd infra
terraform init
terraform plan
terraform apply

# 4. Ship the dashboard
cd ../apps/web
echo "NEXT_PUBLIC_API_URL=<api_endpoint from terraform output>" > .env.local
npm install && npm run build           # produces out/
aws s3 sync out/ s3://<frontend_bucket> --delete
aws cloudfront create-invalidation --distribution-id <id> --paths '/*'

# 5. Drive it
cd ../../tooling
uv sync
uv run python src/seed_messages.py --bucket <inbox_bucket> --count 12
```

## Cost

Designed for ~$0 idle under the Free Tier. There is **no VPC, NAT gateway, ALB,
RDS, or Fargate**. Those are the services that bill around the clock, and this
project leaves them out on purpose. Caveats:

- **Comprehend**'s 5M-character free tier is first-12-months only; after that it's
  ~$0.0001/unit. Pennies for a demo, but not literally zero forever.
- The real risk on a "free" project is **leaving it running**, which is why this
  one has been torn down now that it has been demonstrated.

## Cleanup

```bash
aws s3 rm s3://<inbox_bucket> --recursive
aws s3 rm s3://<frontend_bucket> --recursive
cd infra && terraform destroy
```

Then confirm in the console that the S3 buckets, DynamoDB table, Lambdas, queues,
and CloudFront distribution are gone, and check Billing the next day.
