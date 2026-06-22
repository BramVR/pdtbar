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
