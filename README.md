# Serverless Smart Inbox

Real-time sentiment monitoring for incoming messages, built serverless on AWS.
Messages land in S3, a Lambda scores them with Amazon Comprehend, the result is
routed by sentiment through SQS and persisted to DynamoDB, and a Next.js console
visualizes the stream live.

A portfolio project for cloud / DevOps: event-driven architecture, IaC, least-
privilege IAM, a dead-letter queue, and observability — designed to run inside the
AWS Free Tier.

## Architecture

```
                    ObjectCreated
   ┌─────────┐  event   ┌──────────────┐   poll    ┌───────────────────────┐
   │   S3    │─────────▶│  SQS ingest  │──────────▶│   Lambda: processor   │
   │  inbox  │          │  (+ DLQ)     │  (batch)  │  Comprehend sentiment │
   └─────────┘          └──────────────┘           └───────────┬───────────┘
                                                                │
                              route by sentiment ┌──────────────┼─────────────┐
                                                 ▼              ▼             ▼
                                          ┌────────────┐  ┌──────────┐  ┌──────────┐
                                          │ SQS pos /  │  │ DynamoDB │  │   ...    │
                                          │ neg / neu /│  │ results  │  │          │
                                          │ mixed      │  └────┬─────┘  └──────────┘
                                          └────────────┘       │ read
                                                               ▼
   ┌───────────────────┐   GET /messages   ┌────────────────────────────┐
   │ CloudFront + S3   │◀──────────────────│  API Gateway + read Lambda │
   │ (Next.js console) │                   └────────────────────────────┘
   └───────────────────┘
```

**Why S3 → SQS → Lambda** (instead of S3 triggering Lambda directly): the queue
gives you a retry buffer, batching, backpressure, and a dead-letter queue for
poison messages. Direct invocation gives you none of that.

## Repo layout

```
apps/web/        Next.js dashboard (static export → S3 + CloudFront)
functions/       Lambda source (Python) — processor + read_api   [handlers: YOU build]
infra/           Terraform skeleton — resource bodies are TODOs   [YOU build]
tooling/         Python seeder + sample messages (uv)
action-plan.md   Internal phase-by-phase build guide (gitignored)
```

This repo is a **skeleton**. The dashboard and seeder are complete and runnable.
The Lambda handlers, the Terraform resource bodies, and CI/CD are intentionally
left for you to build — see `action-plan.md`.

## Run the dashboard locally (no AWS needed)

```bash
cd apps/web
npm install
npm run dev          # http://localhost:3000
```

With no `NEXT_PUBLIC_API_URL` set, the dashboard runs on built-in mock data so you
can develop and demo the UI with zero backend.

## Prerequisites for the full build

- Node 20+ (`apps/web/.nvmrc`)
- Terraform ≥ 1.7
- AWS CLI, configured with credentials (`aws configure`)
- Python 3.12 + [`uv`](https://docs.astral.sh/uv/) (for the seeder)
- An AWS account (everything here targets the Free Tier)

## Deploy (you run this — from your machine, with your credentials)

Full step-by-step lives in `action-plan.md`. The short version:

```bash
# 1. State backend (one-time): create an S3 state bucket + DynamoDB lock table,
#    then: cd infra && cp backend.tf.example backend.tf  (fill in names)

# 2. Vars
cp infra/terraform.tfvars.example infra/terraform.tfvars   # set unique bucket names

# 3. Build the infra (after you've filled in the resource bodies)
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
RDS, or Fargate** — those are the things that bill 24/7, and this project avoids
all of them on purpose. Honest caveats:

- **Comprehend**'s 5M-character free tier is first-12-months only; after that it's
  ~$0.0001/unit. Pennies for a demo, but not literally zero forever.
- The real risk on a "free" project is **leaving it running**. When you're done,
  `terraform destroy` (see the cleanup phase) tears it down. Empty the S3 buckets
  first or destroy will refuse.

## Cleanup

```bash
aws s3 rm s3://<inbox_bucket> --recursive
aws s3 rm s3://<frontend_bucket> --recursive
cd infra && terraform destroy
```

Then confirm in the console that the S3 buckets, DynamoDB table, Lambdas, queues,
and CloudFront distribution are gone, and check Billing the next day.
