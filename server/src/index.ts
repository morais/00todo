import { routeApi, json, type Env } from "./api";
import { routeMcp } from "./mcp";
import { authenticate, publicOrigin } from "./auth";
import { deleteAccount, signInWithApple, signOut } from "./appAuth";
import {
  dashboard, dashboardAppleCallback, dashboardAppleLogin, dashboardLogin,
  dashboardLogout, dashboardReviewLogin, isDashboardAppleState,
} from "./dashboard";
import { disconnectMcpConnection, listMcpConnections } from "./mcpConnections";
import { maybeSweep, sweepExpiredAuthData } from "./cleanup";
import { openAIAppsChallenge } from "./openAIAppsChallenge";
import { signInAllowed, sourceAllowed, tenantAllowed, tooManyRequests } from "./rateLimit";
import {
  appleCallback, authChallenge, authorizationServerMetadata, beginAuthorization,
  decideConsent, exchangeCode, protectedResourceMetadata, registerClient, showConsent,
  showReviewLogin, reviewCallback,
} from "./oauth";

const signInRoutes = new Set([
  "/v1/auth/apple", "/v1/auth/delete-account", "/oauth/register", "/auth/apple/callback",
  "/oauth/consent", "/oauth/token",
  "/auth/review/callback",
  "/dashboard/login/review", "/dashboard/logout",
]);

export default {
  async fetch(req: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const path = new URL(req.url).pathname;
    const method = req.method;
    if (path === "/health" && method === "GET") return json({ ok: true });
    if (!(await sourceAllowed(env, req))) return tooManyRequests();
    if (path === "/.well-known/openai-apps-challenge" && (method === "GET" || method === "HEAD")) {
      return openAIAppsChallenge(req, env);
    }
    if ((signInRoutes.has(path) && method === "POST") || path === "/oauth/authorize"
      || path === "/dashboard/login/apple") {
      if (!(await signInAllowed(env, req))) return tooManyRequests();
      maybeSweep(env, ctx);
    }
    if (path === "/.well-known/oauth-protected-resource" && method === "GET") return protectedResourceMetadata(env);
    if (path === "/.well-known/oauth-protected-resource/mcp" && method === "GET") return protectedResourceMetadata(env);
    if (path === "/.well-known/oauth-authorization-server" && method === "GET") return authorizationServerMetadata(env);
    if (path === "/oauth/register" && method === "POST") return registerClient(req, env);
    if (path === "/oauth/authorize" && method === "GET") return beginAuthorization(req, env);
    if (path === "/oauth/login" && method === "GET") return showReviewLogin(req, env);
    if (path === "/auth/apple/callback" && method === "POST") {
      if (Number(req.headers.get("content-length") ?? 0) > 16000) return json({ error: "Request too large" }, 413);
      const raw = await req.clone().text();
      if (raw.length > 16000) return json({ error: "Request too large" }, 413);
      const form = new URLSearchParams(raw);
      return isDashboardAppleState(form.get("state"))
        ? dashboardAppleCallback(req, env, form, ctx) : appleCallback(req, env, ctx);
    }
    if (path === "/auth/review/callback" && method === "POST") return reviewCallback(req, env);
    if (path === "/oauth/consent" && method === "GET") return showConsent(req, env);
    if (path === "/oauth/consent" && method === "POST") return decideConsent(req, env);
    if (path === "/oauth/token" && method === "POST") return exchangeCode(req, env);
    if ((path === "/dashboard" || path === "/dashboard/") && method === "GET") return dashboard(req, env);
    if (path === "/dashboard/login" && method === "GET") return dashboardLogin(req, env);
    if (path === "/dashboard/login/apple" && method === "GET") return dashboardAppleLogin(env);
    if (path === "/dashboard/login/review" && method === "POST") return dashboardReviewLogin(req, env);
    if (path === "/dashboard/logout" && method === "POST") return dashboardLogout(req, env);
    if (path === "/v1/auth/apple" && method === "POST") return signInWithApple(req, env, ctx);
    if (path === "/mcp") {
      const principal = await authenticate(req, env, "mcp");
      if (!principal) return authChallenge(env);
      if (!(await tenantAllowed(env, principal.tenantId))) return tooManyRequests();
      return routeMcp(req, env, principal);
    }
    if (path.startsWith("/v1/")) {
      const principal = await authenticate(req, env, "app");
      if (!principal) return json({ error: "Unauthorized" }, 401);
      if (!(await tenantAllowed(env, principal.tenantId))) return tooManyRequests();
      if (path === "/v1/auth/logout" && method === "POST") return signOut(env, principal);
      if (path === "/v1/auth/delete-account" && method === "POST") return deleteAccount(req, env, principal);
      if (path === "/v1/account/mcp-connections" && method === "GET") return listMcpConnections(env, principal);
      const connectionMatch = /^\/v1\/account\/mcp-connections\/([a-f0-9-]{32,36})$/.exec(path);
      if (connectionMatch && method === "DELETE") return disconnectMcpConnection(env, principal, connectionMatch[1]);
      return routeApi(req, env, principal);
    }
    if (path === "/") return Response.redirect(`${publicOrigin(env)}/health`, 302);
    return json({ error: "Not found" }, 404);
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(sweepExpiredAuthData(env));
  },
};
