import { appleEmail, exchangeAppleCode, verifyAppleIdToken } from "./apple";
import { appName, dateInZone, timeInZone, type Env } from "./api";
import { base64url, constantTimeEqual, decodeBase64url, findOrCreateTenant, publicOrigin, randomToken, sha256Hex } from "./auth";
import { startsLater } from "./model";
import { appleAuthorize, reviewTenantForAccessCode } from "./oauth";
import { tenantAllowed, tooManyRequests } from "./rateLimit";

const flowCookieName = "tt_dashboard_flow";
const sessionCookieName = "tt_dashboard_session";
const flowLifetimeSeconds = 600;
const sessionLifetimeSeconds = 86400;

type LoginFlow = { state: string; nonce: string; exp: number };
type Session = {
  kind: "apple" | "review"; tenantId: string; exp: number;
  appleSubject?: string; reviewCodeHash?: string;
};
type ProjectRow = {
  id: string; name: string; start_date: string | null; start_time: string | null;
  due_date: string | null; sort_order: number; created_at: string;
};
type TaskRow = {
  title: string; project_id: string | null; start_date: string | null;
  start_time: string | null; due_date: string | null; sort_order: number; created_at: string;
};
type Item = {
  title: string; kind: "project" | "task"; projectName?: string;
  startDate: string | null; startTime: string | null; dueDate: string | null;
  sortOrder: number; createdAt: string;
};

function configured(env: Env): boolean {
  return Boolean(env.OAUTH_SIGNING_SECRET && env.OAUTH_SIGNING_SECRET.length >= 32);
}

function appleConfigured(env: Env): boolean {
  return configured(env) && Boolean(env.APPLE_WEB_CLIENT_ID && env.APPLE_WEB_REDIRECT_URI && env.APPLE_PRIVATE_KEY);
}

function reviewConfigured(env: Env): boolean {
  return configured(env) && Boolean(env.REVIEW_TENANT_IDS?.trim());
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  })[character]!);
}

function page(env: Env, body: string, status = 200, signedIn = false): Response {
  return new Response(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(appName(env))} · Dashboard</title><style>
    :root{color-scheme:light dark;--bg:#f8fbff;--fg:#06152a;--muted:#56657a;--line:#e2e7ee;--card:#fff;--accent:#0968e8}
    @media(prefers-color-scheme:dark){:root{--bg:#06152a;--fg:#f8fbff;--muted:#98a8c0;--line:#1a2b48;--card:#0b1e38;--accent:#22a8ff}}
    *{box-sizing:border-box}body{font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;background:var(--bg);color:var(--fg);max-width:720px;margin:0 auto;padding:24px;line-height:1.45}
    header{display:flex;align-items:center;justify-content:space-between;gap:16px;border-bottom:1px solid var(--line);padding-bottom:16px;margin-bottom:32px}header strong{font-size:22px;font-weight:800}
    h1{font-size:23px;margin:0 0 8px}h2{font-size:18px;margin:32px 0 12px}p,.muted{color:var(--muted)}main{border:1px solid var(--line);border-radius:18px;padding:28px;background:var(--card)}
    a{color:var(--accent)}.apple-button{display:block;width:100%;text-align:center;padding:10px 18px;margin:20px 0 0;border-radius:6px;background:var(--fg);color:var(--bg);font-weight:600;text-decoration:none}
    input{font:inherit;padding:10px 12px;border:1px solid var(--line);border-radius:6px;background:var(--bg);color:var(--fg);max-width:100%;width:100%}
    button{font:inherit;font-weight:600;cursor:pointer;border:0;border-radius:6px;padding:10px 18px;background:var(--accent);color:#fff}details{margin-top:24px}summary{cursor:pointer}details form{margin-top:12px}details button{margin-top:12px}
    .logout{margin:0}.logout button{background:transparent;color:var(--accent);padding:4px 0}.items{list-style:none;margin:0;padding:0}.items li{padding:12px 0;border-top:1px solid var(--line)}.items li:first-child{border-top:0}.item-title{font-weight:600}.item-meta{font-size:13px;color:var(--muted);margin-top:3px}
    .count{font-size:13px;color:var(--muted);font-weight:400;margin-left:6px}.empty{color:var(--muted);margin:0}
  </style><header><strong>${escapeHtml(appName(env))}</strong>${signedIn ? '<form class="logout" method="post" action="/dashboard/logout"><button>Sign out</button></form>' : ""}</header><main>${body}</main></html>`, {
    status, headers: {
      "content-type": "text/html; charset=utf-8", "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'",
      "referrer-policy": "same-origin", "x-content-type-options": "nosniff",
    },
  });
}

function redirect(env: Env, path: string): Response {
  return new Response(null, { status: 303, headers: {
    Location: `${publicOrigin(env)}${path}`, "cache-control": "no-store",
  } });
}

function cookie(req: Request, name: string): string | null {
  return req.headers.get("cookie")?.split(";").map((part) => part.trim())
    .find((part) => part.startsWith(`${name}=`))?.slice(name.length + 1) ?? null;
}

async function hmac(env: Env, purpose: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.OAUTH_SIGNING_SECRET!),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return base64url(new Uint8Array(await crypto.subtle.sign("HMAC", key,
    new TextEncoder().encode(`dashboard:${purpose}:${value}`))));
}

async function signed<T>(env: Env, purpose: string, value: T): Promise<string> {
  const payload = base64url(new TextEncoder().encode(JSON.stringify(value)));
  return `${payload}.${await hmac(env, purpose, payload)}`;
}

async function verified<T>(env: Env, purpose: string, raw: string | null): Promise<T | null> {
  if (!configured(env) || !raw || raw.length > 2048) return null;
  const [payload, signature, extra] = raw.split(".");
  if (!payload || !signature || extra || !constantTimeEqual(signature, await hmac(env, purpose, payload))) return null;
  try { return JSON.parse(new TextDecoder().decode(decodeBase64url(payload))) as T; }
  catch { return null; }
}

function flowCookie(value: string): string {
  return `${flowCookieName}=${value}; Path=/auth/apple/callback; Max-Age=${flowLifetimeSeconds}; HttpOnly; Secure; SameSite=None`;
}

function clearFlowCookie(): string {
  return `${flowCookieName}=; Path=/auth/apple/callback; Max-Age=0; HttpOnly; Secure; SameSite=None`;
}

function sessionCookie(value: string): string {
  return `${sessionCookieName}=${value}; Path=/dashboard; Max-Age=${sessionLifetimeSeconds}; HttpOnly; Secure; SameSite=Lax`;
}

function clearSessionCookie(): string {
  return `${sessionCookieName}=; Path=/dashboard; Max-Age=0; HttpOnly; Secure; SameSite=Lax`;
}

async function currentSession(req: Request, env: Env): Promise<Session | null> {
  const session = await verified<Session>(env, "session", cookie(req, sessionCookieName));
  if (!session || !Number.isFinite(session.exp) || session.exp <= Date.now() / 1000
    || !/^[a-f0-9-]{36}$/.test(session.tenantId)) return null;
  if (session.kind === "apple" && typeof session.appleSubject === "string") {
    const tenant = await env.DB.prepare("SELECT id FROM tenants WHERE id = ? AND apple_subject = ?")
      .bind(session.tenantId, session.appleSubject).first();
    return tenant ? session : null;
  }
  if (session.kind === "review" && /^[a-f0-9]{64}$/.test(session.reviewCodeHash ?? "")) {
    const allowed = new Set((env.REVIEW_TENANT_IDS ?? "").split(",").map((id) => id.trim()));
    if (!allowed.has(session.tenantId)) return null;
    const credential = await env.DB.prepare(`SELECT tenant_id FROM review_credentials
      WHERE token_hash = ? AND tenant_id = ? AND revoked_at IS NULL AND expires_at > ?`)
      .bind(session.reviewCodeHash, session.tenantId, new Date().toISOString()).first();
    return credential ? session : null;
  }
  return null;
}

export async function dashboardLogin(req: Request, env: Env): Promise<Response> {
  if (await currentSession(req, env)) return redirect(env, "/dashboard");
  if (!appleConfigured(env) && !reviewConfigured(env)) return page(env, "<h1>Sign-in is not configured</h1>", 503);
  return page(env, `<h1>Sign in</h1><p>Use your ${escapeHtml(appName(env))} account to view current and scheduled tasks.</p>
    ${appleConfigured(env) ? '<a class="apple-button" href="/dashboard/login/apple">Sign in with Apple</a>' : ""}
    ${reviewConfigured(env) ? `<details><summary>Reviewer access</summary><p>Use the access code supplied in the secure reviewer instructions.</p>
      <form method="post" action="/dashboard/login/review"><label for="access-code">Review access code</label>
      <input id="access-code" name="accessCode" type="password" autocomplete="off" required maxlength="128">
      <button>Sign in as reviewer</button></form></details>` : ""}`);
}

export async function dashboardAppleLogin(env: Env): Promise<Response> {
  if (!appleConfigured(env)) return page(env, "<h1>Apple sign-in is not configured</h1>", 503);
  const flow: LoginFlow = {
    state: `ttdash_${randomToken(24)}`, nonce: randomToken(24),
    exp: Math.floor(Date.now() / 1000) + flowLifetimeSeconds,
  };
  const response = appleAuthorize(env, flow.state, flow.nonce);
  response.headers.set("set-cookie", flowCookie(await signed(env, "flow", flow)));
  return response;
}

export function isDashboardAppleState(state: string | null): boolean {
  return Boolean(state && /^ttdash_[A-Za-z0-9_-]{32}$/.test(state));
}

export async function dashboardAppleCallback(req: Request, env: Env, form: URLSearchParams): Promise<Response> {
  const flow = await verified<LoginFlow>(env, "flow", cookie(req, flowCookieName));
  const invalid = () => {
    const response = page(env, '<h1>Sign-in expired</h1><p>Please start again from <a href="/dashboard/login">the login page</a>.</p>', 401);
    response.headers.set("set-cookie", clearFlowCookie());
    return response;
  };
  if (!flow || !isDashboardAppleState(flow.state) || !Number.isFinite(flow.exp)
    || flow.exp <= Date.now() / 1000 || !constantTimeEqual(flow.state, form.get("state") ?? "")
    || !/^[A-Za-z0-9_-]{32}$/.test(flow.nonce)) return invalid();
  if (form.get("error")) return invalid();
  try {
    const identityToken = form.get("id_token") ?? "";
    const code = form.get("code") ?? "";
    const claims = await verifyAppleIdToken(identityToken, env.APPLE_WEB_CLIENT_ID!, flow.nonce);
    const exchanged = await exchangeAppleCode(env, code, env.APPLE_WEB_CLIENT_ID!, env.APPLE_WEB_REDIRECT_URI!);
    const verifiedClaims = await verifyAppleIdToken(exchanged.idToken, env.APPLE_WEB_CLIENT_ID!, flow.nonce);
    if (!constantTimeEqual(claims.sub, verifiedClaims.sub)) throw new Error("Apple account changed");
    const tenant = await findOrCreateTenant(env, claims.sub, appleEmail(verifiedClaims));
    const session: Session = {
      kind: "apple", tenantId: tenant.id, appleSubject: claims.sub,
      exp: Math.floor(Date.now() / 1000) + sessionLifetimeSeconds,
    };
    const response = redirect(env, "/dashboard");
    response.headers.append("set-cookie", clearFlowCookie());
    response.headers.append("set-cookie", sessionCookie(await signed(env, "session", session)));
    return response;
  } catch (cause) {
    console.warn("Dashboard Apple sign-in failed", cause instanceof Error ? cause.message : "unknown error");
    return invalid();
  }
}

export async function dashboardReviewLogin(req: Request, env: Env): Promise<Response> {
  if (!reviewConfigured(env)) return page(env, "<h1>Not found</h1>", 404);
  if (req.headers.get("origin") !== publicOrigin(env)) return page(env, "<h1>Invalid request origin</h1>", 403);
  if (Number(req.headers.get("content-length") ?? 0) > 1024) return page(env, "<h1>Invalid request</h1>", 400);
  const raw = await req.text();
  if (raw.length > 1024) return page(env, "<h1>Invalid request</h1>", 400);
  const code = new URLSearchParams(raw).get("accessCode") ?? "";
  const tenantId = await reviewTenantForAccessCode(env, code);
  if (!tenantId) return page(env, '<h1>Invalid or expired reviewer code</h1><p><a href="/dashboard/login">Try again</a>.</p>', 401);
  const session: Session = {
    kind: "review", tenantId, reviewCodeHash: await sha256Hex(code),
    exp: Math.floor(Date.now() / 1000) + sessionLifetimeSeconds,
  };
  const response = redirect(env, "/dashboard");
  response.headers.set("set-cookie", sessionCookie(await signed(env, "session", session)));
  return response;
}

function formattedDate(date: string, time: string | null): string {
  const parsed = new Date(`${date}T12:00:00Z`);
  const label = Number.isNaN(parsed.getTime()) ? date : new Intl.DateTimeFormat("en-GB", {
    day: "numeric", month: "short", year: "numeric", timeZone: "UTC",
  }).format(parsed);
  return time ? `${label} at ${time}` : label;
}

function itemHtml(item: Item, scheduled: boolean): string {
  const details = [
    item.kind === "project" ? "Project" : item.projectName ? `In ${item.projectName}` : null,
    scheduled && item.startDate ? `Starts ${formattedDate(item.startDate, item.startTime)}` : null,
    item.dueDate ? `Due ${formattedDate(item.dueDate, null)}` : null,
  ].filter((value): value is string => Boolean(value));
  return `<li><div class="item-title">${escapeHtml(item.title)}</div>${details.length
    ? `<div class="item-meta">${details.map(escapeHtml).join(" · ")}</div>` : ""}</li>`;
}

function section(title: string, items: Item[], scheduled: boolean): string {
  return `<section><h2>${title}<span class="count">${items.length}</span></h2>${items.length
    ? `<ul class="items">${items.map((item) => itemHtml(item, scheduled)).join("")}</ul>`
    : '<p class="empty">Nothing here.</p>'}</section>`;
}

export async function dashboard(req: Request, env: Env): Promise<Response> {
  const session = await currentSession(req, env);
  if (!session) {
    const response = redirect(env, "/dashboard/login");
    response.headers.set("set-cookie", clearSessionCookie());
    return response;
  }
  if (!(await tenantAllowed(env, session.tenantId))) return tooManyRequests();
  const [projectsResult, tasksResult] = await Promise.all([
    env.DB.prepare(`SELECT id, name, start_date, start_time, due_date, sort_order, created_at
      FROM projects WHERE tenant_id = ? AND completed_at IS NULL ORDER BY sort_order, created_at, id`)
      .bind(session.tenantId).all<ProjectRow>(),
    env.DB.prepare(`SELECT t.title, t.project_id, t.start_date, t.start_time, t.due_date, t.sort_order, t.created_at
      FROM tasks t LEFT JOIN projects p ON p.id = t.project_id AND p.tenant_id = t.tenant_id
      WHERE t.tenant_id = ? AND t.completed_at IS NULL
        AND (t.project_id IS NULL OR (p.id IS NOT NULL AND p.completed_at IS NULL))
      ORDER BY t.sort_order, t.created_at, t.id`).bind(session.tenantId).all<TaskRow>(),
  ]);
  const projects = new Map(projectsResult.results.map((project) => [project.id, project]));
  const now = new Date();
  const zone = env.DEFAULT_TIME_ZONE ?? "UTC";
  const today = dateInZone(now, zone);
  const time = timeInZone(now, zone);
  const available: Item[] = [];
  const scheduled: Item[] = [];
  for (const project of projectsResult.results) {
    const item: Item = { title: project.name, kind: "project", startDate: project.start_date,
      startTime: project.start_time, dueDate: project.due_date, sortOrder: project.sort_order, createdAt: project.created_at };
    (startsLater(project.start_date, project.start_time, today, time) ? scheduled : available).push(item);
  }
  for (const task of tasksResult.results) {
    const parent = projects.get(task.project_id ?? "");
    const taskStart = task.start_date ? `${task.start_date}T${task.start_time ?? "00:00"}` : "";
    const projectStart = parent?.start_date ? `${parent.start_date}T${parent.start_time ?? "00:00"}` : "";
    const useProjectStart = projectStart > taskStart;
    const item: Item = { title: task.title, kind: "task", projectName: parent?.name,
      startDate: useProjectStart ? parent?.start_date ?? null : task.start_date,
      startTime: useProjectStart ? parent?.start_time ?? null : task.start_time,
      dueDate: task.due_date, sortOrder: task.sort_order, createdAt: task.created_at };
    (startsLater(task.start_date, task.start_time, today, time)
      || startsLater(parent?.start_date ?? null, parent?.start_time ?? null, today, time)
      ? scheduled : available).push(item);
  }
  available.sort((a, b) => a.sortOrder - b.sortOrder || a.createdAt.localeCompare(b.createdAt));
  scheduled.sort((a, b) => (a.startDate ?? "").localeCompare(b.startDate ?? "")
    || (a.startTime ?? "").localeCompare(b.startTime ?? "")
    || a.sortOrder - b.sortOrder || a.createdAt.localeCompare(b.createdAt));
  return page(env, `<div class="dashboard"><h1>Your tasks</h1><p>Read-only view of unfinished tasks and projects.</p>
    ${section("Available now", available, false)}${section("Scheduled", scheduled, true)}</div>`, 200, true);
}

export function dashboardLogout(req: Request, env: Env): Response {
  if (req.headers.get("origin") !== publicOrigin(env)) return page(env, "<h1>Invalid request origin</h1>", 403);
  const response = redirect(env, "/dashboard/login");
  response.headers.set("set-cookie", clearSessionCookie());
  return response;
}
