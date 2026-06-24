# src/engine — the pressure engine (the IP)

> Early architecture note. Current Swift implementation lives in `Sources/PDTBarCore`; ADR-0001 is accepted.

The **brain** of the product. Deterministic logic, no LLM required.

## Responsibility

Read the portfolio from PDT plus a small **history snapshot**, compute **pressure** across the facets, and emit a single **structured model** (likely JSON) for the bar to render.

## Inputs

- Current portfolio facets from PDT (holdings/allocation, income + calendar, performance, cash, corporate actions, benchmark).
- A small local **snapshot of prior state** (e.g. yesterday's weights/prices) — required to detect change.

## Output: "the model"

- **Ranked attention items** — each with: facet, what it is, a severity/score, and the supporting numbers that triggered it.
- **Per-facet snapshots** — the underlying data the bar exposes on drill-down.
- A clear **"all quiet"** signal when nothing crosses a threshold.

## Design rules

- **Deterministic & tunable.** Pressure is rules + thresholds over the data; thresholds are configurable. (See the pressure-thresholds ADR once written.)
- **No UI logic.** The engine knows nothing about the menu bar.
- **Cold-start aware.** Must produce useful output on first run using absolute-threshold signals that need no history (see `docs/v1-scope.md`).

## v1 scope

Facets: allocation/concentration, income events, big movers. One attention item rendered end-to-end first, then widen.
