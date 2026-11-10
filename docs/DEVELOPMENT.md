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
make docs-list
make docs-site
make docs-site-test
make start
make stop
make test
make check
swift build
swift run pdtbar-checks
swift test
./Scripts/test.sh
```

`make check` is the default deterministic handoff gate. It delegates to
`Scripts/check.sh`, which checks script syntax, builds the Swift package, runs
`pdtbar-checks`, and runs the sharded Swift test runner. `pdtbar-checks` is now
kept to command-style fixture, PDT API, and tooling-contract proof; core model,
parser, runner, normalization, and rendering regressions live in
`Tests/PDTBarTests` and run under `swift test`. It does not run live PDT,
Keychain, 1Password, Accessibility, or packaged-app flows, or the sandboxed
scripted API matrix (`make smoke-api`, see `docs/smoke-checks.md`).

`Scripts/test.sh` runs Swift Testing suites through the PDTBar sharder. Useful knobs:

```bash
PDTBAR_TEST_GROUP_SIZE=1 PDTBAR_TEST_SUITE_TIMEOUT=60 ./Scripts/test.sh
PDTBAR_TEST_SHARD_INDEX=0 PDTBAR_TEST_SHARD_COUNT=2 ./Scripts/test.sh
```

## Public Docs Site

```bash
make docs-site
make docs-site-test
make docs-site-clean
```

`make docs-site` builds the allowlisted public site into `dist/docs-site`.
Only pages listed in `docs/public-docs.json` are published; contributor,
agent, planning, and smoke docs stay out of the public artifact unless a
maintainer explicitly allowlists them. The Pages workflow builds and
smoke-tests the site on PRs and `main`, then deploys only from `main` when
GitHub Pages is enabled for the repository.

## Developer Commands

```bash
make docs-site
make docs-site-test
make start
make stop
make test
make check
./Scripts/check.sh scripts
swift run pdtbar-dev model --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json --portfolio-values visible
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json --portfolio-values hidden
swift run pdtbar-dev pdt-status --store <file>
swift build --product pdtbar
./Scripts/package_app.sh
ARCHES="$(uname -m)" ./Scripts/package_release_app.sh v0.0.0-test
./Scripts/launch.sh
./Scripts/compile_and_run.sh
swift run pdtbar-smoke app-bundle-packaging
```

`make start` is the normal manual UX launch. It stops existing PDTBar processes,
packages `PDTBar.app`, and launches the packaged app. `./Scripts/compile_and_run.sh`
is the explicit one-shot equivalent. `make stop` stops the packaged app and may
also clean up old raw SwiftPM debug/release processes from historical runs.
Normal product setup is the PDT REST API connection: Sign in with PDT (browser)
or a pasted PDT token, kept in the Keychain. Product code starts no process.
Deterministic app smokes launch
`pdtbar --app-support-dir <isolated> --scripted-pdt <file>` through
`pdtbar-smoke`; the app refuses `--scripted-pdt` without an isolated app support
directory.

`pdtbar-dev pdt-sign-in|pdt-status|pdt-refresh|pdt-disconnect --store <file>`
is the opt-in live PDT sign-in proof. It keeps the credential in a mode-0600
file at the given path, never the Keychain, and prints only states, expiry,
statuses, key names, and token fingerprints. `pdt-sign-in ... --no-browser`
prints the authorize URL instead of opening it, for shells whose `open` does
not reach the user's browser. See `docs/smoke-checks.md`.

Historical workaround only: launching raw `.build/debug/pdtbar`, keeping it
alive in a foreground shell, `tmux`, or `nohup`, and checking truncated process
names were temporary first-run incident workarounds. Normal first-run UX testing
must use the packaged app path above.

## Smoke Gate

```bash
swift build
swift test
swift run pdtbar-checks
make smoke-api
swift run pdtbar-smoke scripted-api-client
swift run pdtbar-smoke scripted-api-snapshot
swift run pdtbar-smoke scripted-api-auth
swift run pdtbar-smoke scripted-sign-in
swift run pdtbar-smoke scripted-setup-retry
swift run pdtbar-smoke scripted-pulse-mark-read
swift run pdtbar-smoke copy-holding-identifier-action
swift run pdtbar-smoke portfolio-summary-proof --peekaboo /opt/homebrew/bin/peekaboo
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
```

Use the commands above as the local deterministic smoke gate. `make check`
invokes the sharded Swift test runner through `Scripts/test.sh`, which bounds
suite groups around `swift test`. The scripted app smokes open the real menu
through Accessibility only when it is already granted, and otherwise return
`skipped` after proving launch state from the scripted connection's event log.

First-run packaged regression gate:

```bash
swift build --product pdtbar
./Scripts/package_app.sh
swift run pdtbar-smoke app-bundle-packaging
swift run pdtbar-smoke packaged-onboarding --app PDTBar.app
```

Release app archive gate:

```bash
ARCHES="$(uname -m)" ./Scripts/package_release_app.sh v0.0.0-test
ditto -x -k .build/release-artifacts/PDTBar-macos-$(uname -m)-0.0.0-test.zip /tmp/pdtbar-release-proof
codesign --verify --deep --strict --verbose=2 /tmp/pdtbar-release-proof/PDTBar.app
```

Optional local/live checks:

```bash
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
swift run pdtbar-smoke packaged-app --app PDTBar.app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/packaged-snapshot
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse
```

See [`smoke-checks.md`](smoke-checks.md) before changing smoke behavior.

mcporter was a past research tool for exploring the PDT MCP (ADR-0001). The
repo no longer pins or runs it; for research, run it unpinned with
`npx mcporter`.

## Handoff Gate

Expected handoff for normal changes:

```bash
make docs-list
make test
make check
swift build --product pdtbar
./Scripts/package_app.sh
swift run pdtbar-smoke app-bundle-packaging
swift run pdtbar-smoke packaged-onboarding --app PDTBar.app
```

Add optional live proof only when explicitly requested or when the change needs
live PDT, Accessibility, or real UI screenshot evidence.

For release/distribution changes, also read [`RELEASING.md`](RELEASING.md) and run the release archive gate above.

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
│   ├── pdt-connection-workflow.md
│   ├── smoke-checks.md
│   ├── adr/
│   └── pdt/
├── Sources/
│   ├── PDTBarApp/
│   ├── PDTBarAppSupport/
│   ├── PDTBarCore/
│   ├── PDTBarDev/
│   ├── PDTBarSmoke/
│   └── PDTBarChecks/
└── src/
    ├── engine/
    └── bar/
```
