# Architecture Decision Records (ADRs)

Short documents that capture a non-obvious decision, the context behind it, and its consequences — so we don't re-litigate or repeat bad ideas. The `grill-with-docs` skill writes ADRs inline as decisions get pinned down.

## When to write one

Write an ADR when all of these are true: the decision is **non-obvious**, it has **lasting consequences**, and a reasonable person might **disagree**. (Routine choices don't need one.)

## Format

Copy `0000-template.md`, number it sequentially, and keep it short. Statuses: `Proposed` → `Accepted` → (later) `Superseded by ADR-XXXX`.

## Index

- `0001-core-architecture-and-stack.md` — engine/bar separation + native-Swift-vs-TS-core. **Status: Proposed** (resolve in the first grilling session).
- _(grilling will add: pressure-thresholds, bar-information-architecture, history-store, PDT-integration, …)_
