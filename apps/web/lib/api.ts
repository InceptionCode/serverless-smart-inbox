import type { MessageRecord, MessagesResponse } from "./types";

const MOCK_MESSAGES: MessageRecord[] = [
  {
    id: "mock-001",
    snippet:
      "Really impressed with the onboarding experience. The team was responsive and the setup took under an hour.",
    sentiment: "POSITIVE",
    confidence: 0.97,
    source: "inbox/feedback-001.txt",
    receivedAt: new Date(Date.now() - 45_000).toISOString(),
  },
  {
    id: "mock-002",
    snippet:
      "The package arrived damaged and customer support has been impossible to reach for over a week.",
    sentiment: "NEGATIVE",
    confidence: 0.94,
    source: "inbox/feedback-002.txt",
    receivedAt: new Date(Date.now() - 120_000).toISOString(),
  },
  {
    id: "mock-003",
    snippet: "Order #4892 was delivered on Tuesday. Invoice attached.",
    sentiment: "NEUTRAL",
    confidence: 0.88,
    source: "inbox/feedback-003.txt",
    receivedAt: new Date(Date.now() - 210_000).toISOString(),
  },
  {
    id: "mock-004",
    snippet:
      "The new dashboard is beautiful but the export function keeps timing out on large datasets.",
    sentiment: "MIXED",
    confidence: 0.82,
    source: "inbox/feedback-004.txt",
    receivedAt: new Date(Date.now() - 350_000).toISOString(),
  },
  {
    id: "mock-005",
    snippet:
      "Five stars — fast shipping, perfect condition, exactly as described. Will order again.",
    sentiment: "POSITIVE",
    confidence: 0.99,
    source: "inbox/feedback-005.txt",
    receivedAt: new Date(Date.now() - 480_000).toISOString(),
  },
  {
    id: "mock-006",
    snippet:
      "Subscription cancelled. Been charged twice this month with no resolution after three support tickets.",
    sentiment: "NEGATIVE",
    confidence: 0.96,
    source: "inbox/feedback-006.txt",
    receivedAt: new Date(Date.now() - 600_000).toISOString(),
  },
  {
    id: "mock-007",
    snippet: "Please update my billing address to 123 Main St, Portland OR 97201.",
    sentiment: "NEUTRAL",
    confidence: 0.91,
    source: "inbox/feedback-007.txt",
    receivedAt: new Date(Date.now() - 740_000).toISOString(),
  },
  {
    id: "mock-008",
    snippet:
      "Love the product itself — the hardware is solid — but the companion app is frustratingly buggy.",
    sentiment: "MIXED",
    confidence: 0.79,
    source: "inbox/feedback-008.txt",
    receivedAt: new Date(Date.now() - 900_000).toISOString(),
  },
  {
    id: "mock-009",
    snippet:
      "Your support agent Sarah went above and beyond to resolve my issue. Truly outstanding service.",
    sentiment: "POSITIVE",
    confidence: 0.98,
    source: "inbox/feedback-009.txt",
    receivedAt: new Date(Date.now() - 1_100_000).toISOString(),
  },
  {
    id: "mock-010",
    snippet:
      "Refund request submitted on the 3rd. Transaction ID: TXN-88421. No confirmation received.",
    sentiment: "NEUTRAL",
    confidence: 0.85,
    source: "inbox/feedback-010.txt",
    receivedAt: new Date(Date.now() - 1_300_000).toISOString(),
  },
  {
    id: "mock-011",
    snippet:
      "Worst experience I have ever had with a SaaS product. Lost two days of work due to a data sync bug.",
    sentiment: "NEGATIVE",
    confidence: 0.97,
    source: "inbox/feedback-011.txt",
    receivedAt: new Date(Date.now() - 1_500_000).toISOString(),
  },
  {
    id: "mock-012",
    snippet:
      "The pricing is fair and most features work well, though the mobile app still lags behind the web version.",
    sentiment: "MIXED",
    confidence: 0.76,
    source: "inbox/feedback-012.txt",
    receivedAt: new Date(Date.now() - 1_800_000).toISOString(),
  },
];

export function isMockMode(): boolean {
  return !process.env.NEXT_PUBLIC_API_URL;
}

export async function fetchMessages(limit = 60): Promise<MessageRecord[]> {
  if (isMockMode()) {
    return Promise.resolve(MOCK_MESSAGES.slice(0, limit));
  }

  const base = process.env.NEXT_PUBLIC_API_URL!.replace(/\/$/, "");
  const res = await fetch(
    `${base}/messages?limit=${encodeURIComponent(String(limit))}`,
    { cache: "no-store" }
  );

  if (!res.ok) throw new Error(`API error: ${res.status}`);

  const data: MessagesResponse = await res.json();
  return data.items;
}
