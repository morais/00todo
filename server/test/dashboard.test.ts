import { afterEach, describe, expect, it, vi } from "vitest";
import { base64url, sha256Hex } from "../src/auth";
import { resetAppleKeysForTest } from "../src/apple";
import {
  dashboard, dashboardAppleLogin, dashboardLogin, dashboardLogout,
  dashboardAppleCallback, dashboardReviewLogin, isDashboardAppleState,
} from "../src/dashboard";
import type { Env } from "../src/api";

const origin = "https://api.00todo.com";
const reviewerCode = "tt_review_" + "A".repeat(43);
const reviewTenant = "11111111-1111-4111-8111-111111111111";
const otherTenant = "22222222-2222-4222-8222-222222222222";

async function environment() {
  const codeHash = await sha256Hex(reviewerCode);
  let revoked = false;
  const projects = [
    { id: "shopping", tenant_id: reviewTenant, name: "Weekend shopping", start_date: null, start_time: null,
      due_date: null, completed_at: null, sort_order: 0, created_at: "2026-01-01" },
    { id: "future", tenant_id: reviewTenant, name: "Future project", start_date: "2099-01-15", start_time: "09:00",
      due_date: "2099-01-20", completed_at: null, sort_order: 1, created_at: "2026-01-02" },
    { id: "done", tenant_id: reviewTenant, name: "Completed project", start_date: null, start_time: null,
      due_date: null, completed_at: "2026-01-01", sort_order: 2, created_at: "2026-01-03" },
    { id: "private", tenant_id: otherTenant, name: "Other tenant project", start_date: null, start_time: null,
      due_date: null, completed_at: null, sort_order: 0, created_at: "2026-01-01" },
  ];
  const tasks = [
    { id: "one", tenant_id: reviewTenant, title: "Review release notes", project_id: null,
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 0, created_at: "2026-01-01" },
    { id: "two", tenant_id: reviewTenant, title: "Buy oat milk", project_id: "shopping",
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 1, created_at: "2026-01-02" },
    { id: "three", tenant_id: reviewTenant, title: "Plan project launch", project_id: "future",
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 2, created_at: "2026-01-03" },
    { id: "four", tenant_id: reviewTenant, title: "Already completed", project_id: null,
      start_date: null, start_time: null, due_date: null, completed_at: "2026-01-01",
      sort_order: 3, created_at: "2026-01-04" },
    { id: "five", tenant_id: reviewTenant, title: "Hidden by completed project", project_id: "done",
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 4, created_at: "2026-01-05" },
    { id: "six", tenant_id: otherTenant, title: "Other tenant secret", project_id: "private",
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 0, created_at: "2026-01-01" },
    { id: "seven", tenant_id: reviewTenant, title: "<script>alert(1)</script>", project_id: null,
      start_date: null, start_time: null, due_date: null, completed_at: null,
      sort_order: 5, created_at: "2026-01-06" },
  ];
  const env = {
    PUBLIC_ORIGIN: origin, OAUTH_SIGNING_SECRET: "test-signing-secret-with-at-least-32-characters",
    APP_NAME: "00Todo", REVIEW_TENANT_IDS: reviewTenant,
    APPLE_WEB_CLIENT_ID: "com.example.todo.web", APPLE_WEB_REDIRECT_URI: `${origin}/auth/apple/callback`,
    APPLE_PRIVATE_KEY: "test-key-not-used-for-redirect", APPLE_TEAM_ID: "TESTTEAM", APPLE_KEY_ID: "TESTKEY",
    DEFAULT_TIME_ZONE: "Europe/Lisbon",
    DB: {
      prepare(sql: string) {
        return { bind(...args: unknown[]) {
          return {
            async first() {
              if (sql.includes("FROM review_credentials")) {
                return args[0] === codeHash && !revoked
                  ? { tenant_id: reviewTenant, expires_at: "2099-01-01", revoked_at: null } : null;
              }
              if (sql.includes("FROM tenants WHERE apple_subject")) {
                return { id: otherTenant, apple_subject: "apple-subject", email: null };
              }
              if (sql.includes("FROM tenants WHERE id")) {
                return args[0] === otherTenant && args[1] === "apple-subject" ? { id: otherTenant } : null;
              }
              return null;
            },
            async run() { return { meta: { changes: 1 } }; },
            async all() {
              if (sql.includes("FROM projects WHERE")) return { results: projects.filter((row) =>
                row.tenant_id === args[0] && row.completed_at === null) };
              if (sql.includes("FROM tasks t")) return { results: tasks.filter((row) =>
                row.tenant_id === args[0] && row.completed_at === null
                && (!row.project_id || projects.some((project) => project.id === row.project_id
                  && project.tenant_id === row.tenant_id && project.completed_at === null))) };
              return { results: [] };
            },
          };
        } };
      },
    } as unknown as D1Database,
  } as Env;
  return { env, revoke: () => { revoked = true; } };
}

afterEach(() => {
  vi.restoreAllMocks();
  resetAppleKeysForTest();
});

async function reviewerSession(env: Env): Promise<string> {
  const response = await dashboardReviewLogin(new Request(`${origin}/dashboard/login/review`, {
    method: "POST", headers: { origin, "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ accessCode: reviewerCode }),
  }), env);
  expect(response.status).toBe(303);
  expect(response.headers.get("location")).toBe(`${origin}/dashboard`);
  const cookie = response.headers.get("set-cookie")!;
  expect(cookie).toContain("HttpOnly; Secure; SameSite=Lax");
  expect(cookie).not.toContain(reviewerCode);
  return cookie.split(";")[0];
}

describe("read-only dashboard", () => {
  it("requires a browser session and offers Apple or reviewer sign-in", async () => {
    const { env } = await environment();
    const entry = await dashboard(new Request(`${origin}/dashboard`), env);
    expect(entry.status).toBe(303);
    expect(entry.headers.get("location")).toBe(`${origin}/dashboard/login`);
    const login = await dashboardLogin(new Request(`${origin}/dashboard/login`), env);
    expect(login.status).toBe(200);
    const html = await login.text();
    expect(html).toContain("Sign in with Apple");
    expect(html).toContain("Reviewer access");
    expect(login.headers.get("content-security-policy")).toContain("form-action 'self'");
  });

  it("binds Apple sign-in to a short-lived, secure browser flow cookie", async () => {
    const { env } = await environment();
    const response = await dashboardAppleLogin(env);
    expect(response.status).toBe(302);
    const url = new URL(response.headers.get("location")!);
    expect(url.origin).toBe("https://appleid.apple.com");
    expect(isDashboardAppleState(url.searchParams.get("state"))).toBe(true);
    expect(response.headers.get("set-cookie")).toContain("Path=/auth/apple/callback; Max-Age=600; HttpOnly; Secure; SameSite=None");
    const cookie = response.headers.get("set-cookie")!.split(";")[0];
    const callback = await dashboardAppleCallback(new Request(`${origin}/auth/apple/callback`, {
      method: "POST", headers: { cookie },
    }), env, new URLSearchParams({ state: "ttdash_" + "B".repeat(32) }));
    expect(callback.status).toBe(401);
    expect(callback.headers.get("set-cookie")).toContain("Max-Age=0");
  });

  it("verifies Apple sign-in and opens only the matching tenant", async () => {
    const { env } = await environment();
    const login = await dashboardAppleLogin(env);
    const authorizeURL = new URL(login.headers.get("location")!);
    const state = authorizeURL.searchParams.get("state")!;
    const nonce = authorizeURL.searchParams.get("nonce")!;
    const flowCookie = login.headers.get("set-cookie")!.split(";")[0];
    const rsa = await crypto.subtle.generateKey({ name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
    const ec = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true,
      ["sign", "verify"]) as CryptoKeyPair;
    const pem = new Uint8Array(await crypto.subtle.exportKey("pkcs8", ec.privateKey));
    env.APPLE_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----\n${btoa(String.fromCharCode(...pem))}\n-----END PRIVATE KEY-----`;
    const jwk = await crypto.subtle.exportKey("jwk", rsa.publicKey) as JsonWebKey;
    const encode = (value: unknown) => base64url(new TextEncoder().encode(JSON.stringify(value)));
    const now = Math.floor(Date.now() / 1000);
    const input = `${encode({ alg: "RS256", kid: "dashboard-test" })}.${encode({
      iss: "https://appleid.apple.com", aud: env.APPLE_WEB_CLIENT_ID, sub: "apple-subject",
      iat: now, exp: now + 600, nonce,
    })}`;
    const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", rsa.privateKey,
      new TextEncoder().encode(input)));
    const idToken = `${input}.${base64url(signature)}`;
    vi.spyOn(globalThis, "fetch").mockImplementation(async (url) => {
      if (String(url).endsWith("/auth/keys")) return Response.json({ keys: [{ kty: "RSA", kid: "dashboard-test", n: jwk.n, e: jwk.e }] });
      if (String(url).endsWith("/auth/token")) return Response.json({ id_token: idToken, access_token: "apple-test-token" });
      throw new Error(`Unexpected fetch ${url}`);
    });
    const callback = await dashboardAppleCallback(new Request(`${origin}/auth/apple/callback`, {
      method: "POST", headers: { cookie: flowCookie },
    }), env, new URLSearchParams({ state, id_token: idToken, code: "apple-test-code" }));
    expect(callback.status).toBe(303);
    expect(callback.headers.get("location")).toBe(`${origin}/dashboard`);
    const sessionCookie = callback.headers.get("set-cookie")!.match(/tt_dashboard_session=[^;]+/)?.[0];
    expect(sessionCookie).toBeTruthy();
    const view = await dashboard(new Request(`${origin}/dashboard`, { headers: { cookie: sessionCookie! } }), env);
    expect(view.status).toBe(200);
    const html = await view.text();
    expect(html).toContain("Other tenant secret");
    expect(html).not.toContain("Review release notes");
  });

  it("rejects cross-origin or invalid reviewer submissions", async () => {
    const { env } = await environment();
    const request = (code: string, requestOrigin: string) => new Request(`${origin}/dashboard/login/review`, {
      method: "POST", headers: { origin: requestOrigin, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ accessCode: code }),
    });
    expect((await dashboardReviewLogin(request(reviewerCode, "https://evil.example"), env)).status).toBe(403);
    expect((await dashboardReviewLogin(request("tt_review_" + "B".repeat(43), origin), env)).status).toBe(401);
  });

  it("shows only this tenant's unfinished available and scheduled work", async () => {
    const { env } = await environment();
    const cookie = await reviewerSession(env);
    const response = await dashboard(new Request(`${origin}/dashboard`, { headers: { cookie } }), env);
    expect(response.status).toBe(200);
    const html = await response.text();
    expect(html).toContain("Available now");
    expect(html).toContain("Scheduled");
    expect(html).toContain("Review release notes");
    expect(html).toContain("Buy oat milk");
    expect(html).toContain("In Weekend shopping");
    expect(html).toContain("Plan project launch");
    expect(html).toContain("Starts 15 Jan 2099 at 09:00");
    expect(html).not.toContain("Already completed");
    expect(html).not.toContain("Completed project");
    expect(html).not.toContain("Hidden by completed project");
    expect(html).not.toContain("Other tenant secret");
    expect(html).toContain("&lt;script&gt;alert(1)&lt;/script&gt;");
    expect(html).not.toContain("<script>alert(1)</script>");
  });

  it("invalidates reviewer sessions on revocation, tampering, or sign-out", async () => {
    const { env, revoke } = await environment();
    const cookie = await reviewerSession(env);
    const tampered = cookie.slice(0, -1) + (cookie.endsWith("A") ? "B" : "A");
    expect((await dashboard(new Request(`${origin}/dashboard`, { headers: { cookie: tampered } }), env)).status).toBe(303);
    const logout = dashboardLogout(new Request(`${origin}/dashboard/logout`, {
      method: "POST", headers: { origin, cookie },
    }), env);
    expect(logout.status).toBe(303);
    expect(logout.headers.get("set-cookie")).toContain("Max-Age=0");
    revoke();
    expect((await dashboard(new Request(`${origin}/dashboard`, { headers: { cookie } }), env)).status).toBe(303);
  });
});
