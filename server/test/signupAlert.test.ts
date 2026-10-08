import { describe, expect, it, vi } from "vitest";
import { findOrCreateTenant } from "../src/auth";
import { sendNewTenantAlert } from "../src/signupAlert";
import type { Env } from "../src/api";

// `cloudflare:email` only resolves inside the Workers runtime. Standing in for
// it lets the hand-built message be read back.
vi.mock("cloudflare:email", () => ({
  EmailMessage: class {
    constructor(readonly from: string, readonly to: string, readonly raw: string) {}
  },
}));

function environment(existing: boolean, alerts = true) {
  const send = vi.fn(async (_message: { from: string; to: string; raw: string }) => {});
  let tenant: { id: string; apple_subject: string; email: string | null } | null =
    existing ? { id: "existing-tenant", apple_subject: "apple-sub", email: "old@example.com" } : null;
  const db = {
    prepare(sql: string) {
      return {
        bind(...values: unknown[]) {
          return {
            async run() {
              if (sql.includes("INSERT OR IGNORE INTO tenants")) {
                if (tenant) return { meta: { changes: 0 } };
                tenant = { id: values[0] as string, apple_subject: values[1] as string, email: values[2] as string | null };
                return { meta: { changes: 1 } };
              }
              return { meta: { changes: 1 } };
            },
            async first() { return tenant; },
          };
        },
      };
    },
  };
  const env = {
    DB: db, PUBLIC_ORIGIN: "https://api.00todo.com", APP_NAME: "00Todo",
    ...(alerts ? { SIGNUP_ALERTS: { send }, SIGNUP_ALERT_TO: "ops@example.com", SIGNUP_ALERT_FROM: "alerts@00todo.com" } : {}),
  } as unknown as Env;
  return { env, send };
}

describe("signup alert", () => {
  it("emails the operator when a sign-in creates a tenant, after the response", async () => {
    const { env, send } = environment(false);
    const waitUntil = vi.fn();
    const tenant = await findOrCreateTenant(env, "apple-sub", "new@example.com",
      { source: "mcp", ctx: { waitUntil } as unknown as ExecutionContext });
    expect(waitUntil).toHaveBeenCalledTimes(1);
    await waitUntil.mock.calls[0][0];
    expect(send).toHaveBeenCalledTimes(1);
    const message = send.mock.calls[0][0];
    expect(message.from).toBe("alerts@00todo.com");
    expect(message.to).toBe("ops@example.com");
    expect(message.raw).toContain("Subject: 00Todo: new tenant new@example.com\r\n");
    expect(message.raw).toContain("Signup surface: MCP client connection");
    expect(message.raw).toContain(`Tenant id:   ${tenant.id}`);
  });

  it("stays quiet when the tenant already exists", async () => {
    const { env, send } = environment(true);
    const waitUntil = vi.fn();
    const tenant = await findOrCreateTenant(env, "apple-sub", "old@example.com",
      { source: "app", ctx: { waitUntil } as unknown as ExecutionContext });
    expect(tenant.id).toBe("existing-tenant");
    expect(waitUntil).not.toHaveBeenCalled();
    expect(send).not.toHaveBeenCalled();
  });

  it("sends nothing unless both the binding and the recipient are configured", async () => {
    const { env } = environment(false, false);
    await expect(findOrCreateTenant(env, "apple-sub", null, { source: "dashboard" })).resolves.toBeTruthy();
  });

  it("names the surface when Apple shares no email, and strips header-breaking characters", async () => {
    const { env, send } = environment(false);
    await sendNewTenantAlert(env, { source: "dashboard", tenantId: "t-1", ownerEmail: null, createdAt: "2026-10-08T00:00:00.000Z" });
    expect(send.mock.calls[0][0].raw).toContain("Subject: 00Todo: new tenant via web dashboard\r\n");
    expect(send.mock.calls[0][0].raw).toContain("Owner email: (none)");

    await sendNewTenantAlert(env, {
      source: "app", tenantId: "t-2", ownerEmail: "a@example.com\r\nBcc: evil@example.com", createdAt: "2026-10-08T00:00:00.000Z",
    });
    expect(send.mock.calls[1][0].raw).toContain("Subject: 00Todo: new tenant a@example.comBcc: evil@example.com\r\n");
    const headers = send.mock.calls[1][0].raw.split("\r\n\r\n")[0];
    expect(headers).not.toContain("\r\nBcc:");
  });

  it("never fails the sign-in when sending fails", async () => {
    const { env, send } = environment(false);
    send.mockRejectedValueOnce(new Error("not verified"));
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    await expect(findOrCreateTenant(env, "apple-sub", "new@example.com", { source: "app" })).resolves.toBeTruthy();
    expect(warn).toHaveBeenCalledWith("signup alert email failed", expect.objectContaining({ error: "not verified" }));
    warn.mockRestore();
  });
});
