#!/usr/bin/env node
// Provision a dedicated, disposable review tenant and a sign-in-only code.
// The raw code is saved locally in an ignored, owner-readable file, never Git.
import { randomBytes, randomUUID, createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const server = dirname(dirname(fileURLToPath(import.meta.url)));
const credentialPath = join(server, ".review-access.json");
if (existsSync(credentialPath)) {
  const saved = JSON.parse(readFileSync(credentialPath, "utf8"));
  console.log(`Reviewer tenant already provisioned: ${saved.tenantId}`);
  console.log(`Credential remains in ${credentialPath}`);
  process.exit(0);
}

const tenantId = randomUUID();
const code = `tt_review_${randomBytes(32).toString("base64url")}`;
const hash = createHash("sha256").update(code).digest("hex");
const now = new Date().toISOString();
const expiry = new Date(Date.now() + 365 * 86400000).toISOString();
const future = "2030-01-15";
const projectId = randomUUID();
const quoted = (value) => `'${String(value).replaceAll("'", "''")}'`;
const sql = [
  `INSERT INTO tenants (id, apple_subject, email, created_at, updated_at) VALUES (${quoted(tenantId)}, NULL, NULL, ${quoted(now)}, ${quoted(now)});`,
  `INSERT INTO review_credentials (token_hash, tenant_id, label, created_at, expires_at) VALUES (${quoted(hash)}, ${quoted(tenantId)}, 'OpenAI MCP reviewer', ${quoted(now)}, ${quoted(expiry)});`,
  `INSERT INTO projects (id, name, notes, tenant_id, start_date, due_date, completed_at, sort_order, created_at, updated_at) VALUES (${quoted(projectId)}, 'Weekend shopping', 'Sample shopping list for plugin review.', ${quoted(tenantId)}, NULL, NULL, NULL, 0, ${quoted(now)}, ${quoted(now)});`,
  ...[
    ["Review release notes", "Check the draft before sharing it.", null, null],
    ["Plan project launch", "Prepare a short launch checklist.", null, future],
    ["Buy oat milk", "Two cartons.", projectId, null],
    ["Pick up coffee beans", "Whole bean.", projectId, null],
  ].map(([title, notes, project, start]) => `INSERT INTO tasks (id, title, notes, project_id, start_date, due_date, completed_at, sort_order, created_at, updated_at, tenant_id) VALUES (${quoted(randomUUID())}, ${quoted(title)}, ${quoted(notes)}, ${project ? quoted(project) : "NULL"}, ${start ? quoted(start) : "NULL"}, NULL, NULL, 0, ${quoted(now)}, ${quoted(now)}, ${quoted(tenantId)});`),
].join("\n");

const temporary = mkdtempSync(join(tmpdir(), "00todo-review-"));
try {
  const path = join(temporary, "seed.sql");
  writeFileSync(path, sql, { mode: 0o600 });
  execFileSync("npx", ["wrangler", "d1", "execute", "00todo", "--remote", "--file", path], {
    cwd: server, stdio: "inherit",
  });
  writeFileSync(credentialPath, JSON.stringify({ tenantId, accessCode: code, expiresAt: expiry }, null, 2) + "\n", {
    mode: 0o600, flag: "wx",
  });
  console.log(`Reviewer tenant provisioned: ${tenantId}`);
  console.log(`Credential saved to ${credentialPath}; never put it in Git or the plugin ZIP.`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
