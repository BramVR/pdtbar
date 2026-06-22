# Codex Kickoff Prompt — paste as the first message

> Paste this whole thing as your first message to Codex (or Claude Code). The repo already contains `CONTEXT.md`, `docs/product-brief.md`, `docs/mvp-scope.md`, `docs/reuse-notes.md`, and `docs/adr/`. This session writes **no product code** — alignment + domain modeling only.

---

We're starting development on this project. **Before you write any code, run Matt Pocock's `grill-with-docs` skill.** Refuse to implement until we've aligned: read the docs in this repo, then interview me branch by branch, build the domain model, and update `CONTEXT.md` and the ADRs in `docs/adr/` inline as decisions get made. If a question is answerable from the repo docs or by exercising the PDT MCP, do that instead of asking me.

## Guiding principle
**Keep it minimal. The product is the point, not the tooling.** Good basics, small surface area. Reuse a tool only where it clearly removes work; otherwise borrow the idea or the code. Do **not** adopt shared agent-script/workflow apparatus. See `docs/reuse-notes.md`.

## What we're building
An ambient, plug-and-play companion for an investor's **whole** portfolio on the PDT MCP (full portfolio, not just dividends). It lives in the **macOS menu bar** and surfaces only the few things worth attention now, via layered disclosure — **not** a dashboard clone. The value is **curation**: a "pressure" engine that emits a structured model, which a thin bar renders. Full context in `docs/product-brief.md`.

## Do this first
**Exercise the PDT MCP before grilling the pressure model.** Learn what it actually exposes, how fresh it is, and what's missing — the whole design is downstream of this. Record findings; they feed ADR-0001 (stack) and the threshold decisions.

## Grill me on these (resolve each; capture as ADRs) — product-critical only
1. **The pressure model — the core IP.** Per facet (income, performance, allocation, corporate-action, cash, benchmark): what signals and thresholds make something worth surfacing vs. silence? How is it tunable? Nothing we reuse solves this.
2. **Bar information architecture.** What's in the status item / at the glance / behind expansion / in submenus? How do we keep it quiet-by-default at the top while making all info reachable underneath?
3. **Core stack (ADR-0001).** Native Swift (reuse CodexBar/RepoBar, talk to PDT directly) vs. a thin Swift bar over a TS core (keeps mcporter). Decide *after* the PDT investigation; keep the engine cleanly separated from the bar; justify the pick.
4. **History & cold start.** A small snapshot store is required (pressure = change over time). Confirm its shape, and the day-one + quiet-day behavior per `docs/mvp-scope.md`.

(Channels beyond the bar, onboarding polish, and LLM-written narration are **later** — note, don't solve.)

## Scope the build small
Target the first slice in `docs/mvp-scope.md`: **connect PDT → engine emits the model with one real attention item → the bar renders it (glance + expand + basic drill-down + an "all quiet" state).** Start with 2–3 facets (allocation/concentration, income events, big movers), one attention item end-to-end, then widen.

## Hard constraints (non-negotiable — already in `CONTEXT.md`)
Informational not advice (descriptive, never prescriptive); read-only against PDT by default; local-first/privacy; plug-and-play (two clicks to value, quiet by default); engine/bar separation.

## Deliverables this session (no code)
1. Updated **`CONTEXT.md`** (domain model + sharpened language).
2. **ADRs** filled in: at least ADR-0001 (stack), plus new ones for pressure thresholds, bar information architecture, and history store.
3. A **minimal spec** of the first slice, ready for `/to-prd`.

## Later (don't run yet)
Once the engine + bar prove out: `/to-prd` → `/to-issues` (vertical slices) → `/prototype` → `/tdd`; then consider narration, a notification on new high-pressure items, and packaging.

**Start now: read the repo docs, exercise the PDT MCP, then begin `grill-with-docs`. Keep it minimal — product is key, and it shows in the bar.**
