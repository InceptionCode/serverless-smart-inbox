import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

describe("isMockMode", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  it("returns true when NEXT_PUBLIC_API_URL is not set", async () => {
    delete process.env.NEXT_PUBLIC_API_URL;
    vi.resetModules();
    const { isMockMode } = await import("@/lib/api");
    expect(isMockMode()).toBe(true);
  });

  it("returns false when NEXT_PUBLIC_API_URL is set", async () => {
    process.env.NEXT_PUBLIC_API_URL = "https://api.example.com";
    vi.resetModules();
    const { isMockMode } = await import("@/lib/api");
    expect(isMockMode()).toBe(false);
  });
});

describe("fetchMessages", () => {
  let originalEnv: NodeJS.ProcessEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };
    vi.resetModules();
  });

  afterEach(() => {
    process.env = originalEnv;
    vi.restoreAllMocks();
  });

  it("returns mock data array in mock mode", async () => {
    delete process.env.NEXT_PUBLIC_API_URL;
    const { fetchMessages } = await import("@/lib/api");
    const result = await fetchMessages(60);
    expect(Array.isArray(result)).toBe(true);
    expect(result.length).toBeGreaterThan(0);
  });

  it("respects the limit parameter in mock mode", async () => {
    delete process.env.NEXT_PUBLIC_API_URL;
    const { fetchMessages } = await import("@/lib/api");
    const result = await fetchMessages(2);
    expect(result.length).toBeLessThanOrEqual(2);
  });

  it("each mock record has required fields", async () => {
    delete process.env.NEXT_PUBLIC_API_URL;
    const { fetchMessages } = await import("@/lib/api");
    const result = await fetchMessages(60);
    for (const item of result) {
      expect(item).toHaveProperty("id");
      expect(item).toHaveProperty("snippet");
      expect(item).toHaveProperty("sentiment");
      expect(item).toHaveProperty("confidence");
      expect(item).toHaveProperty("source");
      expect(item).toHaveProperty("receivedAt");
    }
  });

  it("calls the API URL with limit param in live mode", async () => {
    process.env.NEXT_PUBLIC_API_URL = "https://api.example.com";
    const mockFetch = vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response(JSON.stringify({ items: [] }), { status: 200 })
    );
    const { fetchMessages } = await import("@/lib/api");
    await fetchMessages(10);
    expect(mockFetch).toHaveBeenCalledWith(
      "https://api.example.com/messages?limit=10",
      expect.objectContaining({ cache: "no-store" })
    );
  });

  it("throws when the API returns a non-2xx response", async () => {
    process.env.NEXT_PUBLIC_API_URL = "https://api.example.com";
    vi.spyOn(globalThis, "fetch").mockResolvedValue(
      new Response("Not Found", { status: 404 })
    );
    const { fetchMessages } = await import("@/lib/api");
    await expect(fetchMessages(10)).rejects.toThrow("API error: 404");
  });

  it("throws when fetch itself rejects (network error)", async () => {
    process.env.NEXT_PUBLIC_API_URL = "https://api.example.com";
    vi.spyOn(globalThis, "fetch").mockRejectedValue(new Error("Failed to fetch"));
    const { fetchMessages } = await import("@/lib/api");
    await expect(fetchMessages(10)).rejects.toThrow("Failed to fetch");
  });
});
