import { appName, type Env } from "./api";
import type { Principal } from "./auth";

export type Setup = {
  status: "ready" | "finish_setup" | "unknown";
  optional: true;
  appStoreUrl?: string;
  question?: string;
  instructions?: string[];
};

// 00Todo has no required onboarding beyond native Sign in with Apple.
// Badge notifications, voice input, and Apple Intelligence are optional.
// Consequently finish_setup is not emitted for this app's current setup.
export async function accountSetup(env: Env, principal: Principal, readTool: string): Promise<Setup> {
  const reviewerAllowed = (env.REVIEW_TENANT_IDS ?? "").split(",").some((id) => id.trim() === principal.tenantId);
  const evidence = await env.DB.prepare(`SELECT native_first_signed_in_at,
    EXISTS (SELECT 1 FROM review_credentials
      WHERE tenant_id = tenants.id AND revoked_at IS NULL AND expires_at > ?) AS active_reviewer
    FROM tenants WHERE id = ?`)
    .bind(new Date().toISOString(), principal.tenantId)
    .first<{ native_first_signed_in_at: string | null; active_reviewer: number }>();
  if (evidence?.native_first_signed_in_at || (reviewerAllowed && evidence?.active_reviewer === 1)) {
    return { status: "ready", optional: true };
  }
  const name = appName(env);
  return {
    status: "unknown",
    optional: true,
    appStoreUrl: "https://apps.apple.com/app/id6816729167",
    question: `Have you already configured the ${name} app? There is not enough native sign-in evidence to tell.`,
    instructions: [
      "Setup guidance is optional. You can keep using the connected tools and the data returned here.",
      `If needed, open ${name} on your iPhone or iPad, or install it from the App Store link.`,
      "Sign in with the same Apple account you used to connect this chat, then complete setup. For this app, signing in completes the required setup; notifications and voice features are optional.",
      `Return to this chat and call ${readTool} again to recheck. Keep the plugin connected; no disconnect, reinstall, or new authorization is needed.`,
    ],
  };
}
