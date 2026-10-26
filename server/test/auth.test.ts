import { afterEach, describe, expect, it, vi } from "vitest";
import { issueCredential } from "../src/auth";
import type { Env } from "../src/api";

afterEach(() => vi.useRealTimers());

describe("credential lifetimes", () => {
  it.each([
    ["mcp", 365],
    ["app", 90],
  ] as const)("issues %s credentials for %i days", async (kind, days) => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-23T12:34:56.789Z"));
    let inserted: unknown[] = [];
    const env = {
      PUBLIC_ORIGIN: "https://api.00todo.com",
      DB: {
        prepare: () => ({ bind: (...values: unknown[]) => ({
          run: async () => { inserted = values; return { meta: { changes: 1 } }; },
        }) }),
      } as unknown as D1Database,
    } as Env;

    const credential = await issueCredential(env, "tenant-id", kind, "Test connection");
    const expectedExpiry = new Date(Date.now() + days * 86400000).toISOString();
    expect(credential.expiresAt).toBe(expectedExpiry);
    expect(inserted[3]).toBe(kind);
    expect(inserted[8]).toBe(expectedExpiry);
  });
});
