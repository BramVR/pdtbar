---
summary: "v1 scope: Claude-first product slice, facets, history, cold-start, and quiet-day behavior."
read_when:
  - Scoping v1 work or deciding what to defer
  - Changing pressure facets, history, cold-start, or quiet-day behavior
  - Planning the next product slice
---

# v1 Scope

The goal of v1 is to ship the smallest coherent product: Claude-first launch, one real attention item or all-quiet state computed from PDT data, and a menu-bar pulse rendered from the normalized model. Everything else expands from that product spine.

## Definition Of Done

**Launch PDTBar with no arguments → probe Claude/PDT MCP → fetch required read-only PDT data → normalize and snapshot → the engine emits the model → the bar renders it (Concentration Stack icon, glance, expand, and basic drill-down).**

Concretely, v1 is "done" when:
- The no-argument app path is the product path; fixture mode remains explicit `--fixture` developer tooling.
- The app connects through the Claude CLI and configured PDT MCP server, then pulls only the required read tools.
- The engine computes pressure for the v1 facets and emits the structured model.
- The bar shows the Concentration Stack status icon, the ranked attention item(s) at the glance, expansion to the supporting numbers, and an "all quiet" state.
- Setup, fetch, stale, and retryable failure states are covered without publishing fixture or partial data as real.

## Sequencing (do these in order)

1. **Exercise the PDT MCP first.** Done for v1 on 2026-06-22; keep `docs/pdt/portfolio-data-source.md` as the data-shape source unless live PDT changes.
2. **Ship the Claude-only launch/fetch tracer.** No-argument launch, readiness probe, setup menu, first fetch, local snapshot, and returning-launch refresh are the product spine.
3. **Scope to 2-3 facets** (below) and get one attention item or all-quiet pulse rendered end-to-end.
4. **Then widen** — more facets, richer drill-down, tuning.

## v1 facet scope

Pick the highest-signal, lowest-data-dependency facets first:

- **Allocation / concentration** — a position, sector, cash allocation, or top-3 concentration drift crosses a deterministic line. *Absolute thresholds work on day one with no history; once prior state exists, repeat holding alerts require a fresh crossing from below the line, and top-3 drift can surface from the previous complete snapshot.*
- **Income events** — a dividend cut/raise, a payment landed, or an ex-dividend date within N days. *Mostly forward-looking calendar data.*
  The Income menu stays browsable rather than alert-like: it summarizes the current income window, shows the next ex-dividend/payment event, and keeps Pulse limited to pressure-worthy income items.
- **Big movers** — a holding moved more than X% over the window. *Needs a little history (see below).*

Current v1 drill-down covers allocation/concentration, income/calendar, and big movers/freshness. Attention rows carry structured explanation facts for trigger, severity, threshold, current value, prior value where available, and source slots; the menu renders those facts without deriving pressure reasons. The first menu section is Overview: a compact 2x2 grid separates portfolio value, price date, attention count, and top item or all-quiet status. Allocation starts with a first-class Portfolio allocation chart fed by core overview facts: total value, open holding count, top holdings, top-N concentration, sectors, asset types, and cash when present. The chart stays compact in the main menu; Detailed info opens the whole allocation overview plus individual holding drill-down rows. Allocation-derived pressure can also surface sector concentration, cash drag, and limited top-3 concentration drift as deterministic rows in Overview and Allocation. Freshness is ledger-backed: core computes fresh, stale, partial, and unknown states plus stale counts, oldest price rows, latest complete detail fill, and source caveats before the menu renderer sees it. Deferred full-product facets include performance-vs-benchmark divergence and corporate-action decisions; add them after the first three work.

## History store — required, kept tiny

Pressure is **change over time**, so the engine must remember prior state. This is **in v1, not optional** — but keep it minimal: a small local snapshot of the facet values needed to detect change (e.g. yesterday's weights and prices), with short retention. Borrow birdclaw's idea of a small local store; don't build a full mirror.

## Cold-start & quiet-day spec (the real UX risk)

The two hardest moments are day one and a calm day. Handle them deliberately:

- **Cold start (no prior snapshot):** lean on signals that need no local history — concentration too high, ex-dividend within N days, and big movers derived from PDT price history. Deferred facets can add cash-too-high later. The bar must be useful on the *first* run, not after a day of data. Take the first snapshot on connect.
- **Quiet day (nothing crosses a threshold):** show a real **"all quiet"** state with glanceable context (value, open holdings, top allocation, freshness) still present and the drill-down still reachable. A holding that was already above the concentration line in the prior snapshot is quiet unless it freshly crosses from below. Silence is a designed state, not an empty screen.
- **Caught up (current attention was marked read):** hide those Pulse rows, badge fill, and attention highlighting while keeping Allocation/Income/Big movers drill-down facts visible. If the same material fingerprint remains, it stays read; if the material bucket changes, it can surface again.

## Explicitly deferred (add only when earned)

- LLM-written narrative (v1 copy is **templated**, deterministic).
- A background, subscription-backed "analyze/narrate" agent runtime.
- Packaging / auto-update / distribution machinery (Sparkle, Homebrew).
- Extra connectors (oracle, imsg, poltergeist).
- A user-facing CLI (the engine emits JSON for testing; a CLI is a dev convenience, not a product surface).
- Non-Claude login providers, Codex login, generic OAuth, pasted API keys/tokens, and raw MCP JSON as product paths. Existing host-app auth reuse may be used when narrow, read-only, prompt-safe, and documented.
- mcporter as a shipped runtime path; it remains research/dev tooling unless a later ADR supersedes ADR-0001.

## One thing to actively consider un-deferring

A single **native macOS notification** when a *new* high-pressure attention item first appears. Push was the original "it comes to you" thesis, it's cheap (UNUserNotification), and without any push v1 is glance-only. Decide during grilling; if included, keep it to *new, high-severity* items to preserve quiet-by-default.
