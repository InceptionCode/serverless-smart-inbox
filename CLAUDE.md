# CLAUDE.md — Serverless Smart Inbox

Project memory for Claude Code. Read this before doing anything in this repo.

## What this is

A serverless, event-driven sentiment pipeline on AWS, built as a cloud/DevOps
portfolio piece. Messages land in S3 → SQS ingest queue → a Lambda scores them
with Amazon Comprehend → routes by sentiment to SQS queues + writes DynamoDB → a
Next.js console (S3 + CloudFront) visualizes the stream live via API Gateway.

It must stay inside the AWS Free Tier. No VPC, NAT, ALB, RDS, or Fargate — ever.

## Build order (follow `action-plan.md`)

The full phase-by-phase guide is in `action-plan.md` (gitignored, local-only).
Work the phases in order. Do not build a component before its dependencies exist
(e.g. the processor Lambda needs the ingest queue from Phase 2 first).

Current state of the repo:

- `apps/web/` — Next.js dashboard. COMPLETE and runnable (mock-data fallback).
- `tooling/` — Python seeder + samples. COMPLETE.
- `handlers/processor/handler.py` — STUB. Build per its docstring + Phase 5.
- `handlers/read_api/handler.py` — STUB. Build per its docstring + Phase 7.
- `infra/*.tf` — SKELETON. Boilerplate done; resource bodies are commented TODOs.
- CI/CD — not written yet. Phase 10. The human writes this; don't auto-generate it
  unless asked.

## The data contract (do not break it)

`apps/web/lib/types.ts` is the source of truth for the record shape. The processor
Lambda writes it, the read_api Lambda returns it, the dashboard renders it. If you
change a field name, change it in all three. DynamoDB needs scores as `Decimal`,
not float; convert back to number in read_api before `json.dumps`.

## Always Do First

- **Invoke the `frontend-design` skill and `ui-ux-pro-max` skill as well** before writing any frontend code, every session, no exceptions.

## Hard rules

1. **Never deploy autonomously.** Do NOT run `terraform apply`, `terraform destroy`,
   `aws s3 sync`, image pushes, or any command that creates/changes/destroys AWS
   resources on your own. Propose the command, explain what it does, and let the
   human run it (or explicitly approve it) after they've read the plan. Surprise
   AWS bills and irreversible changes are the failure mode we're avoiding.
2. **`terraform plan` and `validate` are fine to run** for feedback. `apply` is the
   human's call, every time.
3. **Never write real secrets, account IDs, ARNs, or keys** into committed files.
   Use the `.example` files. Real `.env`, `*.tfvars`, `*.tfstate`, `backend.tf` are
   gitignored — keep it that way.
4. **Least privilege in IAM.** No `"*"` resources. Scope every action to specific ARNs.
5. **Match the house conventions** already in the repo — pinned versions, the tag
   set in `providers.tf`, the file split in `infra/`.

## Useful commands

```bash
# Dashboard (no AWS needed — runs on mock data)
cd apps/web && npm install && npm run dev

# Terraform feedback (safe)
cd infra && terraform fmt && terraform validate && terraform plan

# Seed the inbox once deployed (human runs the apply that creates the bucket first)
cd tooling && uv sync && uv run python src/seed_messages.py --bucket <name> --count 12
```

## Working style for this repo

- When asked to "build Phase N", read that phase in `action-plan.md` first, then the
  relevant stub docstring or `.tf` skeleton comments, then implement.
- Prefer small, reviewable diffs per phase over one giant change.
- After writing Terraform, run `validate` and report the result. Don't apply.
