import { json, type Env } from "./api";

// Workers Rate Limiting bindings are counted at the edge, so a refused request
// never reaches D1 and no limit costs a database write. Each binding is
// optional: a deployment without them (local tests, an old wrangler.toml)
// simply runs unlimited.

export const tooManyRequests = (): Response => {
  const response = json({ error: "Too many requests. Try again in a minute." }, 429);
  response.headers.set("Retry-After", "60");
  return response;
};

/// The client address Cloudflare observed, never a header the caller can set.
export function sourceKey(req: Request): string {
  return req.headers.get("cf-connecting-ip")?.trim() || "unknown";
}

async function allowed(limiter: RateLimit | undefined, key: string): Promise<boolean> {
  if (!limiter) return true;
  try { return (await limiter.limit({ key })).success; }
  catch { return true; }
}

/// Every non-health request, per IP, before any credential lookup.
export function sourceAllowed(env: Env, req: Request): Promise<boolean> {
  return allowed(env.SOURCE_LIMITER, `source:${sourceKey(req)}`);
}

/// Sign-in and OAuth routes, per IP. They call Apple or write unauthenticated
/// rows, so they get a much smaller budget than ordinary API traffic.
export function signInAllowed(env: Env, req: Request): Promise<boolean> {
  return allowed(env.SIGN_IN_LIMITER, `sign-in:${sourceKey(req)}`);
}

/// Authenticated REST and MCP requests, per account.
export function tenantAllowed(env: Env, tenantId: string): Promise<boolean> {
  return allowed(env.TENANT_LIMITER, `tenant:${tenantId}`);
}

export const tenantLimits = { tasks: 5000, projects: 1000 } as const;

/// Explains why a create would take an account past its item cap, or null
/// when it fits. Bounded storage per account keeps one account from filling the
/// database every account shares.
export async function capacityProblem(
  db: D1Database,
  tenantId: string,
  adding: { tasks?: number; projects?: number },
): Promise<string | null> {
  const row = await db.prepare(`SELECT
      (SELECT COUNT(*) FROM tasks WHERE tenant_id = ?1) AS tasks,
      (SELECT COUNT(*) FROM projects WHERE tenant_id = ?1) AS projects`)
    .bind(tenantId).first<{ tasks: number; projects: number }>();
  const tasks = Number(row?.tasks ?? 0) + (adding.tasks ?? 0);
  const projects = Number(row?.projects ?? 0) + (adding.projects ?? 0);
  if (tasks <= tenantLimits.tasks && projects <= tenantLimits.projects) return null;
  return `This account has reached its limit of ${tenantLimits.tasks} tasks and ${tenantLimits.projects} projects. Delete completed items to make room.`;
}
