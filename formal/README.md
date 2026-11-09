---
summary: "TLA+ models of PDTBar state machines, the pinned TLC runner, and the verify skill per subsystem."
read_when:
  - Changing launch, login, background refresh, snapshot, or read-state concurrency
  - Adding or updating a formal model
---

# Formal models

Each subsystem has a TLA+ model under `formal/<subsystem>/` and a project skill under `.claude/skills/verify-<subsystem>/` that says when and how to recheck it.

Run any model with the pinned runner (downloads `tla2tools.jar` 1.7.4 to `~/.cache/tlaplus`, checksum-verified, needs a JDK 11+):

```bash
Scripts/formal/tlc.sh formal/<subsystem>/<Spec>.tla
```

A pass covers the model and its bounds only. Each skill lists what its model leaves out.

## Models

- `launch-runtime`: launch, readiness probe, login handoff, first fetch, cached pulse, background refresh wiring. Skill `verify-launch-runtime`. Check: `formal/launch-runtime/check.sh`.
- `claude-login-process`: `claude auth login` PTY run, timeout, cancellation, process-tree cleanup. Skill `verify-claude-login-process`.
- `pulse-read-state`: mark-as-read, read-state reset, snapshot commit ordering. Skill `verify-pulse-read-state`. Check: `formal/pulse-read-state/check.sh`.
- `background-detail-refresh`: phases, retries, outage skip, price-history worker pool and deadline. Skill `verify-background-detail-refresh`.
