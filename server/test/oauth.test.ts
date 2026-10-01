import { describe, expect, it } from "vitest";
import { beginAuthorization, registerClient, authorizationServerMetadata, protectedResourceMetadata, verifiedClientName, reviewCallback, showReviewLogin, decideConsent } from "../src/oauth";
import { sha256Hex } from "../src/auth";
import type { Env } from "../src/api";

const origin = "https://api.00todo.com";
const signing = "test-signing-secret-with-at-least-32-characters";

function environment(inserts: unknown[][] = []): Env {
  return {
    PUBLIC_ORIGIN: origin,
    APPLE_WEB_CLIENT_ID: "com.example.todo.web",
    APPLE_WEB_REDIRECT_URI: `${origin}/auth/apple/callback`,
    APPLE_PRIVATE_KEY: "test-key-not-used-for-redirect",
    OAUTH_SIGNING_SECRET: signing,
    DB: {
      prepare: () => ({ bind: (...args: unknown[]) => ({ run: async () => {
        inserts.push(args);
        return { meta: { changes: 1 } };
      } }) }),
    } as unknown as D1Database,
  };
}

describe("MCP OAuth discovery and registration", () => {
  it("advertises one resource and PKCE authorization", async () => {
    const env = environment();
    const resource = await protectedResourceMetadata(env).json() as Record<string, unknown>;
    const server = await authorizationServerMetadata(env).json() as Record<string, unknown>;
    expect(resource.resource).toBe(`${origin}/mcp`);
    expect(server.issuer).toBe(origin);
    expect(server.code_challenge_methods_supported).toEqual(["S256"]);
    expect(server.registration_endpoint).toBe(`${origin}/oauth/register`);
  });

  it("rejects insecure redirects and tampered client IDs", async () => {
    const env = environment();
    const bad = await registerClient(new Request(`${origin}/oauth/register`, {
      method: "POST", body: JSON.stringify({ client_name: "Bad", redirect_uris: ["http://evil.example/callback"] }),
    }), env);
    expect(bad.status).toBe(400);
    expect((await bad.json() as { error: string }).error).toBe("invalid_redirect_uri");

    const good = await registerClient(new Request(`${origin}/oauth/register`, {
      method: "POST", body: JSON.stringify({ client_name: "Test client", redirect_uris: ["https://client.example/callback"] }),
    }), env);
    expect(good.status).toBe(201);
    const client = await good.json() as { client_id: string };
    const url = new URL(`${origin}/oauth/authorize`);
    url.search = new URLSearchParams({
      client_id: client.client_id + "tampered", response_type: "code",
      redirect_uri: "https://client.example/callback", code_challenge_method: "S256",
      code_challenge: "A".repeat(43), resource: `${origin}/mcp`,
    }).toString();
    expect((await beginAuthorization(new Request(url), env)).status).toBe(400);
  });

  it("registers a public client when optional metadata is absent or asks for unsupported extras", async () => {
    const env = environment();
    const registered = await registerClient(new Request(`${origin}/oauth/register`, {
      method: "POST", body: JSON.stringify({
        redirect_uris: ["https://claude.ai/api/mcp/auth_callback"],
        grant_types: ["authorization_code", "refresh_token"],
        response_types: ["code"],
        token_endpoint_auth_method: "client_secret_basic",
      }),
    }), env);
    expect(registered.status).toBe(201);
    const client = await registered.json() as { client_id: string; client_name: string; grant_types: string[]; token_endpoint_auth_method: string };
    expect(client.client_name).toBe("MCP client");
    expect(client.grant_types).toEqual(["authorization_code"]);
    expect(client.token_endpoint_auth_method).toBe("none");
    const url = new URL(`${origin}/oauth/authorize`);
    url.search = new URLSearchParams({
      client_id: client.client_id, response_type: "code", redirect_uri: "https://claude.ai/api/mcp/auth_callback",
      code_challenge_method: "S256", code_challenge: "A".repeat(43), resource: `${origin}/mcp`,
    }).toString();
    expect((await beginAuthorization(new Request(url), env)).status).toBe(302);
  });

  it("starts a valid PKCE flow for the MCP resource only", async () => {
    const inserts: unknown[][] = [];
    const env = environment(inserts);
    const registered = await registerClient(new Request(`${origin}/oauth/register`, {
      method: "POST", body: JSON.stringify({ client_name: "Test client", redirect_uris: ["https://client.example/callback"] }),
    }), env);
    const { client_id } = await registered.json() as { client_id: string };
    const url = new URL(`${origin}/oauth/authorize`);
    url.search = new URLSearchParams({
      client_id, response_type: "code", redirect_uri: "https://client.example/callback",
      code_challenge_method: "S256", code_challenge: "A".repeat(43),
      resource: `${origin}/mcp`, scope: "todo:read", state: "client-state",
    }).toString();
    const response = await beginAuthorization(new Request(url), env);
    expect(response.status).toBe(302);
    expect(new URL(response.headers.get("location")!).hostname).toBe("appleid.apple.com");
    expect(inserts).toHaveLength(1);
    expect(inserts[0]).toContain(`${origin}/mcp`);
    expect(inserts[0]).toContain("todo:read");
    url.searchParams.set("resource", `${origin}/v1`);
    expect((await beginAuthorization(new Request(url), env)).status).toBe(400);
  });
});

describe("verified MCP clients", () => {
  const registry = JSON.stringify({ "https://claude.ai/api/mcp/auth_callback": "Claude" });
  const withRegistry = (value?: string) => ({ PUBLIC_ORIGIN: "https://api.example.com", MCP_VERIFIED_CLIENTS: value }) as unknown as Env;

  it("names only exact registered HTTPS callbacks", () => {
    const env = withRegistry(registry);
    expect(verifiedClientName(env, "https://claude.ai/api/mcp/auth_callback")).toBe("Claude");
    expect(verifiedClientName(env, "https://claude.ai/api/mcp/auth_callback/extra")).toBeUndefined();
    expect(verifiedClientName(env, "https://evil.example/claude")).toBeUndefined();
  });

  it("fails closed on missing or malformed configuration", () => {
    expect(verifiedClientName(withRegistry(), "https://claude.ai/api/mcp/auth_callback")).toBeUndefined();
    expect(verifiedClientName(withRegistry("{not json"), "https://claude.ai/api/mcp/auth_callback")).toBeUndefined();
    expect(verifiedClientName(withRegistry("[]"), "https://claude.ai/api/mcp/auth_callback")).toBeUndefined();
  });
});

describe("service name", () => {
  it("uses APP_NAME and falls back to a generic name", async () => {
    const named = await protectedResourceMetadata({ PUBLIC_ORIGIN: origin, APP_NAME: "00Todo" } as unknown as Env).json() as { resource_name: string };
    const generic = await protectedResourceMetadata({ PUBLIC_ORIGIN: origin } as unknown as Env).json() as { resource_name: string };
    expect(named.resource_name).toBe("00Todo");
    expect(generic.resource_name).toBe("Todo");
  });
});

describe("dedicated MCP reviewer sign-in", () => {
  async function reviewFlow(state?: string) {
    const tenantId = "dedicated-review-tenant";
    const code = "tt_review_" + "A".repeat(43);
    let flow: Record<string, unknown> | null = null;
    const env = {
      ...environment(), REVIEW_TENANT_IDS: tenantId,
      DB: {
        prepare(sql: string) {
          return { bind(...args: unknown[]) {
            return {
              async run() {
                if (sql.includes("INSERT INTO oauth_flows")) {
                  flow = { id_hash: args[0], client_id: args[1], client_name: args[2],
                    redirect_uri: args[3], code_challenge: args[4], client_state: args[5],
                    resource: args[6], scopes: args[7], apple_nonce: args[8],
                    tenant_id: null, consent_hash: null, expires_at: args[10] };
                }
                if (sql.includes("UPDATE oauth_flows") && flow && flow.tenant_id === null) {
                  flow.tenant_id = args[0]; flow.consent_hash = args[1];
                  return { meta: { changes: 1 } };
                }
                if (sql.includes("DELETE FROM oauth_flows") && flow && flow.id_hash === args[0]) {
                  flow = null;
                  return { meta: { changes: 1 } };
                }
                if (sql.includes("INSERT INTO oauth_codes")) return { meta: { changes: 1 } };
                return { meta: { changes: 0 } };
              },
              async first() {
                if (sql.includes("FROM oauth_flows")) return flow && flow.id_hash === args[0] ? flow : null;
                if (sql.includes("FROM review_credentials")) return args[0] === await sha256Hex(code)
                  ? { tenant_id: tenantId, expires_at: "2099-01-01T00:00:00.000Z", revoked_at: null } : null;
                return null;
              },
            };
          } };
        },
      } as unknown as D1Database,
    } as Env;
    const registered = await registerClient(new Request(`${origin}/oauth/register`, {
      method: "POST", body: JSON.stringify({ client_name: "ChatGPT", redirect_uris: ["https://chatgpt.com/callback"] }),
    }), env);
    const { client_id } = await registered.json() as { client_id: string };
    const url = new URL(`${origin}/oauth/authorize`);
    url.search = new URLSearchParams({ client_id, response_type: "code", redirect_uri: "https://chatgpt.com/callback",
      code_challenge_method: "S256", code_challenge: "A".repeat(43), resource: `${origin}/mcp`,
      ...(state === undefined ? {} : { state }) }).toString();
    const response = await beginAuthorization(new Request(url), env);
    const page = await response.text();
    const flowId = page.match(/name="flow" value="([^"]+)"/)?.[1];
    if (!flowId) throw new Error("Missing review flow");
    return { env, code, flowId, response, page };
  }

  it("shows reviewer access only when a tenant is allowlisted", async () => {
    const { env, flowId, response, page } = await reviewFlow();
    expect(response.status).toBe(200);
    expect(page).toContain("Reviewer access");
    expect(page).toContain('class="apple-button">Sign in with Apple</button>');
    const apple = await showReviewLogin(new Request(`${origin}/oauth/login?flow=${flowId}`), env);
    expect(apple.status).toBe(302);
    expect(new URL(apple.headers.get("location")!).hostname).toBe("appleid.apple.com");
  });

  it("rejects cross-origin and invalid codes, then allows the dedicated tenant", async () => {
    const { env, code, flowId } = await reviewFlow();
    const request = (accessCode: string, requestOrigin: string) => new Request(`${origin}/auth/review/callback`, {
      method: "POST", headers: { origin: requestOrigin, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ flow: flowId, accessCode }),
    });
    expect((await reviewCallback(request(code, "https://evil.example"), env)).status).toBe(403);
    expect((await reviewCallback(request("tt_review_" + "B".repeat(43), origin), env)).status).toBe(401);
    const accepted = await reviewCallback(request(code, origin), env);
    expect(accepted.status).toBe(303);
    expect(accepted.headers.get("location")).toContain(`/oauth/consent?flow=${flowId}`);
    expect(accepted.headers.get("set-cookie")).toContain("HttpOnly; Secure");
    expect((await reviewCallback(request(code, origin), env)).status).toBe(401);
  });

  it("returns a long opaque client state unchanged in the authorization callback", async () => {
    const state = "opaque-state:" + "x".repeat(1000) + "+/%=";
    const { env, code, flowId } = await reviewFlow(state);
    const accepted = await reviewCallback(new Request(`${origin}/auth/review/callback`, {
      method: "POST", headers: { origin, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ flow: flowId, accessCode: code }),
    }), env);
    expect(accepted.status).toBe(303);
    const cookie = accepted.headers.get("set-cookie")!.split(";")[0];
    const secret = cookie.split(".")[1];
    const callback = await decideConsent(new Request(`${origin}/oauth/consent`, {
      method: "POST", headers: { cookie, "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ flow: flowId, csrf: secret, decision: "approve" }),
    }), env);
    expect(callback.status).toBe(303);
    const callbackURL = new URL(callback.headers.get("location")!);
    expect(callbackURL.searchParams.get("state")).toBe(state);
    expect(callbackURL.searchParams.get("iss")).toBe(origin);
  });
});
