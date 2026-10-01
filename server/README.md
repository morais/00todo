# 00Todo Worker

Cloudflare Worker with D1 storage, REST API, and a stateless MCP endpoint. Node 22+ and Wrangler are needed for development and deployment.

## Configuration

Copy `wrangler.toml.sample` to ignored `wrangler.toml`. Set a real D1 ID, `PUBLIC_ORIGIN`, `DEFAULT_TIME_ZONE`, the Apple identifiers, and the custom-domain route. The committed sample deliberately uses `api.example.com`.

The Apple Developer setup needs:

1. A primary iOS App ID with Sign in with Apple enabled. `APPLE_APP_CLIENT_ID` is its exact bundle ID.
2. A web Services ID associated with that primary App ID. `APPLE_WEB_CLIENT_ID` is the Services ID. Register your API domain and the return URL `https://<your API host>/auth/apple/callback`.
3. A Sign in with Apple key for the same team, with its `.p8` PEM as the `APPLE_PRIVATE_KEY` secret. Set `APPLE_TEAM_ID` and `APPLE_KEY_ID` in the ignored config. An App Store Connect API key is **not** a substitute for this key.

Install Worker secrets without committing them:

```sh
npx wrangler secret put APPLE_PRIVATE_KEY < /secure/path/AuthKey_SIGNIN.p8
openssl rand -hex 32 | npx wrangler secret put OAUTH_SIGNING_SECRET
```

For local development, set `PUBLIC_ORIGIN = "http://localhost:8787"`, remove the custom-domain route, enable `workers_dev`, and use a local D1 ID. Copy `.dev.vars.example` to ignored `.dev.vars` and fill it with development-only secrets. The Apple web callback requires a registered HTTPS return URL for a real end-to-end login; use the production Worker or a registered HTTPS tunnel for that check.

```sh
npm install
npx wrangler d1 migrations apply 00todo --local
npm run dev
npm run typecheck
npm test
```

For a fresh production database, `npx wrangler d1 create 00todo`, set its ID in the ignored config, then `npx wrangler d1 migrations apply 00todo --remote` and `npm run deploy`. For an existing database, apply outstanding migrations before deploying the Worker. Do not recreate the production database on future deploys.

## Authentication and tenancy

`POST /v1/auth/apple` accepts a native Apple identity token, one-use authorization code, and raw nonce. The Worker verifies Apple's signature, issuer, audience, time, and nonce, exchanges the code with Apple, then creates or finds a tenant by Apple's stable `sub` (never by email). It issues a 90-day opaque app credential; only its SHA-256 hash is stored. `POST /v1/auth/logout` revokes it. `POST /v1/auth/delete-account` requires a fresh Apple sign-in for the same subject, revokes the new Apple access token, and deletes that tenant's tasks, projects, OAuth state, and credentials.

MCP clients use authorization-code flow with S256 PKCE, resource indicator `<PUBLIC_ORIGIN>/mcp`, dynamic client registration, Apple web sign-in, and an explicit consent screen. Discovery is at `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`; authorization, registration and token endpoints are in the advertised metadata. The consent screen marks a client as verified only when its exact callback URL is listed in `MCP_VERIFIED_CLIENTS`, and then shows the server-owned name; other clients show their self-asserted name with an unverified warning and the callback address. MCP credentials are separate, audience-bound, scope-limited, and expire after 30 days. App credentials cannot call MCP; MCP credentials cannot call REST.

The iOS app's MCP Connections screen shows the server address and active OAuth grants. Its app-only `GET /v1/account/mcp-connections` lists grant IDs, client names, scopes, and timestamps, never tokens or hashes. `DELETE /v1/account/mcp-connections/:id` revokes one of the signed-in tenant's grants. There is no bare-token integration flow.

### Dedicated MCP reviewer access

For public MCP review, set up a dedicated tenant with `node scripts/provision-review.mjs` after applying migrations. The script seeds sample tasks and a shopping project, saves the one-year access code to ignored `server/.review-access.json` (mode 0600), and prints only the tenant UUID. Put that UUID in `REVIEW_TENANT_IDS` in the ignored production Wrangler config and deploy. The MCP authorization page then offers a discreet **Reviewer access** option alongside Sign in with Apple. Share the code only in the review portal's secure credentials field, never in the plugin ZIP or Git.

The code is stored only as a SHA-256 hash in `review_credentials`. It has no REST or MCP bearer scope: it can only select the allowlisted demo tenant for a pending, rate-limited OAuth flow, followed by the normal client consent screen. Remove the UUID from `REVIEW_TENANT_IDS` to disable reviewer sign-in immediately. A review code can also be revoked in D1 by setting `revoked_at`; separately revoke any issued MCP grants when review ends.

Three Workers Rate Limiting bindings in `wrangler.toml.sample` cap traffic before D1 is touched: 600 requests a minute per IP, 20 sign-in or OAuth requests a minute per IP, and 300 authenticated requests a minute per account. Refused requests get `429` with `Retry-After: 60`. Each account is also capped at 5,000 tasks and 1,000 projects.

All task/project queries include `tenant_id`, and D1 triggers prevent a task from referring to another tenant's project. A legacy tenant preserves any old local prototype data without exposing it to Apple accounts.

## REST API

Authenticated routes require `Authorization: Bearer <app credential>`. `/health` is public. JSON uses camelCase and dates are nullable `YYYY-MM-DD` strings.

| Method | Route | Purpose |
| --- | --- | --- |
| GET | `/v1/me` | Current tenant ID and optional email |
| GET | `/v1/snapshot` | Open projects and tasks, plus those completed in the last 90 days (`completedSince`); returns an `ETag` and answers `304` to a matching `If-None-Match` |
| GET/POST | `/v1/projects` | List/create projects |
| POST | `/v1/projects-with-tasks` | Atomically create a project and up to 50 subtasks |
| GET/PATCH/DELETE | `/v1/projects/:id` | Read/edit/delete a project |
| GET/POST | `/v1/tasks` | List/create tasks |
| GET/PATCH/DELETE | `/v1/tasks/:id` | Read/edit/delete a task |
| GET | `/v1/account/mcp-connections` | List active MCP OAuth grants |
| DELETE | `/v1/account/mcp-connections/:id` | Revoke one MCP OAuth grant |

Projects are completable top-level items with notes, sort order, independent nullable `startDate` and `dueDate`, an optional `startTime` (24-hour `HH:mm`, requiring `startDate`), and tasks as subtasks. `GET /v1/projects` defaults to `view=all`; `view=available` hides future-start projects, `view=upcoming` lists them, and `view=completed` lists completed projects. `GET /v1/tasks` defaults to `view=available`; alternatives are `upcoming`, `completed`, and `all`. `today=YYYY-MM-DD` and `time=HH:mm` can override the server's clock for filtering; otherwise the configured default time zone is used. Available means incomplete with neither the task nor its project starting in the future, and with the project itself still open. Start times are local wall-clock times in the app or the API's selected time zone, not UTC timestamps. Deleting a project makes its subtasks standalone tasks.

Create requests may include a client-generated UUID `id` for a task, project, or each task in a project batch. Repeating a create with the same ID returns the existing item, allowing the iOS offline queue to retry after a lost response without making duplicates. IDs remain tenant-scoped in all reads and updates.

## MCP

`POST /mcp` supports JSON-RPC `initialize`, `ping`, `tools/list`, and `tools/call`. Tools list/create/update/delete tasks and projects and use the same validation as REST. The endpoint returns a `WWW-Authenticate` challenge with protected-resource metadata when authentication is absent. The endpoint is stateless; OAuth is required to obtain a bearer token.

## Checks

`npm run typecheck` and `npm test` cover models and MCP behavior.
