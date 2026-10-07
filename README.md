# 00Todo

![00Todo checked-task mascot and wordmark](docs/brand/brand-preview.png)

A small SwiftUI task app backed by Cloudflare Workers and D1. Start and due dates are independent: a future start date or optional start time hides a task from Available until it begins, while a due date never hides it. Blocked holds work waiting on something; Someday holds ideas you may consider later. Both appear below scheduled work in Upcoming. Projects can be ordinary task lists or shopping lists.

The shape follows sister project 00Widget: a native client, a Worker with REST and MCP surfaces, and committed `.sample` configuration rather than committed deployment credentials. The mascot and palette are also a deliberate sibling identity, with the chart-shaped mouth replaced by checked tasks. The same API can later serve a Horizon OS app.

## Current state

- iOS/iPadOS: native Sign in with Apple, Keychain session storage, cached snapshot, a unified list of tasks and completable projects with subtasks, an Expand projects toggle that shows visible subtasks in place of their project row, Upcoming groups by effective start date, optional local start times, one focused manual create form with task/project selection in its title, on-device Quick Add from the toolbar, widget, or app-icon quick actions with automatic voice drafting, a small/medium Quick Add Home Screen widget, an MCP connection guide and management, account sign-out and re-authenticated account deletion.
- Worker: Apple identity verification, one tenant per stable Apple subject, tenant-scoped D1 reads and writes, separate app and MCP credentials, and OAuth authorization-code/PKCE for MCP clients with Apple web sign-in and consent.
- Hosted: the official app uses the Worker at `https://api.00todo.com`. Deployment config is gitignored; `server/wrangler.toml.sample` and `ios/project.yml.sample` are generic templates for your own deployment.

See [server/README.md](server/README.md) for Worker setup, [ios/README.md](ios/README.md) for the app, and [docs/brand/README.md](docs/brand/README.md) for the identity. Neither client needs a manually shared API token.

The screenshot-only simulator fixture in `ios/ScreenshotUITests` uses the same sample data as the sign-in screen's Try with demo data, without signing in or changing account data.

Dates are calendar days (`YYYY-MM-DD`), not timestamps. Optional start times are local wall-clock values (`HH:mm`). The iOS app compares with the device's local clock. API/MCP callers can pass `today=YYYY-MM-DD` and `time=HH:mm`, or the Worker uses `DEFAULT_TIME_ZONE`.

## License

Source code is MIT licensed; see [LICENSE](./LICENSE).

The 00Todo name, logos, icons, wordmarks, mascot, and other brand artwork,
including the files in `docs/brand` and the app assets generated from them,
are excluded from the MIT License and governed by
[docs/brand/LICENSE](./docs/brand/LICENSE). No trademark rights are granted.
