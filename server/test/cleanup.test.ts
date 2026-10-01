import { describe, expect, it } from "vitest";
import { sweepExpiredAuthData } from "../src/cleanup";
import type { Env } from "../src/api";

describe("expired auth data sweep", () => {
  it("deletes only rows that can never be used again", async () => {
    const statements: Array<{ sql: string; args: unknown[] }> = [];
    const env = { DB: {
      prepare(sql: string) { return { bind(...args: unknown[]) { const statement = { sql, args }; statements.push(statement); return statement; } }; },
      async batch(batch: unknown[]) { expect(batch).toHaveLength(5); return []; },
    } } as unknown as Env;
    await sweepExpiredAuthData(env, new Date("2026-10-01T12:00:00.000Z"));
    expect(statements.map((item) => item.sql)).toEqual([
      "DELETE FROM oauth_flows WHERE expires_at <= ?",
      "DELETE FROM oauth_codes WHERE expires_at <= ?",
      "DELETE FROM credentials WHERE expires_at <= ?",
      "DELETE FROM credentials WHERE revoked_at IS NOT NULL",
      "DELETE FROM review_credentials WHERE expires_at <= ? OR revoked_at IS NOT NULL",
    ]);
    expect(statements[0].args).toEqual(["2026-10-01T12:00:00.000Z"]);
  });
});
