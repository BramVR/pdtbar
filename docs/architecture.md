---
summary: "Architecture overview: modules, entry points, data flow, and boundaries."
read_when:
  - Reviewing architecture before feature work
  - Refactoring modules, app lifecycle, or data flow
  - Changing engine/bar boundaries
---

# Architecture

## Modules

- `Sources/PDTBarCore`: normalized portfolio model, pressure engine, fixture/live data sources, menu descriptor rendering.
- `Sources/PDTBarAppSupport`: shared AppKit-adjacent support used by the app, smoke runner, and tests for app state, status visuals, menu actions, scripted launch seams, and local Claude/PDT connection handling.
- `Sources/PDTBarApp`: AppKit status item, Claude-first readiness probe, first fetch, cached pulse, menu actions.
- `Sources/PDTBarDev`: command-line model and descriptor inspection.
- `Sources/PDTBarSmoke`: scripted, packaged, Accessibility, manual Claude, and live PDT smoke checks.
- `Sources/PDTBarChecks`: deterministic invariant checks.

## Entry Points

- `pdtbar`: product menu-bar app.
- `pdtbar-dev`: developer fixture/model inspection.
- `pdtbar-smoke`: smoke proof runner.
- `pdtbar-checks`: deterministic checks.

## Data Flow

Claude/PDT readiness probe -> `PortfolioDataSource` -> normalized `PortfolioSnapshot` -> `SnapshotStore` -> pressure engine + Data Health -> `PortfolioPulseModel` -> `MenuDescriptor` -> `PDTBarAppSupport` action/status helpers -> AppKit menu/status item.

`PressureRunner` is the Pulse lifecycle seam for cached snapshots, first fetches,
and refreshed snapshots: it loads prior state, computes pressure, applies/reset
read state, commits snapshot metadata when needed, and returns the rendered
descriptor as one `PulseLifecycleResult`.

`PDTLaunchRuntime` is the scripted no-argument launch seam for readiness,
cached-pulse display, first-fetch success/failure, returning-launch background
detail refresh progress/completion/failure, retry gating, and descriptor updates.
The AppKit delegate renders runtime descriptors, forwards menu actions, and
performs platform lifecycle work such as timers, async process calls, and
status-item installation.

`ClaudeLocalConnection` is the local Claude/PDT connection seam for real product
launches: readiness, login handoff process handling, MCP list parsing,
ToolSearch resolution, PDT read-tool calls, retry classification, read-only
allowlists, and Claude tool-result parsing flow through app support instead of
the AppKit delegate.

`DataHealth` composes runtime/source facts into model state: Claude/PDT
readiness, required read tools, read-only policy, cache/source, detail-fill,
freshness, read-state, and redacted diagnostics. Menu descriptors render this
state; AppKit does not derive health facts.

Live and fixture PDT decoders both feed PDT-shaped DTO inputs into
`PDTSnapshotNormalizer`, so holding filtering, symbol quote joins, dividend
correction handling, optional facets, price history, and fixture/live parity
stay in one core normalization path. Fixture mode uses the same engine/render
path but is explicit developer tooling.

## Boundaries

- Engine computes pressure. Bar renders descriptors.
- App support holds reusable AppKit-adjacent glue; it is not a second engine.
- Launch runtime owns setup, retry, cached-pulse display, and background detail refresh state; Bar forwards menu actions.
- `ClaudeLocalConnection` owns local Claude CLI process/result handling; AppKit chooses when to start work and renders descriptors.
- PDT/MCP adapters normalize raw shapes before engine logic sees them.
- Financial data stays local; public proof is sanitized.

See also: [`claude-login-workflow.md`](claude-login-workflow.md), [`pdt/portfolio-data-source.md`](pdt/portfolio-data-source.md), [`reuse-notes.md`](reuse-notes.md).
