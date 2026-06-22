# ADR-0001: Core architecture & stack

- **Status:** Accepted
- **Date:** 2026-06-22
- **Deciders:** Bram, Codex

## Context

The product is **bar-first**: it lives in the macOS menu bar and all info is reachable through it via layered disclosure. Two forces shape the stack:

1. **Engine/bar separation (settled bet).** The **engine** computes pressure and emits a structured model; the **bar** is a thin renderer holding no portfolio logic. This is the main architectural bet and should hold regardless of language.
2. **The language tension (open).** A native macOS bar points toward **Swift** (reuse the CodexBar/RepoBar skeleton, talk to PDT directly). But our cleanest way to consume the PDT MCP is **mcporter**, which is **TypeScript** — pointing toward a TS core with a thin Swift bar over it.

This decision is finalized after exercising the PDT MCP and confirming the real PDT shapes are plain JSON that decode cleanly in Swift.

## Decision

Use **Option A — all native Swift**. Bar + engine stay in Swift; the app talks to PDT directly through a Swift adapter; mcporter is a research/dev tool only.

Rejected options:

- **Option B — Swift bar over a TS core.** Engine + PDT access in TypeScript (mcporter stays); the Swift bar runs/reads the core and renders the model.
- **Option C — Cross-platform tray (TS).** Skip native; one TS ecosystem; gives up the polished native skeleton. (Only if cross-platform becomes a requirement.)

## Options considered

- **A (native Swift):** + one app, one language, native feel, reuses real menu-bar code. − hand-roll MCP access in Swift; lose mcporter at runtime.
- **B (Swift bar + TS core):** + keeps mcporter and a clean engine in TS. − two languages / two runtimes to package and ship.
- **C (TS tray):** + simplest single ecosystem, cross-platform. − not native; doesn't reuse the CodexBar/RepoBar skeleton.

## Consequences

- Determines whether **mcporter** is a shipped dependency or just a research tool (see `docs/reuse-notes.md`).
- Sets the shape of `src/engine` and `src/bar` and the packaging story.
- Keeps the product in one native app/runtime. The cost is owning a small Swift PDT normalization layer, including join-key mapping, freshness derivation, closed-holding filtering, FX handling, and derived income-event signals.

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
choice is a packaging preference. Accepted choice: **Option A (native Swift;
mcporter = research/dev tool only)**. Nothing in PDT needs a TS runtime and the
shapes are Swift-decode-friendly. Option B remains viable only if the team later
chooses to ship reusable normalization as TypeScript; that would supersede this
ADR.
