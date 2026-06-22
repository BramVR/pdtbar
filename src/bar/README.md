# src/bar — the pulse (menu-bar renderer)

> Placeholder. No code yet — structure settles after the stack decision (ADR-0001).

A **thin renderer** over the engine's model. Holds **no portfolio logic** — it only displays what the engine emits.

## Surface (layered, quiet-by-default)

- **Status item (always visible):** one small signal (portfolio value or next-payment countdown) + a badge when there are attention items.
- **The menu (the glance):** the ranked attention items, or **"all quiet"**; each expands to the numbers that triggered it.
- **Submenus (drill-down):** the per-facet snapshots — holdings/allocation, income/calendar, performance vs benchmark, cash — reachable without leaving the bar.

All information reachable through the bar, but via progressive disclosure — never a dashboard grid shown all at once.

## Reuse

Start from the **CodexBar / RepoBar** menu-bar skeleton (status item, menu + submenus, refresh loop, OAuth, Keychain). Don't hand-build menu-bar plumbing. See `docs/reuse-notes.md`.

## Later

A native notification when a *new* high-pressure item appears is a candidate to un-defer (see `docs/mvp-scope.md`); keep it to new, high-severity items to preserve quiet-by-default.
