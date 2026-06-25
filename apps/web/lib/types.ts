export type Sentiment = "POSITIVE" | "NEUTRAL" | "NEGATIVE" | "MIXED";

export const SENTIMENTS: Sentiment[] = [
  "POSITIVE",
  "NEUTRAL",
  "NEGATIVE",
  "MIXED",
];

export const SENTIMENT_META: Record<Sentiment, { label: string; dot: string }> =
  {
    POSITIVE: { label: "Positive", dot: "#4ade80" },
    NEUTRAL: { label: "Neutral", dot: "#94a3b8" },
    NEGATIVE: { label: "Negative", dot: "#f87171" },
    MIXED: { label: "Mixed", dot: "#c084fc" },
  };

export interface MessageRecord {
  id: string;
  /** Truncated preview of the message body (≤ 280 chars). */
  snippet: string;
  sentiment: Sentiment;
  /** Comprehend confidence score — 0 to 1. */
  confidence: number;
  /** S3 object key that triggered this record. */
  source: string;
  /** ISO 8601 timestamp of when the object landed in S3. */
  receivedAt: string;
}

export interface MessagesResponse {
  items: MessageRecord[];
}
