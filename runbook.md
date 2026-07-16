# Serverless Smart Inbox — Runbook

Operational reference for deploying, operating, and rolling back the project.
Read alongside `action-plan.md` (build order) and `CLAUDE.md` (hard rules).

---

## Table of Contents

1. [Prerequisites Checklist](#1-prerequisites-checklist)
2. [One-Time AWS Setup (OIDC + IAM Deploy Role)](#2-one-time-aws-setup)
3. [GitHub Secrets Reference](#3-github-secrets-reference)
4. [CI Pipeline (`ci.yml`)](#4-ci-pipeline)
5. [Deploy Pipeline (`deploy.yml`)](#5-deploy-pipeline)
6. [Post-Deploy Verification](#6-post-deploy-verification)
7. [Error Handling by Stage](#7-error-handling-by-stage)
8. [Rollback Strategy](#8-rollback-strategy)
9. [Teardown](#9-teardown)

---

## 1. Prerequisites Checklist

Complete these once before any CI or deploy run will succeed.

### Local toolchain
- [ ] Node 20+ installed (`node --version`)
- [ ] pnpm 9+ installed (`pnpm --version`)
- [ ] Terraform >= 1.7 installed (`terraform version`)
- [ ] AWS CLI v2 installed and configured (`aws sts get-caller-identity`)
- [ ] `uv` installed (for seeder: `uv --version`)

### AWS account
- [ ] Billing alarm set ($1–$5 budget with email alert — do this first)
- [ ] Default region confirmed as `us-east-1`
- [ ] S3 state bucket created (Phase 1):
  ```bash
  aws s3 mb s3://<your-prefix>-tfstate-smart-inbox --region us-east-1
  aws s3api put-bucket-versioning \
    --bucket <your-prefix>-tfstate-smart-inbox \
    --versioning-configuration Status=Enabled
  ```
- [ ] DynamoDB lock table created (Phase 1):
  ```bash
  aws dynamodb create-table \
    --table-name <your-prefix>-tflock-smart-inbox \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region us-east-1
  ```
- [ ] `infra/backend.tf` created from `backend.tf.example` with real names (gitignored)
- [ ] `infra/terraform.tfvars` created from `terraform.tfvars.example` with real names (gitignored)
- [ ] `terraform init` succeeds locally
- [ ] OIDC provider + deploy role created (see §2)

### GitHub repository
- [ ] All six secrets in §3 are set
- [ ] (Optional) GitHub Environment named `production` created with a required reviewer for extra protection

---

## 2. One-Time AWS Setup

### Create the OIDC identity provider

Run once per AWS account. This lets GitHub Actions exchange a short-lived OIDC
token for temporary AWS credentials — no long-lived access keys anywhere.

```bash
aws iam create-open-id-connect-provider \
  --url "https://token.actions.githubusercontent.com" \
  --client-id-list "sts.amazonaws.com" \
  --thumbprint-list "6938fd4d98bab03faadb97b34396831e3780aea1"
```

Verify: `aws iam list-open-id-connect-providers`

### Create the deploy IAM role

Replace `<ACCOUNT_ID>` and `<GITHUB_ORG>/<GITHUB_REPO>` with your values.

**Trust policy** (`trust.json`):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:<GITHUB_ORG>/<GITHUB_REPO>:*"
        }
      }
    }
  ]
}
```

```bash
aws iam create-role \
  --role-name smart-inbox-github-deploy \
  --assume-role-policy-document file://trust.json

# Attach policies scoped to what Terraform needs to create/modify
aws iam attach-role-policy \
  --role-name smart-inbox-github-deploy \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

# For production: replace PowerUserAccess with a custom least-privilege policy
# that covers the specific services this project uses:
# S3, SQS, DynamoDB, Lambda, API Gateway, CloudFront, CloudWatch, SNS, IAM (roles only)
```

Copy the role ARN and store it as the `AWS_DEPLOY_ROLE_ARN` GitHub Secret.

---

## 3. GitHub Secrets Reference

**Settings → Secrets and variables → Actions → Repository secrets**

| Secret | Description | Example |
|--------|-------------|---------|
| `AWS_DEPLOY_ROLE_ARN` | ARN of the OIDC deploy role | `arn:aws:iam::123456789012:role/smart-inbox-github-deploy` |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state | `juice-tfstate-smart-inbox` |
| `TF_LOCK_TABLE` | DynamoDB lock table name | `juice-tflock-smart-inbox` |
| `TF_INBOX_BUCKET` | S3 bucket for incoming messages | `juice-smart-inbox-messages` |
| `TF_FRONTEND_BUCKET` | S3 bucket for the dashboard | `juice-smart-inbox-frontend` |
| `TF_ALARM_EMAIL` | Email for DLQ failure alerts | `you@example.com` |

> All six must be set before the deploy workflow can run. Missing secrets
> cause `terraform apply` to fail with an obscure variable error, not a
> clear "secret not found" message.

---

## 4. CI Pipeline

**File:** `.github/workflows/ci.yml`
**Triggers:** every push to `main`, every pull request.
**AWS access required:** No.

### Jobs

#### `web` — Frontend
| Step | Command | Purpose |
|------|---------|---------|
| Install | `pnpm install --frozen-lockfile` | Reproducible install; fails if lock file is out of sync |
| Lint | `pnpm run lint` | ESLint via `next lint` |
| Typecheck | `pnpm run typecheck` | `tsc --noEmit` — catches type errors without emitting files |
| Test | `pnpm run test:run` | Vitest in non-watch mode |
| Build | `pnpm run build` | Static export to `out/`; catches build-time errors early |

#### `infra` — Terraform
| Step | Command | Purpose |
|------|---------|---------|
| Format | `terraform fmt -check -recursive` | Enforces canonical HCL formatting |
| Init | `terraform init -backend=false` | Downloads providers, skips S3 backend |
| Validate | `terraform validate` | Checks types, references, required args |

#### `python` — Handlers
| Step | Command | Purpose |
|------|---------|---------|
| Lint | `ruff check handlers/ tooling/src/` | Style + common bugs |
| Compile | `python -m py_compile <file>` | Syntax check without executing |

### CI Checklist (before opening a PR)
- [ ] `pnpm run lint` passes locally
- [ ] `pnpm run typecheck` passes locally
- [ ] `pnpm run test:run` passes locally
- [ ] `terraform fmt -recursive infra/` run (auto-fixes formatting)
- [ ] `terraform validate` passes locally
- [ ] `ruff check handlers/ tooling/src/` passes locally

---

## 5. Deploy Pipeline

**File:** `.github/workflows/deploy.yml`
**Trigger:** Manual only — **Actions → Deploy → Run workflow**.

> This workflow runs `terraform apply`. It creates and modifies real AWS
> resources and incurs costs. Read the Terraform plan output in the logs
> before the apply step completes.

### Pre-deploy Checklist
- [ ] CI is green on the commit you intend to deploy
- [ ] All six GitHub Secrets are set (§3)
- [ ] You have reviewed any open Terraform plan from a recent local run
- [ ] No in-flight deployments (check the Actions tab for running workflows)
- [ ] SNS alarm email confirmed (you'll receive a subscription confirmation email on first deploy)

### Steps

| # | Step | What can go wrong |
|---|------|-------------------|
| 0 | **Confirm gate** | Input is not exactly `deploy` → workflow exits immediately |
| 1 | **Checkout** | Rare network issue → retry |
| 2 | **Tool setup** | Version unavailable → pin exact version in `env` block |
| 3 | **AWS OIDC** | Role ARN wrong / trust policy mismatch / OIDC provider not created → see §7 |
| 4 | **Write tfvars** | Missing secret → file written with empty string → Terraform error on apply |
| 5 | **Terraform init** | Wrong bucket/table name → state backend error → see §7 |
| 6 | **Terraform plan** | Provider error, missing variable, IAM permission denied → see §7 |
| 7 | **Terraform apply** | Resource conflict, quota exceeded, IAM denied → see §7 |
| 8 | **Capture outputs** | Output doesn't exist (resource not yet applied) → fix the .tf, re-apply |
| 9 | **pnpm install** | Lock file out of sync → run `pnpm install` locally and commit updated lock |
| 10 | **Next.js build** | Missing env var, TypeScript error, import error → fix and re-push |
| 11 | **S3 sync** | IAM denied `s3:PutObject` → check deploy role policy |
| 12 | **CF invalidation** | IAM denied `cloudfront:CreateInvalidation` → check deploy role policy |

### Post-deploy Checklist
- [ ] `terraform output` values look correct (correct bucket names, API URL)
- [ ] `curl "$(terraform output -raw api_endpoint)/messages?limit=5"` returns JSON
- [ ] CloudFront URL (`terraform output -raw dashboard_url`) loads the dashboard
- [ ] Dashboard top bar shows **"live"** (not the demo-data banner)
- [ ] Drop a test file and confirm it flows end-to-end:
  ```bash
  aws s3 cp tooling/samples/01-positive.txt \
    s3://$(terraform output -raw inbox_bucket)/inbox/test.txt
  # Wait ~5 seconds, then:
  aws dynamodb scan --table-name smart-inbox-results --max-items 3
  ```
- [ ] SNS subscription confirmation email received and confirmed
- [ ] CloudWatch dashboard visible at AWS Console → CloudWatch → Dashboards → `smart-inbox-overview`

---

## 6. Post-Deploy Verification

### Quick smoke test
```bash
# From infra/ after a successful deploy
API=$(terraform output -raw api_endpoint)
BUCKET=$(terraform output -raw inbox_bucket)
TABLE=$(terraform output -raw results_table)
CF_URL=$(terraform output -raw dashboard_url)

# 1. API responds
curl -s "$API/messages?limit=1" | python3 -m json.tool

# 2. Seed one message
aws s3 cp ../tooling/samples/02-negative.txt "s3://$BUCKET/inbox/smoke-test.txt"

# 3. Wait for Lambda to process (~5 s), then check DynamoDB
sleep 8
aws dynamodb scan --table-name "$TABLE" --max-items 1

# 4. Dashboard URL
echo "Dashboard: $CF_URL"
```

### What healthy looks like
- `GET /messages` returns `{"items": [...]}` with `sentiment` fields
- Each DynamoDB item has `id`, `text`, `sentiment`, `scores`, `timestamp`
- CloudWatch log group `/aws/lambda/smart-inbox-processor` has recent log streams
- DLQ (`smart-inbox-ingest-dlq`) depth is 0

---

## 7. Error Handling by Stage

### CI errors

#### `web` job

| Error | Cause | Fix |
|-------|-------|-----|
| `pnpm install` fails with lock file mismatch | Local pnpm version different from CI | Run `pnpm install` with pnpm 9 locally; commit updated `pnpm-lock.yaml` |
| ESLint error | Lint rule violation | Run `pnpm run lint` locally and fix reported issues |
| `tsc` error | Type mismatch | Run `pnpm run typecheck` locally; fix the type error |
| Vitest failure | Failing test | Run `pnpm run test:run` locally; fix the test or the code |
| Build error: `Image Optimization` | Using `<Image>` with static export | Replace `next/image` with plain `<img>` or configure `unoptimized: true` |

#### `infra` job

| Error | Cause | Fix |
|-------|-------|-----|
| `terraform fmt -check` fails | Unformatted HCL | Run `terraform fmt -recursive infra/` locally and commit |
| `Error: Invalid reference` | Referencing a resource that doesn't exist yet | Check resource name; may need `depends_on` or correct resource type |
| `Error: Missing required argument` | Required attribute missing from a resource | Check the Terraform docs for that resource type |
| Provider not found | `.terraform/` not in repo (expected), but `-backend=false` init failed | Ensure `hashicorp/aws ~> 5.90` is reachable from GitHub runners |

#### `python` job

| Error | Cause | Fix |
|-------|-------|-----|
| `ruff: E501 line too long` | Line exceeds 100 chars | Wrap or shorten the line |
| `ruff: F401 unused import` | Imported but not used | Remove the import |
| `py_compile` syntax error | Python syntax error | Fix the syntax; run `python -m py_compile <file>` locally |

---

### Deploy errors

#### OIDC / AWS auth

| Error | Cause | Fix |
|-------|-------|-----|
| `Could not assume role` | OIDC provider not created in the AWS account | Run the `aws iam create-open-id-connect-provider` command in §2 |
| `sub condition mismatch` | Trust policy has wrong repo name | Edit the trust policy: `repo:OWNER/REPO:*` must match exactly |
| `AccessDenied: sts:AssumeRoleWithWebIdentity` | OIDC provider ARN in trust policy is wrong | Verify the ARN with `aws iam list-open-id-connect-providers` |

#### Terraform init

| Error | Cause | Fix |
|-------|-------|-----|
| `NoSuchBucket` | `TF_STATE_BUCKET` secret wrong or bucket not created | Create the bucket (Phase 1 CLI commands) and verify the secret |
| `ResourceNotFoundException` | `TF_LOCK_TABLE` secret wrong or table not created | Create the DynamoDB table and verify the secret |
| `AccessDenied` | Deploy role lacks `s3:GetObject` on the state bucket | Add `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket` to the deploy role policy |

#### Terraform plan / apply

| Error | Cause | Fix |
|-------|-------|-----|
| `Error: Variable not set` | A tfvars key is missing or the Secret is empty | Verify all six secrets are set in GitHub; check `TF_INBOX_BUCKET` and `TF_FRONTEND_BUCKET` |
| `BucketAlreadyExists` | Bucket name is taken globally | Choose a more unique name in `TF_INBOX_BUCKET` / `TF_FRONTEND_BUCKET` |
| `ResourceConflict` on Lambda ESM | Event source mapping already exists | Run `terraform import` for the existing mapping, then re-apply |
| `AccessDenied` on apply | Deploy role missing a permission | Check the CloudTrail `AccessDenied` event for the exact action, add it to the role |
| `ConditionalCheckFailedException` (DynamoDB) | Idempotency condition failed | Check the processor handler's `ConditionExpression`; safe to retry |

#### Frontend build

| Error | Cause | Fix |
|-------|-------|-----|
| `NEXT_PUBLIC_API_URL is undefined` | Terraform output step failed silently | Check that `api_endpoint` output exists in `infra/outputs.tf`; verify the apply step succeeded |
| `Export encountered errors` | A page uses Node-only API not compatible with static export | Replace with browser-compatible code or add `export const dynamic = 'force-static'` |

#### S3 sync / CloudFront

| Error | Cause | Fix |
|-------|-------|-----|
| `AccessDenied` on `s3 sync` | Deploy role lacks `s3:PutObject` on the frontend bucket | Add the permission scoped to `arn:aws:s3:::FRONTEND_BUCKET/*` |
| `NoSuchDistribution` | CloudFront dist ID output is wrong | Verify the `cloudfront_distribution_id` Terraform output matches the real distribution |
| Dashboard shows old content after deploy | CloudFront invalidation did not propagate yet | Wait 1–2 minutes; invalidations typically complete in under 60 s |
| Dashboard shows demo-data banner after deploy | `NEXT_PUBLIC_API_URL` was empty during build | Re-run the deploy; the env var is baked in at build time |

---

## 8. Rollback Strategy

### Principles
- The **fastest rollback is always to re-deploy the last known-good commit**.
- Terraform state is versioned in S3 — previous state files can be restored.
- DynamoDB writes are **not rolled back** (they are append-only records; rolling back doesn't make sense for message data).
- CloudFront propagates in ~1 min; wait before declaring a rollback complete.

---

### Frontend rollback (fastest — ~3 min)

The dashboard is a static export. Rolling back means syncing the previous build to S3.

**Option A — Re-deploy from a previous commit:**
1. Find the last good commit SHA: `git log --oneline`
2. Open **Actions → Deploy → Run workflow**
3. In the branch/tag field, enter the commit SHA or tag
4. Type `deploy` and trigger

**Option B — Manual sync from a local build (if CI is broken):**
```bash
git checkout <last-good-sha>
cd apps/web
NEXT_PUBLIC_API_URL=$(cd ../../infra && terraform output -raw api_endpoint) \
  pnpm run build

aws s3 sync out/ s3://$(cd ../../infra && terraform output -raw frontend_bucket) --delete

aws cloudfront create-invalidation \
  --distribution-id $(cd ../../infra && terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

---

### Lambda / backend rollback (~5–10 min)

Lambda code is packaged from `handlers/` by Terraform. Rolling back means deploying the previous handler code.

**Steps:**
1. `git revert <bad-commit-sha>` (or `git checkout <sha> -- handlers/`)
2. Commit and push
3. Trigger the deploy workflow — Terraform detects the source code hash change and redeploys the Lambda

**Emergency manual rollback (without a deploy run):**
```bash
# From the infra/ directory, with your local AWS credentials
git checkout <last-good-sha> -- ../handlers/
terraform apply -target=aws_lambda_function.processor -target=aws_lambda_function.read_api
```

---

### Terraform infrastructure rollback

> Use this only if `terraform apply` partially applied and left resources in
> an inconsistent state. Do not run `terraform destroy` unless you intend to
> tear everything down.

**Option A — Restore previous state from S3 versioning:**
```bash
# List state versions
aws s3api list-object-versions \
  --bucket <TF_STATE_BUCKET> \
  --prefix smart-inbox/terraform.tfstate

# Restore a specific version
aws s3api get-object \
  --bucket <TF_STATE_BUCKET> \
  --key smart-inbox/terraform.tfstate \
  --version-id <VERSION_ID> \
  terraform.tfstate.backup

# Replace the current state (DANGEROUS — coordinate with anyone else who might apply)
aws s3 cp terraform.tfstate.backup \
  s3://<TF_STATE_BUCKET>/smart-inbox/terraform.tfstate
```

**Option B — Targeted destroy + re-apply of a specific broken resource:**
```bash
# Example: the Lambda event source mapping is stuck
terraform destroy -target=aws_lambda_event_source_mapping.ingest
terraform apply -target=aws_lambda_event_source_mapping.ingest
```

**Option C — Revert the Terraform code and re-apply:**
```bash
git revert <bad-commit-sha>   # reverts the .tf changes
cd infra && terraform apply   # brings infra back to match previous code
```

---

### Rollback decision tree

```
Problem observed
│
├─ Dashboard shows wrong content / 404
│   └─ Frontend rollback (Option A above — re-deploy from last good commit)
│
├─ API returns errors / Lambda throwing exceptions
│   ├─ Check CloudWatch logs: /aws/lambda/smart-inbox-processor
│   └─ Lambda rollback (revert handler code → trigger deploy)
│
├─ Messages not flowing S3 → SQS → Lambda
│   ├─ Check ingest DLQ depth > 0?
│   │   └─ Yes → check Lambda logs for the failure reason
│   └─ Check S3 bucket notification config is still attached
│
├─ terraform apply failed partway
│   ├─ Run `terraform plan` to see drift
│   └─ Use targeted destroy + re-apply (Option B above)
│
└─ Complete outage / unknown state
    └─ Restore previous Terraform state (Option A above) then re-apply
```

---

## 9. Teardown

When the project is done. **Do not skip — this is how "free" stays free.**

### Checklist
- [ ] Empty both S3 buckets (destroy will fail on non-empty buckets):
  ```bash
  aws s3 rm s3://$(terraform output -raw inbox_bucket) --recursive
  aws s3 rm s3://$(terraform output -raw frontend_bucket) --recursive
  ```
- [ ] `cd infra && terraform destroy` — type `yes` when prompted
- [ ] Verify in AWS Console: Lambdas, SQS queues, DynamoDB table, CloudFront distribution, API Gateway, CloudWatch log groups — all gone
- [ ] Optionally delete the state bucket and lock table:
  ```bash
  aws s3 rb s3://<TF_STATE_BUCKET> --force
  aws dynamodb delete-table --table-name <TF_LOCK_TABLE>
  ```
- [ ] Remove the OIDC provider and deploy role if no longer needed:
  ```bash
  aws iam detach-role-policy --role-name smart-inbox-github-deploy \
    --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
  aws iam delete-role --role-name smart-inbox-github-deploy
  ```
- [ ] Check AWS Billing the next day — should show $0 for all project resources

---

*Last updated: 2026-07-14*
