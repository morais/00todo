import { describe, expect, it } from "vitest";
import { beginAuthorization, registerClient, authorizationServerMetadata, protectedResourceMetadata, verifiedClientName } from "../src/oauth";
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
