---
summary: "Agent-facing docs index and read-before-change workflow."
read_when:
  - Starting work in this repo
  - Choosing which project docs to read
  - Adding or reorganizing documentation
---

# PDTBar Docs

Docs are agent-facing source of truth. Root `README.md` stays human/product-facing.

## Workflow

1. Run `make docs-list`.
2. Read every doc whose `Read when` hint matches the task.
3. Change behavior and docs together.
4. Add `summary` and `read_when` frontmatter to every new docs page.
5. Keep user-facing product copy in the root README; keep implementation, smoke, and agent routing here.

## Start Here

- [`product-brief.md`](product-brief.md) - product mission, target user, what PDTBar is not.
- [`v1-scope.md`](v1-scope.md) - v1 product slice, facets, cold-start, quiet day.
- [`architecture.md`](architecture.md) - modules, entry points, data flow.
- [`DEVELOPMENT.md`](DEVELOPMENT.md) - local build/test/smoke workflow.
- [`claude-login-workflow.md`](claude-login-workflow.md) - product launch, setup, first fetch.
- [`smoke-checks.md`](smoke-checks.md) - deterministic and live proof gates.
- [`reuse-notes.md`](reuse-notes.md) - CodexBar/RepoBar/mcporter/birdclaw reuse boundaries.

## Domain And Decisions

- [`../CONTEXT.md`](../CONTEXT.md) - domain language and non-negotiables.
- [`pdt/README.md`](pdt/README.md) - PDT data reality and sanitized fixtures.
- [`adr/README.md`](adr/README.md) - architecture decision records.

## Current Shape

- `Sources/PDTBarCore`: pressure model, normalization, fixtures, smokeable core.
- `Sources/PDTBarAppSupport`: shared AppKit-adjacent support for the app, smoke runner, and tests.
- `Sources/PDTBarApp`: macOS menu-bar product path.
- `Sources/PDTBarDev`: developer descriptors/model inspection.
- `Sources/PDTBarSmoke`: scripted and live smoke checks.
- `Sources/PDTBarChecks`: deterministic checks.
