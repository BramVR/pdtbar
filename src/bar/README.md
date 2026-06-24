# src/bar — the pulse (menu-bar renderer)

> Early architecture note. Current Swift implementation lives in `Sources/PDTBarCore` and `Sources/PDTBarApp`; ADR-0001 is accepted.

A **thin renderer** over the engine's model. Holds **no portfolio logic** — it only displays what the engine emits.

## Surface (layered, quiet-by-default)

- **Status item (always visible):** the Concentration Stack icon. Bar heights come from concentration/allocation facts; filled bars are attention-count notification fill capped at three; no separate dot.
- **The menu (the glance):** the ranked attention items, or **"all quiet"**; each expands to the numbers that triggered it.
- **Submenus (drill-down):** the per-facet snapshots — holdings/allocation, income/calendar, performance vs benchmark, cash — reachable without leaving the bar.

All information reachable through the bar, but via progressive disclosure — never a dashboard grid shown all at once.

## Reuse

Borrow **CodexBar / RepoBar** menu-bar patterns selectively: status item, menu + submenus, refresh/coalescing, cached pulse while refreshing, and crisp empty/loading/error states. Do not add generic OAuth, token entry, or provider switching to the Claude-only path. See `docs/reuse-notes.md`.

## Later

A native notification when a *new* high-pressure item appears is a candidate to un-defer (see `docs/mvp-scope.md`); keep it to new, high-severity items to preserve quiet-by-default.
