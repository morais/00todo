import { describe, expect, it } from "vitest";
import worker from "../src/index";
import { capacityProblem, tenantLimits } from "../src/rateLimit";
import type { Env } from "../src/api";

const refusing: RateLimit = { async limit() { return { success: false }; } };

describe("rate limits", () => {
  it("refuses a source over its budget before touching D1", async () => {
    const env = {
      PUBLIC_ORIGIN: "https://api.example.com",
      SOURCE_LIMITER: refusing,
      DB: { prepare() { throw new Error("D1 should not be reached"); } },
    } as unknown as Env;
    const response = await worker.fetch(new Request("https://api.example.com/v1/snapshot", {
      headers: { authorization: `Bearer tt_app_${"a".repeat(43)}`, "cf-connecting-ip": "203.0.113.9" },
    }), env);
    expect(response.status).toBe(429);
    expect(response.headers.get("Retry-After")).toBe("60");
  });

  it("refuses sign-in attempts over the sign-in budget", async () => {
    const env = { PUBLIC_ORIGIN: "https://api.example.com", SIGN_IN_LIMITER: refusing } as unknown as Env;
    const response = await worker.fetch(new Request("https://api.example.com/v1/auth/apple", { method: "POST", body: "{}" }), env);
    expect(response.status).toBe(429);
  });

  it("keeps health checks unlimited", async () => {
    const env = { PUBLIC_ORIGIN: "https://api.example.com", SOURCE_LIMITER: refusing } as unknown as Env;
    expect((await worker.fetch(new Request("https://api.example.com/health"), env)).status).toBe(200);
  });
});

describe("account capacity", () => {
  const db = (tasks: number, projects: number) => ({
    prepare() { return { bind() { return { async first() { return { tasks, projects }; } }; } }; },
  }) as unknown as D1Database;

  it("allows creates within the cap", async () => {
    expect(await capacityProblem(db(10, 2), "tenant", { tasks: 1 })).toBeNull();
  });

  it("refuses a batch that would pass the task cap", async () => {
    expect(await capacityProblem(db(tenantLimits.tasks - 2, 0), "tenant", { projects: 1, tasks: 3 })).toMatch(/limit/);
  });
});
