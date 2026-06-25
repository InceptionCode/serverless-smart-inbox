import { render, screen, act, fireEvent } from "@testing-library/react";
import { vi, describe, it, expect, beforeEach, afterEach } from "vitest";
import Dashboard from "@/app/page";
import { fetchMessages, isMockMode } from "@/lib/api";
import type { MessageRecord } from "@/lib/types";

vi.mock("@/lib/api");

const RECORDS: MessageRecord[] = [
  {
    id: "1",
    snippet: "Really impressed with the onboarding experience.",
    sentiment: "POSITIVE",
    confidence: 0.97,
    source: "inbox/a.txt",
    receivedAt: new Date(Date.now() - 30_000).toISOString(),
  },
  {
    id: "2",
    snippet: "Terrible experience, never buying again.",
    sentiment: "NEGATIVE",
    confidence: 0.91,
    source: "inbox/b.txt",
    receivedAt: new Date(Date.now() - 60_000).toISOString(),
  },
  {
    id: "3",
    snippet: "Order #1234 was delivered on Tuesday.",
    sentiment: "NEUTRAL",
    confidence: 0.78,
    source: "inbox/c.txt",
    receivedAt: new Date(Date.now() - 90_000).toISOString(),
  },
];

// Advance fake time enough to flush resolved-promise microtasks (100ms is
// well under the shortest interval, 1000ms, so no ticker/poller callbacks fire).
async function flush() {
  await act(async () => {
    await vi.advanceTimersByTimeAsync(100);
  });
}

describe("Dashboard", () => {
  beforeEach(() => {
    vi.mocked(isMockMode).mockReturnValue(false);
    vi.mocked(fetchMessages).mockResolvedValue([]);
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  // ── loading / status ────────────────────────────────────────────────────────

  it("shows connecting state before first fetch resolves", async () => {
    vi.mocked(fetchMessages).mockReturnValue(new Promise(() => {})); // never resolves
    render(<Dashboard />);
    expect(screen.getByText(/connecting/i)).toBeInTheDocument();
    // no flush needed — no state updates fired yet
  });

  it("shows live status text after fetch resolves", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/^live$/i)).toBeInTheDocument();
  });

  it("shows offline status text when fetch throws", async () => {
    vi.mocked(fetchMessages).mockRejectedValue(new Error("network"));
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/offline/i)).toBeInTheDocument();
  });

  it("shows error empty state body when fetch throws", async () => {
    vi.mocked(fetchMessages).mockRejectedValue(new Error("network"));
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/can't reach/i)).toBeInTheDocument();
  });

  // ── mock mode banner ────────────────────────────────────────────────────────

  it("shows demo data banner when in mock mode", async () => {
    vi.mocked(isMockMode).mockReturnValue(true);
    vi.mocked(fetchMessages).mockResolvedValue([]);
    render(<Dashboard />);
    // Banner is driven by a ref set at render time — synchronously available
    expect(screen.getByText(/demo data/i)).toBeInTheDocument();
    await flush(); // drain pending effects to avoid act() warnings
  });

  it("hides demo data banner in live mode", async () => {
    vi.mocked(isMockMode).mockReturnValue(false);
    render(<Dashboard />);
    expect(screen.queryByText(/demo data/i)).not.toBeInTheDocument();
    await flush();
  });

  // ── message stream ──────────────────────────────────────────────────────────

  it("renders message snippets after loading", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/impressed with the onboarding/i)).toBeInTheDocument();
    expect(screen.getByText(/terrible experience/i)).toBeInTheDocument();
    expect(screen.getByText(/delivered on tuesday/i)).toBeInTheDocument();
  });

  it("shows inbox-quiet empty state when there are no messages at all", async () => {
    vi.mocked(fetchMessages).mockResolvedValue([]);
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/inbox is quiet/i)).toBeInTheDocument();
  });

  it("shows no-matches state when filter yields zero results (not inbox-quiet)", async () => {
    // RECORDS contains POSITIVE/NEGATIVE/NEUTRAL — no MIXED entries
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    act(() => { fireEvent.click(screen.getByRole("button", { name: /mixed/i })); });
    expect(screen.getByText(/no matches/i)).toBeInTheDocument();
    expect(screen.queryByText(/inbox is quiet/i)).not.toBeInTheDocument();
  });

  it("shows total count in stream footer", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    expect(screen.getByText(/showing 3 of 3/i)).toBeInTheDocument();
  });

  it("stream footer reflects filtered count vs total", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    act(() => { fireEvent.click(screen.getByRole("button", { name: /positive/i })); });
    expect(screen.getByText(/showing 1 of 3/i)).toBeInTheDocument();
  });

  // ── filter rail ─────────────────────────────────────────────────────────────

  it("renders all five filter options", async () => {
    render(<Dashboard />);
    await flush();
    for (const label of ["All", "Positive", "Negative", "Neutral", "Mixed"]) {
      expect(
        screen.getByRole("button", { name: new RegExp(label, "i") })
      ).toBeInTheDocument();
    }
  });

  it("ALL filter button has aria-pressed=true by default", async () => {
    render(<Dashboard />);
    await flush();
    expect(screen.getByRole("button", { name: /^all/i })).toHaveAttribute(
      "aria-pressed",
      "true"
    );
  });

  it("clicking NEGATIVE sets its aria-pressed to true", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    const negBtn = screen.getByRole("button", { name: /negative/i });
    act(() => { fireEvent.click(negBtn); });
    expect(negBtn).toHaveAttribute("aria-pressed", "true");
  });

  it("clicking NEGATIVE sets ALL aria-pressed to false", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    act(() => { fireEvent.click(screen.getByRole("button", { name: /negative/i })); });
    expect(screen.getByRole("button", { name: /^all/i })).toHaveAttribute(
      "aria-pressed",
      "false"
    );
  });

  it("filters message list to selected sentiment", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    act(() => { fireEvent.click(screen.getByRole("button", { name: /positive/i })); });
    expect(screen.getByText(/impressed with the onboarding/i)).toBeInTheDocument();
    expect(screen.queryByText(/terrible experience/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/delivered on tuesday/i)).not.toBeInTheDocument();
  });

  // ── accessibility ───────────────────────────────────────────────────────────

  it("filter nav has aria-label", async () => {
    render(<Dashboard />);
    expect(
      screen.getByRole("navigation", { name: /filter by sentiment/i })
    ).toBeInTheDocument();
    await flush();
  });

  it("status dot has sr-only companion text", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    expect(document.querySelector(".sr-only")).toBeInTheDocument();
  });

  // ── message row UX ──────────────────────────────────────────────────────────

  it("snippet paragraph has title attribute with full text", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    expect(
      screen.getByTitle("Really impressed with the onboarding experience.")
    ).toBeInTheDocument();
  });

  it("renders confidence percentage text", async () => {
    vi.mocked(fetchMessages).mockResolvedValue(RECORDS);
    render(<Dashboard />);
    await flush();
    // 97% confidence on the first record — at least one element shows it
    expect(screen.getAllByText(/97%/).length).toBeGreaterThan(0);
  });
});
