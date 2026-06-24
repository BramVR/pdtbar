# MVP Scope — the first slice

The goal of v1 is to **prove the pressure engine with the smallest possible build**: Claude-first launch, one real attention item or all-quiet state computed from PDT data, and a menu-bar pulse rendered from the normalized model. Everything else expands from that working tracer bullet.

## The first slice (definition of done)

**Launch PDTBar with no arguments → probe Claude/PDT MCP → fetch required read-only PDT data → normalize and snapshot → the engine emits the model → the bar renders it (Concentration Stack icon, glance, expand, and basic drill-down).**

Concretely, v1 is "done" when:
- The no-argument app path is the product path; fixture mode remains explicit `--fixture` developer tooling.
- The app connects through Claude Desktop and the configured PDT MCP server, then pulls only the required read tools.
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

- **Allocation / concentration** — a position's weight crosses a line (e.g. >20%, or drifted by >N points). *Absolute thresholds work on day one with no history.*
- **Income events** — a dividend cut/raise, a payment landed, or an ex-dividend date within N days. *Mostly forward-looking calendar data.*
- **Big movers** — a holding moved more than X% over the window. *Needs a little history (see below).*

Deferred facets: performance-vs-benchmark divergence, cash drag, corporate-action decisions — add after the first three work. (Cash drag is a cheap absolute-threshold add if PDT exposes cash readily.)

## History store — required, kept tiny

Pressure is **change over time**, so the engine must remember prior state. This is **in the MVP, not optional** — but keep it minimal: a small local snapshot of the facet values needed to detect change (e.g. yesterday's weights and prices), with short retention. Borrow birdclaw's idea of a small local store; don't build a full mirror.

## Cold-start & quiet-day spec (the real UX risk)

The two hardest moments are day one and a calm day. Handle them deliberately:

- **Cold start (no prior snapshot):** "what changed" signals can't fire yet, so lean on the **absolute-threshold** signals that need no history — concentration too high, cash too high, ex-dividend within N days. The bar must be useful on the *first* run, not after a day of data. Take the first snapshot on connect.
- **Quiet day (nothing crosses a threshold):** show a real **"all quiet"** state with the glanceable context (value / next payment) still present and the drill-down still reachable. Silence is a designed state, not an empty screen.

## Explicitly deferred (add only when earned)

- LLM-written narrative (v1 copy is **templated**, deterministic).
- A background, subscription-backed "analyze/narrate" agent runtime.
- Packaging / auto-update / distribution machinery (Sparkle, Homebrew).
- Extra connectors (oracle, imsg, poltergeist).
- A user-facing CLI (the engine emits JSON for testing; a CLI is a dev convenience, not a product surface).
- Non-Claude login providers, Codex login, generic OAuth, pasted API keys/tokens, and raw MCP JSON.
- mcporter as a shipped runtime path; it remains research/dev tooling unless a later ADR supersedes ADR-0001.

## One thing to actively consider un-deferring

A single **native macOS notification** when a *new* high-pressure attention item first appears. Push was the original "it comes to you" thesis, it's cheap (UNUserNotification), and without any push v1 is glance-only. Decide during grilling; if included, keep it to *new, high-severity* items to preserve quiet-by-default.
