---
summary: "TLA+ models of PDTBar state machines, the pinned TLC runner, and the verify skill per subsystem."
read_when:
  - Changing launch, PDT connection, background refresh, snapshot, or read-state concurrency
  - Adding or updating a formal model
---

# Formal models

Each subsystem has a TLA+ model under `formal/<subsystem>/` and a project skill under `.claude/skills/verify-<subsystem>/` that says when and how to recheck it.

Run any model with the pinned runner (downloads `tla2tools.jar` 1.7.4 to `~/.cache/tlaplus`, checksum-verified, needs a JDK 11+):

```bash
Scripts/formal/tlc.sh formal/<subsystem>/<Spec>.tla
```

A pass covers the model and its bounds only. Each skill lists what its model leaves out.

Models and their skills name Swift code by symbol (`PDTLaunchRuntime.signIn`, `Persistence.swift`), never by line number. `swift run pdtbar-checks` fails on a line anchor or on a code span naming something no Swift, test, model, or script file has; write a removed name as plain text.

## Models

- `launch-runtime`: launch, PDT connection check / sign-in / disconnect, first fetch, cached pulse, background refresh wiring. Skill `verify-launch-runtime`. Check: `formal/launch-runtime/check.sh`. Mutations: `formal/launch-runtime/mutations.sh`.
- `pulse-read-state`: mark-as-read, read-state reset, snapshot commit ordering. Skill `verify-pulse-read-state`. Check: `formal/pulse-read-state/check.sh`.
- `background-detail-refresh`: the PDT API refresh's phases, paged facets, sync-ending failures, cancellation checkpoints, single snapshot commit, outcome, and stored sync failure. Skill `verify-background-detail-refresh`. Mutations: `formal/background-detail-refresh/mutations.sh`.
