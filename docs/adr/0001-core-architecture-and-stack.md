# ADR-0001: Core architecture & stack

- **Status:** Proposed — resolve in the first `grill-with-docs` session
- **Date:** TODO
- **Deciders:** TODO

## Context

The product is **bar-first**: it lives in the macOS menu bar and all info is reachable through it via layered disclosure. Two forces shape the stack:

1. **Engine/bar separation (settled bet).** The **engine** computes pressure and emits a structured model; the **bar** is a thin renderer holding no portfolio logic. This is the main architectural bet and should hold regardless of language.
2. **The language tension (open).** A native macOS bar points toward **Swift** (reuse the CodexBar/RepoBar skeleton, talk to PDT directly). But our cleanest way to consume the PDT MCP is **mcporter**, which is **TypeScript** — pointing toward a TS core with a thin Swift bar over it.

This decision can't be finalized until we've **exercised the PDT MCP** and seen how hard it is to talk to from Swift directly.

## Decision

**TODO** — choose one, after the PDT data investigation:

- **Option A — All native Swift.** Bar + engine in Swift; talk to PDT directly; mcporter is a research/dev tool only.
- **Option B — Swift bar over a TS core.** Engine + PDT access in TypeScript (mcporter stays); the Swift bar runs/reads the core and renders the model.
- **Option C — Cross-platform tray (TS).** Skip native; one TS ecosystem; gives up the polished native skeleton. (Only if cross-platform becomes a requirement.)

## Options considered

- **A (native Swift):** + one app, one language, native feel, reuses real menu-bar code. − hand-roll MCP access in Swift; lose mcporter at runtime.
- **B (Swift bar + TS core):** + keeps mcporter and a clean engine in TS. − two languages / two runtimes to package and ship.
- **C (TS tray):** + simplest single ecosystem, cross-platform. − not native; doesn't reuse the CodexBar/RepoBar skeleton.

## Consequences

- Determines whether **mcporter** is a shipped dependency or just a research tool (see `docs/reuse-notes.md`).
- Sets the shape of `src/engine` and `src/bar` and the packaging story.
- Lean recommendation pending data: **Option A** for minimalism in a bar-first product — but verify PDT-from-Swift feasibility first.

## Evidence (PDT MCP exercised 2026-06-22 — issue #8)

Full write-up and sanitized fixtures: [`../pdt/portfolio-data-source.md`](../pdt/portfolio-data-source.md).

- **Nothing in PDT is reachable only via mcporter.** Every v1 facet
  (allocation, income, big movers) is a plain MCP tool returning plain JSON —
  no TS-only surface forces mcporter into the runtime.
- **Shapes decode cleanly in Swift.** Money is `{value:String, currency:String}`,
  weights are doubles, dates are ISO-8601. A `Codable` layer over the ~15
  engine-relevant holding fields is straightforward. The only friction is
  payload size (~195 KB / ~90 fields per holding) — handled by projecting to
  needed fields, not a typing problem.
- **The real work is normalization, not transport** — joins
  (`symbolId ↔ symbolQuoteId`), FX (trading vs portfolio currency), per-holding
  freshness, deriving raise/cut (PDT has no such field), filtering closed
  positions. This `PortfolioDataSource` logic is pure and language-agnostic.

**This is enough evidence to decide.** Feasibility is no longer the blocker; the
choice is a packaging preference. Strengthened lean: **Option A (native Swift;
mcporter = research/dev tool only)** — nothing in PDT needs a TS runtime and the
shapes are Swift-decode-friendly. Choose **Option B** only to reuse the
normalization layer as shipped TypeScript. This ADR can move to **Accepted** on
that basis.
