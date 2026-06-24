# CONTEXT.md

> The project's source of truth for **domain model, shared language, and hard constraints.** This is a *living* document. The `grill-with-docs` session fills in the `TODO` items and sharpens the language as decisions are made. Keep it terse and current.

## Product in one paragraph

An ambient, plug-and-play companion for an investor's **whole** portfolio, built on the Portfolio Dividend Tracker (PDT) MCP (which exposes holdings, performance, gains, allocation, transactions, cash, corporate actions, ETF x-ray, and benchmarks — not just dividends). It lives in the macOS menu bar and surfaces only the few things worth attention right now, via layered disclosure. It is **not** a clone of the PDT dashboard; the value is curation, not completeness.

## Domain model (sharpen during grilling)

- **Facet** — a dimension of the portfolio the engine watches: *income, performance, allocation, corporate-action, cash, benchmark*.
- **Pressure** — a judgment that something in a facet crosses a threshold of "worth your attention now" (a change, a breach, or an upcoming event). Distinct from raw data: data is "NVDA is 22%"; pressure is "NVDA rose to 22% from 18% — concentration climbing."
- **Attention item** — one unit of pressure the engine outputs: what it is, which facet, a severity/score, and the supporting numbers that triggered it.
- **The model** — the structured output the engine emits and the bar renders: the ranked attention items + their supporting data + per-facet snapshots. (Likely JSON.)
- **Pulse** — the menu-bar surface that renders the model.
- **Quiet-by-default** — the bar shows attention items at the glance and is silent ("all quiet") when nothing crosses a threshold; everything else is reachable underneath but never shouted.

## Shared language (ubiquitous language)

Anchor terms above (**facet, pressure, attention item, the model, pulse, quiet-by-default**). Reconcile with PDT's own vocabulary (holding, dividend, booking, corporate action, x-ray, benchmark). **grill-with-docs owns expanding this list** — add terms here as they're pinned down; don't pre-invent.

## Hard constraints (decided — non-negotiable)

1. **Informational, not financial advice.** Descriptive only ("KO cut its dividend"), never prescriptive ("sell KO"). Anything advice-like is out of scope / compliance-gated.
2. **Read-only against PDT by default.** No writes, trades, or fund movements without an explicit, confirmed, opt-in action.
3. **Local-first / privacy.** Keep financial data local. If an LLM is ever added, minimize what is sent and document it.
4. **Plug-and-play.** Two clicks to value, ~60-second aha, zero commands in daily use, quiet by default. Judge every decision against this.
5. **Engine/bar separation.** The engine computes; the bar renders. The bar holds no portfolio logic.

## Open questions (TODO — resolve in grilling, record as ADRs)

- [x] **PDT data reality** — exercised 2026-06-22; see `docs/pdt/` (seam, schemas, sanitized fixtures). All v1 facets have dedicated read tools; gaps (cross-tool join key, derived raise/cut, per-holding freshness) documented.
- [x] **Core stack** — native Swift; mcporter is research/dev only. See ADR-0001.
- [ ] **Pressure thresholds** — the concrete signals/thresholds per facet, and how they're tuned.
- [ ] **Bar information architecture** — what's in the status item / at the glance / behind expansion / in submenus.
- [ ] **History store** — confirmed required (pressure = change over time); decide shape and retention. See `docs/v1-scope.md`.
- [ ] **Cold-start & quiet-day behavior** — see `docs/v1-scope.md`.
