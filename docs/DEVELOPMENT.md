---
summary: "Development workflow: build, checks, smoke commands, and docs inventory."
read_when:
  - Starting local development
  - Running build/test/smoke checks
  - Updating contributor or agent workflow
---

# Development

## Docs First

```bash
make docs-list
```

Read matching `Read when` hints before editing. Keep docs current with behavior.

## Build And Checks

```bash
make check
swift build
swift run pdtbar-checks
swift test
./Scripts/test.sh
make test
```

`make check` is the default deterministic handoff gate. It delegates to
`Scripts/check.sh`, which checks script syntax, builds the Swift package, runs
`pdtbar-checks`, and runs the sharded Swift test runner. It does not run live
Claude/PDT, Keychain, 1Password, Accessibility, or packaged-app flows.

`Scripts/test.sh` runs Swift Testing suites through the PDTBar sharder. Useful knobs:

```bash
PDTBAR_TEST_GROUP_SIZE=1 PDTBAR_TEST_SUITE_TIMEOUT=60 ./Scripts/test.sh
PDTBAR_TEST_SHARD_INDEX=0 PDTBAR_TEST_SHARD_COUNT=2 ./Scripts/test.sh
```

## Developer Commands

```bash
make start
make stop
./Scripts/check.sh scripts
swift run pdtbar-dev model --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift build --product pdtbar
./Scripts/package_app.sh
./Scripts/launch.sh
```

## Smoke Gate

```bash
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-login-handoff
swift run pdtbar-smoke scripted-setup-retry
swift run pdtbar-smoke scripted-pulse-mark-read
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
swift run pdtbar-smoke real-claude-flow-ax
```

Optional local/live checks:

```bash
swift run pdtbar-smoke manual-claude-pdt --model opus
swift run pdtbar-smoke live-pdt
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
swift run pdtbar-smoke packaged-app --app PDTBar.app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/packaged-snapshot
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse
```

See [`smoke-checks.md`](smoke-checks.md) before changing smoke behavior.

## Project Map

```text
PDTBar/
├── README.md
├── CONTEXT.md
├── Package.swift
├── Scripts/docs-list.mjs
├── docs/
│   ├── README.md
│   ├── DEVELOPMENT.md
│   ├── architecture.md
│   ├── product-brief.md
│   ├── v1-scope.md
│   ├── reuse-notes.md
│   ├── claude-login-workflow.md
│   ├── smoke-checks.md
│   ├── adr/
│   └── pdt/
├── Sources/
│   ├── PDTBarApp/
│   ├── PDTBarCore/
│   ├── PDTBarDev/
│   ├── PDTBarSmoke/
│   └── PDTBarChecks/
└── src/
    ├── engine/
    └── bar/
```
