---
summary: "ADR process and index for lasting architecture decisions."
read_when:
  - Making or reviewing a non-obvious lasting decision
  - Adding or updating an ADR
  - Checking accepted architecture decisions
---

# Architecture Decision Records (ADRs)

Short documents that capture a non-obvious decision, the context behind it, and its consequences — so we don't re-litigate or repeat bad ideas. The `grill-with-docs` skill writes ADRs inline as decisions get pinned down.

## When to write one

Write an ADR when all of these are true: the decision is **non-obvious**, it has **lasting consequences**, and a reasonable person might **disagree**. (Routine choices don't need one.)

## Format

Copy `0000-template.md`, number it sequentially, and keep it short. Statuses: `Proposed` → `Accepted` → (later) `Superseded by ADR-XXXX`.

## Index

- `0001-core-architecture-and-stack.md` — engine/bar separation + native-Swift-vs-TS-core. **Status: Accepted** (native Swift; mcporter is research/dev only).
- `0002-pdt-public-rest-api.md` — PDT public REST API replaces the Claude CLI + PDT MCP path; browser sign-in (main) or pasted read-only token (fallback); Keychain this-device-only storage. **Status: Accepted**.
- `0003-credential-storage-and-unsaved-connections.md` — keep the data protection Keychain as the only durable store; hold a credential the store refuses instead of dropping it (#301); session-only use and dev signing wait for sign-off. **Status: Proposed**.
- _(grilling will add: pressure-thresholds, bar-information-architecture, history-store, PDT-integration, …)_
