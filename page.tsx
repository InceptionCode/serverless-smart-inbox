"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { fetchMessages, isMockMode } from "@/lib/api";
import {
  MessageRecord,
  Sentiment,
  SENTIMENTS,
  SENTIMENT_META,
} from "@/lib/types";

const POLL_MS = 4000;

type Filter = "ALL" | Sentiment;

export default function Dashboard() {
  const [messages, setMessages] = useState<MessageRecord[]>([]);
  const [filter, setFilter] = useState<Filter>("ALL");
  const [status, setStatus] = useState<"loading" | "live" | "error">("loading");
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null);
  const [secsAgo, setSecsAgo] = useState(0);
  const mock = useRef(isMockMode());

  const load = useCallback(async () => {
    try {
      const items = await fetchMessages(60);
      items.sort((a, b) => b.receivedAt.localeCompare(a.receivedAt));
      setMessages(items);
      setStatus("live");
      setLastUpdated(new Date());
    } catch {
      setStatus("error");
    }
  }, []);

  useEffect(() => {
    load();
    const id = setInterval(load, POLL_MS);
    return () => clearInterval(id);
  }, [load]);

  // "updated Ns ago" ticker
  useEffect(() => {
    const id = setInterval(() => {
      if (lastUpdated) {
        setSecsAgo(Math.round((Date.now() - lastUpdated.getTime()) / 1000));
      }
    }, 1000);
    return () => clearInterval(id);
  }, [lastUpdated]);

  const counts = useMemo(() => {
    const c: Record<Sentiment, number> = {
      POSITIVE: 0,
      NEUTRAL: 0,
      NEGATIVE: 0,
      MIXED: 0,
    };
    for (const m of messages) c[m.sentiment] += 1;
    return c;
  }, [messages]);

  const total = messages.length;

  const visible = useMemo(
    () => (filter === "ALL" ? messages : messages.filter((m) => m.sentiment === filter)),
    [messages, filter]
  );

  return (
    <main className="mx-auto min-h-screen max-w-6xl px-5 py-6 sm:px-8">
      <TopBar status={status} secsAgo={secsAgo} mock={mock.current} />

      <SignalMeter counts={counts} total={total} />

      <div className="mt-6 grid grid-cols-1 gap-5 lg:grid-cols-[200px_1fr]">
        <FilterRail
          filter={filter}
          setFilter={setFilter}
          counts={counts}
          total={total}
        />
        <MessageStream messages={visible} status={status} />
      </div>

      <footer className="mt-8 border-t border-line pt-4 font-mono text-xs text-muted">
        S3 inbox → SQS → Lambda + Comprehend → DynamoDB · serverless smart inbox
      </footer>
    </main>
  );
}

/* ------------------------------------------------------------------ TopBar */

function TopBar({
  status,
  secsAgo,
  mock,
}: {
  status: "loading" | "live" | "error";
  secsAgo: number;
  mock: boolean;
}) {
  return (
    <header className="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 className="font-display text-2xl font-bold tracking-tight text-text">
          Smart Inbox
        </h1>
        <p className="font-mono text-xs uppercase tracking-[0.2em] text-muted">
          sentiment console
        </p>
      </div>

      <div className="flex items-center gap-4 font-mono text-xs">
        {mock && (
          <span className="rounded border border-line px-2 py-1 text-muted">
            demo data — set NEXT_PUBLIC_API_URL for live
          </span>
        )}
        <span className="flex items-center gap-2">
          <span
            className={[
              "inline-block h-2.5 w-2.5 rounded-full",
              status === "live"
                ? "bg-live animate-livepulse"
                : status === "error"
                  ? "bg-neg"
                  : "bg-muted",
            ].join(" ")}
          />
          <span className="uppercase tracking-widest text-muted">
            {status === "live" ? "live" : status === "error" ? "offline" : "sync"}
          </span>
        </span>
        <span className="text-muted">
          {status === "live" ? `updated ${secsAgo}s ago` : "—"}
        </span>
      </div>
    </header>
  );
}

/* ------------------------------------------------------ SignalMeter (signature) */

function SignalMeter({
  counts,
  total,
}: {
  counts: Record<Sentiment, number>;
  total: number;
}) {
  const order: Sentiment[] = ["POSITIVE", "NEUTRAL", "NEGATIVE", "MIXED"];
  return (
    <section className="mt-6 rounded-lg border border-line bg-panel p-5">
      <div className="mb-3 flex items-center justify-between">
        <span className="font-mono text-xs uppercase tracking-[0.2em] text-muted">
          sentiment signal
        </span>
        <span className="font-mono text-xs text-muted">
          {total} message{total === 1 ? "" : "s"}
        </span>
      </div>

      {/* the live stacked meter */}
      <div className="relative h-7 w-full overflow-hidden rounded-md bg-panel2">
        {total === 0 ? (
          <div className="flex h-full items-center justify-center font-mono text-xs text-muted">
            awaiting signal…
          </div>
        ) : (
          <div className="flex h-full w-full">
            {order.map((s) => {
              const pct = total ? (counts[s] / total) * 100 : 0;
              if (pct === 0) return null;
              return (
                <div
                  key={s}
                  className="h-full transition-[width] duration-700 ease-out"
                  style={{
                    width: `${pct}%`,
                    backgroundColor: SENTIMENT_META[s].dot,
                  }}
                  title={`${SENTIMENT_META[s].label}: ${counts[s]}`}
                />
              );
            })}
          </div>
        )}
        {/* live sweep */}
        {total > 0 && (
          <div className="pointer-events-none absolute inset-0 overflow-hidden">
            <div className="meter-sweep absolute inset-y-0 w-1/3 animate-sweep" />
          </div>
        )}
      </div>

      {/* legend / counts */}
      <div className="mt-4 grid grid-cols-2 gap-3 sm:grid-cols-4">
        {order.map((s) => (
          <div key={s} className="flex items-center gap-2">
            <span
              className="inline-block h-2.5 w-2.5 rounded-full"
              style={{ backgroundColor: SENTIMENT_META[s].dot }}
            />
            <span className="font-mono text-sm text-text">{counts[s]}</span>
            <span className="font-mono text-xs uppercase tracking-wider text-muted">
              {SENTIMENT_META[s].label}
            </span>
          </div>
        ))}
      </div>
    </section>
  );
}

/* --------------------------------------------------------------- FilterRail */

function FilterRail({
  filter,
  setFilter,
  counts,
  total,
}: {
  filter: Filter;
  setFilter: (f: Filter) => void;
  counts: Record<Sentiment, number>;
  total: number;
}) {
  const rows: { key: Filter; label: string; count: number; dot?: string }[] = [
    { key: "ALL", label: "All", count: total },
    ...SENTIMENTS.map((s) => ({
      key: s,
      label: SENTIMENT_META[s].label,
      count: counts[s],
      dot: SENTIMENT_META[s].dot,
    })),
  ];

  return (
    <nav className="rounded-lg border border-line bg-panel p-2 lg:h-fit">
      <p className="px-2 py-2 font-mono text-xs uppercase tracking-[0.2em] text-muted">
        filter
      </p>
      <ul className="space-y-1">
        {rows.map((r) => {
          const active = filter === r.key;
          return (
            <li key={r.key}>
              <button
                onClick={() => setFilter(r.key)}
                className={[
                  "flex w-full items-center justify-between rounded-md px-3 py-2 text-left font-mono text-sm transition-colors",
                  active
                    ? "bg-panel2 text-text"
                    : "text-muted hover:bg-panel2 hover:text-text",
                ].join(" ")}
              >
                <span className="flex items-center gap-2">
                  {r.dot && (
                    <span
                      className="inline-block h-2 w-2 rounded-full"
                      style={{ backgroundColor: r.dot }}
                    />
                  )}
                  {r.label}
                </span>
                <span className="text-xs text-muted">{r.count}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

/* ------------------------------------------------------------- MessageStream */

function MessageStream({
  messages,
  status,
}: {
  messages: MessageRecord[];
  status: "loading" | "live" | "error";
}) {
  if (status === "error") {
    return (
      <Panel>
        <EmptyState
          title="Can't reach the read API"
          body="The dashboard couldn't load messages. Check that NEXT_PUBLIC_API_URL points at your deployed API Gateway endpoint and that the read_api Lambda is wired up."
        />
      </Panel>
    );
  }

  if (status === "loading") {
    return (
      <Panel>
        <EmptyState title="Connecting…" body="Pulling the latest signal." />
      </Panel>
    );
  }

  if (messages.length === 0) {
    return (
      <Panel>
        <EmptyState
          title="Inbox is quiet"
          body="Drop a message into the S3 inbox (or run the seeder) and it'll appear here within a few seconds."
        />
      </Panel>
    );
  }

  return (
    <Panel>
      <div className="stream-scroll max-h-[60vh] divide-y divide-line overflow-y-auto">
        {messages.map((m) => (
          <MessageRow key={m.id} m={m} />
        ))}
      </div>
    </Panel>
  );
}

function MessageRow({ m }: { m: MessageRecord }) {
  const meta = SENTIMENT_META[m.sentiment];
  const conf = Math.round(m.confidence * 100);
  return (
    <div className="flex items-start gap-4 px-4 py-3">
      <span
        className="mt-1 inline-flex shrink-0 items-center gap-1.5 rounded px-2 py-0.5 font-mono text-[11px] uppercase tracking-wider"
        style={{ color: meta.dot, backgroundColor: `${meta.dot}1a` }}
      >
        <span
          className="inline-block h-1.5 w-1.5 rounded-full"
          style={{ backgroundColor: meta.dot }}
        />
        {meta.label}
      </span>

      <div className="min-w-0 flex-1">
        <p className="truncate text-sm text-text">{m.snippet}</p>
        <p className="mt-1 font-mono text-[11px] text-muted">
          {m.source} · {timeAgo(m.receivedAt)}
        </p>
      </div>

      <div className="hidden w-28 shrink-0 sm:block">
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-panel2">
          <div
            className="h-full rounded-full"
            style={{ width: `${conf}%`, backgroundColor: meta.dot }}
          />
        </div>
        <p className="mt-1 text-right font-mono text-[11px] text-muted">
          {conf}%
        </p>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------- shared */

function Panel({ children }: { children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-line bg-panel">{children}</section>
  );
}

function EmptyState({ title, body }: { title: string; body: string }) {
  return (
    <div className="px-6 py-16 text-center">
      <p className="font-display text-lg text-text">{title}</p>
      <p className="mx-auto mt-2 max-w-md text-sm text-muted">{body}</p>
    </div>
  );
}

function timeAgo(iso: string): string {
  const s = Math.max(0, Math.round((Date.now() - new Date(iso).getTime()) / 1000));
  if (s < 60) return `${s}s ago`;
  const m = Math.round(s / 60);
  if (m < 60) return `${m}m ago`;
  const h = Math.round(m / 60);
  return `${h}h ago`;
}
