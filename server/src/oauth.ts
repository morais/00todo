import { appleEmail, exchangeAppleCode, verifyAppleIdToken } from "./apple";
import {
  audience, base64url, constantTimeEqual, decodeBase64url, findOrCreateTenant,
  issueCredential, publicOrigin, randomToken, sha256Base64url, sha256Hex,
  type Scope,
} from "./auth";
import { json, type Env } from "./api";

const scopes: Scope[] = ["todo:read", "todo:write"];
const flowLifetimeMs = 10 * 60000;
const codeLifetimeMs = 5 * 60000;

type Client = { name: string; redirects: string[]; issuedAt: number };
type Flow = {
  id_hash: string; client_id: string; client_name: string; redirect_uri: string;
  code_challenge: string; client_state: string | null; resource: string; scopes: string;
  apple_nonce: string; tenant_id: string | null; consent_hash: string | null;
  expires_at: string;
};
type Code = {
  code_hash: string; tenant_id: string; client_id: string; redirect_uri: string;
  code_challenge: string; resource: string; scopes: string; expires_at: string; redeemed_at: string | null;
};

function configured(env: Env): boolean {
  return Boolean(env.OAUTH_SIGNING_SECRET && env.OAUTH_SIGNING_SECRET.length >= 32
    && env.APPLE_WEB_CLIENT_ID && env.APPLE_WEB_REDIRECT_URI && env.APPLE_PRIVATE_KEY);
}

function metadata(value: unknown): Response {
  return Response.json(value, { headers: { "content-type": "application/json; charset=utf-8", "cache-control": "public, max-age=300" } });
}

export function protectedResourceMetadata(env: Env): Response {
  const origin = publicOrigin(env);
  return metadata({
    resource: audience(env, "mcp"), authorization_servers: [origin],
    scopes_supported: scopes, bearer_methods_supported: ["header"], resource_name: "00Todo",
  });
}

export function authorizationServerMetadata(env: Env): Response {
  const origin = publicOrigin(env);
  return metadata({
    issuer: origin,
    authorization_endpoint: `${origin}/oauth/authorize`,
    token_endpoint: `${origin}/oauth/token`,
    registration_endpoint: `${origin}/oauth/register`,
    response_types_supported: ["code"], grant_types_supported: ["authorization_code"],
    code_challenge_methods_supported: ["S256"], token_endpoint_auth_methods_supported: ["none"],
    scopes_supported: scopes, authorization_response_iss_parameter_supported: true,
  });
}

export function authChallenge(env: Env, status = 401, scope: Scope[] = scopes): Response {
  const origin = publicOrigin(env);
  const error = status === 403 ? ', error="insufficient_scope"' : '';
  return new Response(JSON.stringify({ error: status === 403 ? "insufficient_scope" : "Unauthorized" }), {
    status, headers: {
      "content-type": "application/json; charset=utf-8", "cache-control": "no-store",
      "WWW-Authenticate": `Bearer resource_metadata="${origin}/.well-known/oauth-protected-resource", scope="${scope.join(" ")}"${error}`,
    },
  });
}

function b64text(value: string): string {
  return new TextDecoder().decode(decodeBase64url(value));
}

async function clientSignature(env: Env, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.OAUTH_SIGNING_SECRET!),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64url(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`client:${body}`))));
}

function allowedRedirect(raw: string): boolean {
  if (raw.length > 512) return false;
  try {
    const url = new URL(raw);
    if (url.hash || url.username || url.password) return false;
    if (url.protocol === "https:") return true;
    return url.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
  } catch { return false; }
}

async function verifyClient(env: Env, id: string): Promise<Client | null> {
  if (!configured(env) || id.length > 4096 || !id.startsWith("ttc_")) return null;
  const [body, signature] = id.slice(4).split(".");
  if (!body || !signature || !constantTimeEqual(signature, await clientSignature(env, body))) return null;
  try {
    const client = JSON.parse(b64text(body)) as Client;
    if (!client || typeof client.name !== "string" || client.name.length > 120
      || !Array.isArray(client.redirects) || client.redirects.length < 1 || client.redirects.length > 5
      || !client.redirects.every((uri) => typeof uri === "string" && allowedRedirect(uri))) return null;
    return client;
  } catch { return null; }
}

async function textBody(req: Request, limit = 8192): Promise<string> {
  if (Number(req.headers.get("content-length") ?? 0) > limit) throw new Error("Request too large");
  const text = await req.text();
  if (text.length > limit) throw new Error("Request too large");
  return text;
}

export async function registerClient(req: Request, env: Env): Promise<Response> {
  if (!configured(env)) return json({ error: "MCP sign-in is not configured" }, 503);
  let body: Record<string, unknown>;
  try { body = JSON.parse(await textBody(req)) as Record<string, unknown>; }
  catch { return json({ error: "invalid_client_metadata" }, 400); }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return json({ error: "invalid_client_metadata" }, 400);
  }
  const redirectUris = body.redirect_uris;
  if (!Array.isArray(redirectUris) || redirectUris.length < 1 || redirectUris.length > 5
    || !redirectUris.every((uri) => typeof uri === "string" && allowedRedirect(uri))) {
    return json({ error: "invalid_redirect_uri", error_description: "Register 1–5 HTTPS or loopback redirect URIs" }, 400);
  }
  // RFC 7591 makes client_name optional and permits an authorization server to
  // replace requested metadata with values it supports. MCP clients commonly
  // request refresh_token even though this server only issues access tokens.
  const suppliedName = typeof body.client_name === "string" ? body.client_name.trim() : "";
  const name = suppliedName ? suppliedName.slice(0, 120) : "MCP client";
  const client: Client = { name: name.trim(), redirects: redirectUris, issuedAt: Math.floor(Date.now() / 1000) };
  const encoded = base64url(new TextEncoder().encode(JSON.stringify(client)));
  const clientId = `ttc_${encoded}.${await clientSignature(env, encoded)}`;
  return json({
    client_id: clientId, client_id_issued_at: client.issuedAt, client_name: client.name,
    redirect_uris: client.redirects, grant_types: ["authorization_code"], response_types: ["code"],
    token_endpoint_auth_method: "none", scope: scopes.join(" "),
  }, 201);
}

function requestedScopes(raw: string | null): Scope[] | null {
  if (!raw) return [...scopes];
  const values = [...new Set(raw.split(/\s+/).filter(Boolean))];
  return values.length && values.every((value) => scopes.includes(value as Scope)) ? values as Scope[] : null;
}

function htmlEscape(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]!);
}

function html(body: string, status = 200): Response {
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>00Todo · Connect</title><style>body{font:16px system-ui;max-width:620px;margin:8vh auto;padding:0 24px;line-height:1.5}button{font:inherit;padding:12px 20px;margin:8px 8px 0 0;border-radius:12px}code{overflow-wrap:anywhere}main{border:1px solid #ddd;border-radius:18px;padding:28px}</style><main>${body}</main></html>`, {
    status, headers: {
      "content-type": "text/html; charset=utf-8", "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self' https: http://localhost:* http://127.0.0.1:*; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "same-origin", "x-content-type-options": "nosniff",
    },
  });
}

function redirect(uri: string, params: Record<string, string | null>): Response {
  const url = new URL(uri);
  for (const [key, value] of Object.entries(params)) if (value !== null) url.searchParams.set(key, value);
  return new Response(null, { status: 303, headers: { Location: url.toString(), "cache-control": "no-store" } });
}

async function loadFlow(env: Env, flowId: string): Promise<Flow | null> {
  if (!/^[A-Za-z0-9_-]{32,64}$/.test(flowId)) return null;
  const flow = await env.DB.prepare("SELECT * FROM oauth_flows WHERE id_hash = ?")
    .bind(await sha256Hex(flowId)).first<Flow>();
  return flow && flow.expires_at > new Date().toISOString() ? flow : null;
}

export async function beginAuthorization(req: Request, env: Env): Promise<Response> {
  if (!configured(env)) return html("<h1>Apple sign-in is not configured</h1>", 503);
  const url = new URL(req.url);
  const q = url.searchParams;
  const clientId = q.get("client_id") ?? "";
  const client = await verifyClient(env, clientId);
  const redirectUri = q.get("redirect_uri") ?? "";
  const challenge = q.get("code_challenge") ?? "";
  const requested = requestedScopes(q.get("scope"));
  if (!client || q.get("response_type") !== "code" || !client.redirects.includes(redirectUri)
    || q.get("code_challenge_method") !== "S256" || !/^[A-Za-z0-9_-]{43}$/.test(challenge)
    || !requested || q.get("resource") !== audience(env, "mcp")) {
    return html("<h1>Invalid authorization request</h1><p>Check client registration, PKCE, scopes, and resource.</p>", 400);
  }
  const flowId = randomToken(24);
  const nonce = randomToken(24);
  const now = new Date();
  await env.DB.prepare(`INSERT INTO oauth_flows
    (id_hash, client_id, client_name, redirect_uri, code_challenge, client_state,
     resource, scopes, apple_nonce, created_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`).bind(
    await sha256Hex(flowId), clientId, client.name, redirectUri, challenge,
    q.get("state")?.slice(0, 512) ?? null, audience(env, "mcp"), requested.join(" "),
    nonce, now.toISOString(), new Date(now.getTime() + flowLifetimeMs).toISOString(),
  ).run();
  const apple = new URL("https://appleid.apple.com/auth/authorize");
  apple.search = new URLSearchParams({
    client_id: env.APPLE_WEB_CLIENT_ID!, redirect_uri: env.APPLE_WEB_REDIRECT_URI!,
    response_type: "code id_token", response_mode: "form_post", scope: "name email",
    state: flowId, nonce,
  }).toString();
  return new Response(null, { status: 302, headers: { Location: apple.toString(), "cache-control": "no-store" } });
}

export async function appleCallback(req: Request, env: Env): Promise<Response> {
  if (!configured(env)) return html("<h1>Apple sign-in is not configured</h1>", 503);
  let form: URLSearchParams;
  try { form = new URLSearchParams(await textBody(req, 16000)); }
  catch { return html("<h1>Invalid Apple response</h1>", 400); }
  const flowId = form.get("state") ?? "";
  const flow = await loadFlow(env, flowId);
  if (!flow || flow.tenant_id) return html("<h1>Sign-in session expired</h1><p>Start the connection again.</p>", 400);
  if (form.get("error")) return redirect(flow.redirect_uri, {
    error: "access_denied", state: flow.client_state, iss: publicOrigin(env),
  });
  const identityToken = form.get("id_token") ?? "";
  const code = form.get("code") ?? "";
  if (!identityToken || !code) return html("<h1>Apple response was incomplete</h1>", 400);
  try {
    const claims = await verifyAppleIdToken(identityToken, env.APPLE_WEB_CLIENT_ID!, flow.apple_nonce);
    const exchanged = await exchangeAppleCode(env, code, env.APPLE_WEB_CLIENT_ID!, env.APPLE_WEB_REDIRECT_URI!);
    const exchangedClaims = await verifyAppleIdToken(exchanged.idToken, env.APPLE_WEB_CLIENT_ID!, flow.apple_nonce);
    if (!constantTimeEqual(claims.sub, exchangedClaims.sub)) throw new Error("Apple account changed");
    const tenant = await findOrCreateTenant(env, claims.sub, appleEmail(exchangedClaims));
    const consentSecret = randomToken(24);
    const result = await env.DB.prepare(`UPDATE oauth_flows SET tenant_id = ?, consent_hash = ?
      WHERE id_hash = ? AND tenant_id IS NULL`).bind(tenant.id, await sha256Hex(consentSecret), flow.id_hash).run();
    if (result.meta.changes !== 1) return html("<h1>Sign-in was already used</h1>", 400);
    const target = `${publicOrigin(env)}/oauth/consent?flow=${encodeURIComponent(flowId)}`;
    return new Response(null, { status: 303, headers: {
      Location: target, "set-cookie": `tt_consent=${flowId}.${consentSecret}; Path=/oauth; Max-Age=600; HttpOnly; Secure; SameSite=Lax`,
      "cache-control": "no-store",
    } });
  } catch (cause) {
    console.warn("Apple web sign-in failed", cause instanceof Error ? cause.message : "unknown error");
    return html("<h1>Could not verify Apple sign-in</h1><p>Start the connection again.</p>", 401);
  }
}

function consentCookie(req: Request, flowId: string): string | null {
  const value = req.headers.get("cookie")?.split(";").map((part) => part.trim())
    .find((part) => part.startsWith("tt_consent="))?.slice("tt_consent=".length);
  if (!value || !value.startsWith(`${flowId}.`)) return null;
  return value.slice(flowId.length + 1);
}

async function authorizedConsent(req: Request, env: Env, flowId: string): Promise<{ flow: Flow; secret: string } | null> {
  const flow = await loadFlow(env, flowId);
  const secret = consentCookie(req, flowId);
  if (!flow || !flow.tenant_id || !flow.consent_hash || !secret ||
    !constantTimeEqual(await sha256Hex(secret), flow.consent_hash)) return null;
  return { flow, secret };
}

export async function showConsent(req: Request, env: Env): Promise<Response> {
  const flowId = new URL(req.url).searchParams.get("flow") ?? "";
  const authorized = await authorizedConsent(req, env, flowId);
  if (!authorized) return html("<h1>Connection expired</h1><p>Start again in your MCP client.</p>", 401);
  const { flow, secret } = authorized;
  return html(`<h1>Connect ${htmlEscape(flow.client_name)} to 00Todo?</h1>
    <p>This client can ${flow.scopes.includes("todo:write") ? "read and change" : "read"} your tasks and projects.</p>
    <p>After approval, you'll return to <code>${htmlEscape(flow.redirect_uri)}</code>.</p>
    <form method="post" action="/oauth/consent">
      <input type="hidden" name="flow" value="${htmlEscape(flowId)}">
      <input type="hidden" name="csrf" value="${htmlEscape(secret)}">
      <button name="decision" value="deny">Deny</button>
      <button name="decision" value="approve">Approve</button>
    </form>`);
}

export async function decideConsent(req: Request, env: Env): Promise<Response> {
  let form: URLSearchParams;
  try { form = new URLSearchParams(await textBody(req)); }
  catch { return html("<h1>Invalid consent response</h1>", 400); }
  const flowId = form.get("flow") ?? "";
  const authorized = await authorizedConsent(req, env, flowId);
  if (!authorized || !constantTimeEqual(form.get("csrf") ?? "", authorized.secret)) {
    return html("<h1>Connection expired</h1><p>Start again in your MCP client.</p>", 401);
  }
  const { flow } = authorized;
  const removed = await env.DB.prepare("DELETE FROM oauth_flows WHERE id_hash = ? AND consent_hash = ?")
    .bind(flow.id_hash, flow.consent_hash).run();
  if (removed.meta.changes !== 1) return html("<h1>Connection was already decided</h1>", 400);
  if (form.get("decision") !== "approve") return redirect(flow.redirect_uri, {
    error: "access_denied", state: flow.client_state, iss: publicOrigin(env),
  });
  const code = randomToken(32);
  await env.DB.prepare(`INSERT INTO oauth_codes
    (code_hash, tenant_id, client_id, redirect_uri, code_challenge, resource, scopes, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`).bind(
    await sha256Hex(code), flow.tenant_id, flow.client_id, flow.redirect_uri,
    flow.code_challenge, flow.resource, flow.scopes,
    new Date(Date.now() + codeLifetimeMs).toISOString(),
  ).run();
  return redirect(flow.redirect_uri, { code, state: flow.client_state, iss: publicOrigin(env) });
}

function oauthError(error: string, description: string): Response {
  return Response.json({ error, error_description: description }, {
    status: error === "invalid_client" ? 401 : 400,
    headers: { "cache-control": "no-store", pragma: "no-cache" },
  });
}

export async function exchangeCode(req: Request, env: Env): Promise<Response> {
  if (!configured(env)) return oauthError("server_error", "MCP sign-in is not configured");
  let form: URLSearchParams;
  try { form = new URLSearchParams(await textBody(req)); }
  catch { return oauthError("invalid_request", "Malformed form body"); }
  if (form.get("grant_type") !== "authorization_code") return oauthError("unsupported_grant_type", "Use authorization_code");
  const clientId = form.get("client_id") ?? "";
  const client = await verifyClient(env, clientId);
  if (!client) return oauthError("invalid_client", "Unknown client");
  const rawCode = form.get("code") ?? "";
  const verifier = form.get("code_verifier") ?? "";
  const redirectUri = form.get("redirect_uri") ?? "";
  const resource = form.get("resource") ?? "";
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(verifier) || !/^[A-Za-z0-9_-]{43}$/.test(rawCode)
    || resource !== audience(env, "mcp")) return oauthError("invalid_request", "Invalid code, verifier, or resource");
  const hash = await sha256Hex(rawCode);
  const code = await env.DB.prepare("SELECT * FROM oauth_codes WHERE code_hash = ?").bind(hash).first<Code>();
  if (!code || code.redeemed_at || code.expires_at <= new Date().toISOString()
    || !constantTimeEqual(code.client_id, clientId) || code.redirect_uri !== redirectUri
    || code.resource !== resource || !constantTimeEqual(code.code_challenge, await sha256Base64url(verifier))) {
    return oauthError("invalid_grant", "Authorization code is invalid or expired");
  }
  const claimed = await env.DB.prepare(`UPDATE oauth_codes SET redeemed_at = ?
    WHERE code_hash = ? AND redeemed_at IS NULL AND expires_at > ?`).bind(
    new Date().toISOString(), hash, new Date().toISOString(),
  ).run();
  if (claimed.meta.changes !== 1) return oauthError("invalid_grant", "Authorization code already used");
  const granted = code.scopes.split(" ").filter((scope): scope is Scope => scopes.includes(scope as Scope));
  const credential = await issueCredential(env, code.tenant_id, "mcp", `MCP · ${client.name}`, granted);
  return Response.json({
    access_token: credential.token, token_type: "Bearer",
    expires_in: Math.max(1, Math.floor((Date.parse(credential.expiresAt) - Date.now()) / 1000)),
    scope: granted.join(" "),
  }, { headers: { "cache-control": "no-store", pragma: "no-cache" } });
}
