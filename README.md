# 00Todo

![00Todo checked-task mascot and wordmark](docs/brand/brand-preview.png)

A small SwiftUI task app backed by Cloudflare Workers and D1. Start and due dates are independent: a future start date or optional start time hides a task from Available until it begins, while a due date never hides it. Projects can be ordinary task lists or shopping lists.

The shape follows sister project 00Widget: a native client, a Worker with REST and MCP surfaces, and committed `.sample` configuration rather than committed deployment credentials. The mascot and palette are also a deliberate sibling identity, with the chart-shaped mouth replaced by checked tasks. The same API can later serve a Horizon OS app.

## Current state

- iOS/iPadOS: native Sign in with Apple, Keychain session storage, cached snapshot, a unified list of tasks and completable projects with subtasks, an Expand projects toggle that shows visible subtasks in place of their project row, Upcoming groups by effective start date, optional local start times, one focused manual create form with task/project selection in its title, on-device Quick Add from the toolbar, widget, or app-icon quick actions with automatic voice drafting, a small/medium Quick Add Home Screen widget, an MCP connection guide and management, account sign-out and re-authenticated account deletion.
- Worker: Apple identity verification, one tenant per stable Apple subject, tenant-scoped D1 reads and writes, separate app and MCP credentials, and OAuth authorization-code/PKCE for MCP clients with Apple web sign-in and consent.
- Production: the Worker and D1 schema are deployed at `https://api.00todo.com`. The Apple App ID, web Services ID, and dedicated Sign in with Apple key are registered; the private key is installed as a Worker secret. Native sign-in reached the task list from TestFlight. The MCP browser consent round trip remains to be verified with an Apple web sign-in. The production config remains ignored; `server/wrangler.toml.sample` stays generic for open sourcing.
- TestFlight: app record `00Todo` uses `com.00todo.app`. Version `1.0 (202609291042)` is uploaded and assigned to the `Internal` group. This build targets iOS/iPadOS 27. Automatic distribution of future builds is disabled.

See [server/README.md](server/README.md) for Worker setup, [ios/README.md](ios/README.md) for the app, and [docs/brand/README.md](docs/brand/README.md) for the identity. Neither client needs a manually shared API token.

Dates are calendar days (`YYYY-MM-DD`), not timestamps. Optional start times are local wall-clock values (`HH:mm`). The iOS app compares with the device's local clock. API/MCP callers can pass `today=YYYY-MM-DD` and `time=HH:mm`, or the Worker uses `DEFAULT_TIME_ZONE`.
