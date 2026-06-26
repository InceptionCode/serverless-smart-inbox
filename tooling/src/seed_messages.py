"""
Seed the Smart Inbox.

Uploads sample messages to the inbox S3 bucket. Each PutObject fires an
ObjectCreated event -> ingest SQS queue -> processor Lambda, so this is how you
drive an end-to-end test or a live demo.

Usage:
    uv run python src/seed_messages.py --bucket smart-inbox-incoming-xyz
    uv run python src/seed_messages.py --bucket <name> --count 20 --delay 1.5
    uv run python src/seed_messages.py --bucket <name> --from-samples   # use samples/*.txt

Needs AWS creds in your environment (same profile/region you deployed with) and
s3:PutObject on the bucket.
"""

from __future__ import annotations

import argparse
import datetime as dt
import pathlib
import random
import sys
import time
import uuid

try:
    import boto3
except ImportError:
    sys.exit("boto3 not installed. Run `uv sync` in the tooling/ dir first.")


# A spread of sentiments so the meter actually moves during a demo.
SAMPLE_MESSAGES: list[str] = [
    "These drum kits are unreal, my mixes finally hit different. Worth every penny.",
    "The download link is broken and nobody from support has replied in three days.",
    "Order #4471 has shipped. Tracking number is attached to this message.",
    "Love the sound bank overall but a couple of the 808 presets clip hard.",
    "Best sample pack I've bought this year. Instant inspiration, opened it and made a beat.",
    "I was charged twice for the same order and I want a refund right now.",
    "Invoice for the March licensing period is enclosed for your records.",
    "Great samples, but the folder naming is a mess and hard to browse.",
    "Your granular patches are exactly the vibe I was chasing. Incredible work.",
    "The site crashed at checkout and I lost my cart twice. Frustrating experience.",
    "Following up on my previous email about the missing license file.",
    "Honestly the most inspiring pack in my library right now, thank you.",
    "Audio previews don't match the actual files. Disappointed with the quality.",
    "Standard confirmation that your subscription renews on the 1st.",
    "Mixed feelings — the melodies slap but the drums feel a little thin.",
]


def make_body(text: str) -> str:
    return text


def upload(s3, bucket: str, text: str, prefix: str) -> str:
    key = f"{prefix}{dt.datetime.utcnow():%Y%m%d}/{uuid.uuid4().hex[:12]}.txt"
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=make_body(text).encode("utf-8"),
        ContentType="text/plain",
    )
    return key


def load_sample_files() -> list[str]:
    samples_dir = pathlib.Path(__file__).resolve().parent.parent / "samples"
    files = sorted(samples_dir.glob("*.txt"))
    return [f.read_text(encoding="utf-8").strip() for f in files if f.read_text().strip()]


def main() -> int:
    p = argparse.ArgumentParser(description="Seed the Smart Inbox S3 bucket.")
    p.add_argument("--bucket", required=True, help="Inbox bucket name.")
    p.add_argument("--count", type=int, default=10, help="How many messages to send.")
    p.add_argument("--delay", type=float, default=1.0, help="Seconds between uploads.")
    p.add_argument("--prefix", default="inbox/", help="Key prefix in the bucket.")
    p.add_argument("--region", default=None, help="Override AWS region.")
    p.add_argument(
        "--from-samples",
        action="store_true",
        help="Use the .txt files in tooling/samples/ instead of the built-in list.",
    )
    args = p.parse_args()

    pool = load_sample_files() if args.from_samples else SAMPLE_MESSAGES
    if not pool:
        return _fail("No sample messages found.")

    s3 = boto3.client("s3", region_name=args.region) if args.region else boto3.client("s3")

    print(f"Seeding {args.count} message(s) -> s3://{args.bucket}/{args.prefix}\n")
    for i in range(args.count):
        text = pool[i] if args.from_samples and i < len(pool) else random.choice(pool)
        try:
            key = upload(s3, args.bucket, text, args.prefix)
        except Exception as e:  # noqa: BLE001 — demo tool, surface the error plainly
            return _fail(f"Upload failed: {e}")
        print(f"  [{i + 1:>2}/{args.count}] {key}  «{text[:48]}…»")
        if i < args.count - 1:
            time.sleep(args.delay)

    print("\nDone. Watch CloudWatch logs or the dashboard — records should land in seconds.")
    return 0


def _fail(msg: str) -> int:
    print(f"ERROR: {msg}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
