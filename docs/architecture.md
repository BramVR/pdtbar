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

Claude/PDT readiness probe -> `PortfolioDataSource` -> normalized `PortfolioSnapshot` -> `SnapshotStore` -> pressure engine -> `PortfolioPulseModel` -> `MenuDescriptor` -> AppKit menu/status item.

Fixture mode uses the same engine/render path but is explicit developer tooling.

## Boundaries

- Engine computes pressure. Bar renders descriptors.
- Bar owns setup, retry, cached-pulse display, and menu actions.
- PDT/MCP adapters normalize raw shapes before engine logic sees them.
- Financial data stays local; public proof is sanitized.

See also: [`claude-login-workflow.md`](claude-login-workflow.md), [`pdt/portfolio-data-source.md`](pdt/portfolio-data-source.md), [`reuse-notes.md`](reuse-notes.md).
