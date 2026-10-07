#!/usr/bin/env node
// CLI-only end-to-end check of the dedicated review-code OAuth flow.
import { createHash, randomBytes } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const server = dirname(dirname(fileURLToPath(import.meta.url)));
const { accessCode } = JSON.parse(readFileSync(join(server, ".review-access.json"), "utf8"));
const origin = process.env.PUBLIC_ORIGIN ?? "https://api.00todo.com";
const callback = "https://review.example/callback";
const verifier = randomBytes(32).toString("base64url");
const challenge = createHash("sha256").update(verifier).digest("base64url");
const post = (url, body, extra = {}) => fetch(url, {
  method: "POST", redirect: "manual", headers: { "content-type": "application/x-www-form-urlencoded", ...extra },
  body: new URLSearchParams(body),
});
const requireStatus = (response, status, step) => {
  if (response.status !== status) throw new Error(`${step}: expected ${status}, got ${response.status}`);
};
const hidden = (page, name) => {
  const value = page.match(new RegExp(`name="${name}" value="([^"]+)"`))?.[1];
  if (!value) throw new Error(`Missing ${name} in consent form`);
  return value;
};

let tokenHash;
try {
  const registration = await fetch(`${origin}/oauth/register`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ client_name: "00Todo review smoke test", redirect_uris: [callback] }),
  });
  requireStatus(registration, 201, "client registration");
  const { client_id: clientId } = await registration.json();
  const authorize = new URL(`${origin}/oauth/authorize`);
  authorize.search = new URLSearchParams({ client_id: clientId, redirect_uri: callback,
    response_type: "code", code_challenge_method: "S256", code_challenge: challenge,
    resource: `${origin}/mcp`, scope: "todo:read" }).toString();
  const login = await fetch(authorize);
  requireStatus(login, 200, "review login page");
  const page = await login.text();
  if (!page.includes("Reviewer access")) throw new Error("Reviewer access option missing");
  const flowId = hidden(page, "flow");
  const signedIn = await post(`${origin}/auth/review/callback`, { flow: flowId, accessCode }, { origin });
  requireStatus(signedIn, 303, "review code exchange");
  const cookie = signedIn.headers.get("set-cookie")?.split(";", 1)[0];
  if (!cookie) throw new Error("Missing consent cookie");
  const consent = await fetch(signedIn.headers.get("location"), { headers: { cookie } });
  requireStatus(consent, 200, "consent page");
  const csrf = hidden(await consent.text(), "csrf");
  const decision = await post(`${origin}/oauth/consent`, { flow: flowId, csrf, decision: "approve" }, { cookie, origin });
  requireStatus(decision, 303, "consent approval");
  const code = new URL(decision.headers.get("location")).searchParams.get("code");
  if (!code) throw new Error("Missing authorization code");
  const exchanged = await post(`${origin}/oauth/token`, { grant_type: "authorization_code", client_id: clientId,
    redirect_uri: callback, code, code_verifier: verifier, resource: `${origin}/mcp` });
  requireStatus(exchanged, 200, "token exchange");
  const { access_token: token } = await exchanged.json();
  tokenHash = createHash("sha256").update(token).digest("hex");
  const rpc = async (method, params, id) => {
    const response = await fetch(`${origin}/mcp`, { method: "POST", headers: {
      authorization: `Bearer ${token}`, "content-type": "application/json",
    }, body: JSON.stringify({ jsonrpc: "2.0", id, method, params }) });
    requireStatus(response, 200, method);
    return response.json();
  };
  const catalog = await rpc("tools/list", {}, 1);
  if (!catalog.result.tools.some((tool) => tool.name === "list_tasks")) throw new Error("Missing task tools");
  const tasks = await rpc("tools/call", { name: "list_tasks", arguments: { view: "all" } }, 2);
  const payload = JSON.stringify(tasks.result?.structuredContent ?? {});
  if (!payload.includes("Review release notes") || !payload.includes("Plan project launch")) {
    throw new Error("Dedicated reviewer demo tasks not returned");
  }
  console.log("Review OAuth, consent, MCP tools, and dedicated demo tasks: passed.");
} finally {
  if (tokenHash) {
    execFileSync("npx", ["wrangler", "d1", "execute", "00todo", "--remote", "--command",
      `UPDATE credentials SET revoked_at = CURRENT_TIMESTAMP WHERE token_hash = '${tokenHash}' AND kind = 'mcp'`], {
      cwd: server, stdio: "ignore",
    });
  }
}
