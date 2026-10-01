import type { Env } from "./api";

// The OpenAI submission portal fetches this exact well-known path and expects
// only the deployment-specific token, without JSON, a newline, or a wrapper.
export function openAIAppsChallenge(req: Request, env: Env): Response {
  const token = (env.OPENAI_APPS_CHALLENGE_TOKEN ?? "").trim();
  if (!token) return Response.json({ error: "Not found" }, { status: 404 });
  return new Response(req.method === "HEAD" ? null : token, {
    status: 200,
    headers: {
      "content-type": "text/plain; charset=utf-8",
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  });
}
