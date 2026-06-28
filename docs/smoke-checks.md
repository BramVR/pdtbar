---
summary: "Smoke checks, proof commands, redaction rules, and live/scripted validation boundaries."
read_when:
  - Updating smoke tests or proof artifacts
  - Changing launch, login, fetch, or status-icon behavior
  - Preparing PR proof for UI/runtime changes
---

# Smoke Checks

## Current setup assumptions

- Product launch is no-argument `pdtbar`; fixture mode is explicit `--fixture`.
- Claude is the only setup/login path. PDTBar uses the existing signed-in Claude CLI user and the configured PDT MCP server.
- Scripted smokes use isolated app-support and snapshot directories. They may inject fixture env vars only as sentinels to prove the no-argument path does not enter fixture mode.
- Scripted login handoff fakes use `pdtbar --scripted-claude-login-bin <path>` from smoke/debug tooling only. Product Claude calls scrub inherited old `PDTBAR_CLAUDE_HANDOFF_*` env before using a configured Claude binary.
- Manual Claude reachability proof uses normal `claude -p`; `claude --bare` is refused because it does not prove the signed-in Claude CLI MCP setup.
- Live `mcporter` smoke is optional research/dev proof, not the product runtime path.
- Missing macOS Accessibility/Screen Recording permission, Claude CLI, sign-in, model access, or PDT MCP setup should skip with a setup-required detail unless the smoke is specifically testing that failure.

## Redaction rules

Public proof may report command names, selectors, row text, scenario status,
counts, durations, fixture names, and redacted status text. Do not write private
portfolio data, credentials, private endpoints, raw live payloads, account
identifiers, live holding names/values, or non-public model IDs into docs,
artifacts, PR bodies, or issue comments.

## Status-icon proof rule

The menu bar status slot always renders the Concentration Stack icon. The icon
fill is attention count capped at three filled bars; it is not freshness,
progress, or a separate notification dot. The center bar stays at max visual
height; side bars start from a deterministic silhouette (left half-height, right
two-thirds height) and X-ray look-through concentration scales only those side
bars. Freshness and fetch failure belong in tooltip/menu copy and may optionally
dim the whole icon.
Smoke proof should check the Codable `StatusVisualState`/surface state or
sanitized rendered SVG, not private screenshots or raw portfolio payloads.

Normal deterministic gate:

```bash
make check
swift build
swift run pdtbar-checks
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-login-handoff
swift run pdtbar-smoke scripted-setup-retry
swift run pdtbar-smoke scripted-pulse-mark-read
swift run pdtbar-smoke copy-holding-identifier-action
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
swift run pdtbar-smoke real-claude-flow-ax
# Optional once Tests/ exists; currently exits with "no tests found".
swift test
```

`make check` is bounded to local deterministic checks: script syntax, Swift
build, `pdtbar-checks`, and the sharded Swift test runner. Live Claude/PDT,
Keychain, 1Password, Accessibility, and packaged-app checks stay opt-in.

Expected handoff gate for changes that affect launch, setup, first fetch, menu
behavior, or UI proof:

```bash
make docs-list
make test
make check
swift build --product pdtbar
./Scripts/package_app.sh
swift run pdtbar-smoke app-bundle-packaging
swift run pdtbar-smoke packaged-onboarding --app PDTBar.app
```

Add optional live proof only when explicitly requested or when local deterministic
and packaged scripted proof cannot cover the change.

Scripted Claude PDT connector e2e:

```bash
swift run pdtbar-smoke scripted-pdt-connector
```

This uses no live Claude credentials. It drives the connector-backed
`PortfolioDataSource` path with live-shaped scripted MCP responses, checks all
required v1 PDT read tools are available, verifies only those tools are called,
and proves each required read tool is called exactly once for the coalesced
fetch. It also exercises progressive background detail refresh with one missing
optional price-history response, proving completed allocation/X-ray/income data
is preserved, a redacted diagnostic is stored, and a retry clears the degraded
state. The proof artifact reports selectors/counts/scenario status only; no raw
portfolio payloads, values, account identifiers, or live data are written.

Scripted Claude login handoff e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-login-handoff
```

This uses isolated app-support directories, a scripted fake Claude CLI, and no
live Claude credentials. It launches the logged-out menu, verifies the
fake Claude CLI is not called before the user-initiated `Log in with Claude`
menu action, then proves the explicit smoke/debug login binary invokes `claude
auth login`, shows `Signing in with Claude` while login is in flight, re-runs
readiness, renders `Fetching portfolio`, and starts the first fetch from
scripted PDT data. It fails if a successful handoff returns to the signed-out
setup menu. Failure renders `Claude login failed` with a retryable login action.
The proof artifact contains selector/click booleans, readiness probe counts,
snapshot status, and redacted state only; no credentials, account identifiers,
or raw portfolio payloads are written.

Scripted setup retry e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-setup-retry
```

This uses isolated app-support directories, scripted readiness files, and no
live Claude credentials. It verifies missing Claude login renders `Not
connected`, `Log in with Claude`, and `Check again`; missing PDT MCP renders
`Add the PDT MCP server to Claude` and `Check again`; and clicking
`Check again` reruns readiness once before the scripted first fetch. The proof
artifact contains selectors, probe counts, status booleans, and redacted
first-fetch state only.

Scripted Pulse mark-read proof:

```bash
swift run pdtbar-smoke scripted-pulse-mark-read
```

This uses isolated state and sanitized fixtures only. It exercises the
descriptor `Mark as read` action payload, persists the local fingerprint, proves
the same fingerprint is hidden across a cached reload, and proves changed
material data resurfaces as unread. Proof artifacts contain only fixture names,
selectors/status booleans, and redacted state.

Copy holding identifier action proof:

```bash
swift run pdtbar-smoke copy-holding-identifier-action
```

This uses descriptor/app-support action plumbing only. It verifies the holding
identifier copy action resolves to the expected sanitized identifier payload
without launching the app or touching the user's pasteboard; the smoke reads
back from an isolated named pasteboard.

Manual Claude `-p` PDT reachability smoke:

```bash
swift run pdtbar-smoke manual-claude-pdt --model opus
```

This optional local smoke uses the installed `claude` CLI with normal `-p`
mode plus an explicit `--allowedTools` list for the seven required PDT read tools
under the observed Desktop server name and renamed MCP server names, structured
output, and non-mutating tool discovery; a broad `--disallowedTools` denylist
for built-ins plus PDT mutate-tool prefixes on the configured Claude CLI MCP
server; verbose stream JSON telemetry; and schema-enforced structured output to
exercise the currently logged-in Claude user and Claude CLI PDT MCP setup.
It never passes `claude --bare`;
if `--bare` is supplied to the smoke, it refuses the run because bare mode does
not prove the signed-in Claude CLI setup. Use `--model <alias>` or
`PDTBAR_CLAUDE_MODEL=<alias>` when the local Claude default model is
unavailable; the current manual path defaults to the public `opus` alias. Pass
`--claude <path>` or `PDTBAR_CLAUDE_BIN=<path>` for this manual reachability smoke
only; product launch removes old scripted handoff env before honoring a
configured Claude binary.

Missing Claude CLI, sign-in, model access, or PDT MCP setup exits successfully
with `skipped` and setup-required detail. Passing proof writes
`pdtbar-manual-claude-pdt-proof.json` with only `-p` mode, `bareModeUsed=false`,
required/reported tool names, selector/count totals, duration, and redacted
status plus tool-result error counts. It must not contain raw Claude output,
account identifiers, endpoints, portfolio holdings, values, credentials, or raw
PDT payloads.

Scripted first-fetch e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-first-fetch
```

This uses isolated app-support directories and no live Claude credentials. It
seeds a scripted Claude-ready state plus scripted PDT MCP responses, launches the
no-argument app path, and verifies the first complete fetch writes
`latest-portfolio-snapshot.json` under isolated app state before the pulse
descriptor is considered publishable. It also launches a required-tool-missing
scenario and verifies no first snapshot or pulse is published. Proof artifacts
contain paths, selectors, status text, counts, and booleans only; no raw live
portfolio payloads, account identifiers, or secrets are written.

Scripted returning-launch e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-returning-launch
```

This uses isolated app-support directories and no live Claude credentials. It
seeds a previous complete local snapshot, launches the no-argument app path with
a delayed scripted refresh, and verifies the cached pulse stays visible while the
refresh is in progress. It then verifies complete refreshed data replaces the
snapshot and pulse only after the scripted fetch finishes. A second
transient-failure launch proves the previous snapshot stays in place and the
menu shows `Details fill failed` plus `Fill details again`. Proof artifacts contain
paths, selectors, status text, as-of dates, and booleans only.

Read-only live PDT pulse smoke:

```bash
npx -y mcporter list <pdt-server> --schema --json > /tmp/pdt-schema.json
PDTBAR_LIVE_PDT_SERVER=<pdt-server> PDTBAR_LIVE_PDT_SCHEMA_JSON=/tmp/pdt-schema.json swift run pdtbar-smoke live-pdt
```

Default behavior is a clean skip. The live smoke requires a configured/authenticated
mcporter PDT server via `--server <pdt-server>` or `PDTBAR_LIVE_PDT_SERVER`. When
`PDTBAR_LIVE_PDT_SCHEMA_JSON` is set, the gate first confirms the expected read
tools are present in the schema. It then calls only read tools through the live
`PortfolioDataSource`, runs the same `PressureRunner` path used by fixture e2e,
renders the pulse descriptor, and keeps the raw live snapshot in an unreported
temporary directory that is removed after the render check.

Missing server credentials or local PDT access must stay `skipped`, not failed,
so CI can run `swift run pdtbar-smoke live-pdt` without secrets. CI should treat
`status: "skipped"` as neutral and `status: "failed"` as red. Passing live proof
is sanitized: the reported artifact contains selector IDs/counts only, never raw
portfolio payloads, holding names, or values.

Live read calls default to a 60s timeout. Pass `--timeout <seconds>` to use a
shorter local or CI bound.

Local/release packaged-app smoke:

```bash
swift build --product pdtbar
./Scripts/package_app.sh
swift run pdtbar-smoke app-bundle-packaging
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
swift run pdtbar-smoke packaged-onboarding --app PDTBar.app --peekaboo /opt/homebrew/bin/peekaboo
swift run pdtbar-smoke packaged-app --app PDTBar.app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/quiet-packaged-snapshot
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/quiet-snapshot
```

The logged-out launch smoke starts the app with no arguments, seeds unusable
Claude state in an isolated app-support directory, injects fixture environment
variables as a guard, and verifies the app does not enter fixture mode. With macOS
Accessibility permission, it also opens the menu and verifies `Not connected`,
`Log in with Claude`, and `Quit PDTBar`. Without Accessibility, it reports a
clean `skipped` with the exact missing permission caveat after proving launch
liveness and fixture isolation.

The ready launch smoke uses the same no-argument app path with isolated scripted
Claude/PDT readiness and scripted PDT MCP responses. It verifies the existing
Claude/PDT-ready path skips the logged-out menu, completes the first fetch,
writes isolated first-fetch state, renders the first pulse, avoids fixture state,
and writes only selector/status proof under `.build/pdtbar-smoke-artifacts/`.
No live Claude credentials or portfolio payloads are used.

The app-bundle packaging smoke builds `PDTBar.app` through
`Scripts/package_app.sh`, verifies `Info.plist` bundle identifier/executable/
`LSUIElement` metadata, verifies the local code signature, launches the bundle
through LaunchServices with isolated app support, checks the running process
matches `Contents/MacOS/PDTBar`, and opens the setup menu-bar surface when
Accessibility is granted. Missing Accessibility exits successfully with
`skipped` after packaging, signing, and LaunchServices launch proof. Its JSON
artifact contains only bundle paths, signature posture, process metadata,
selectors, and redacted status text.

The packaged onboarding smoke is the first-run onboarding regression gate. It
requires a packaged `PDTBar.app`, launches the bundle executable with fresh
isolated app-support state and an explicit scripted login handoff option,
injects fixture env only as a sentinel, opens the setup menu through
Accessibility, clicks `Log in with Claude`, uses a scripted successful
`claude auth login`, and verifies readiness is rechecked
before the scripted first fetch starts. Missing Accessibility exits
successfully with `skipped` after proving packaged launch liveness and fixture
isolation. Proof artifacts contain app/support/sentinel paths, selectors, setup
and fetch status text, and booleans only.
Passing `--peekaboo` additionally captures sanitized real UI PNGs for setup,
login-opening, and post-readiness fetching states.

For UI PRs that need screenshot proof, follow the PR #68 convention: capture
real macOS PNG screenshots from packaged `PDTBar.app` using sanitized fixtures or
isolated scripted state, wrap PNG pixels in SVG only as a viewable container, verify
raw URLs with `curl -I -L`, and put the links in a PR comment. Do not use SVG as
the only proof when the reviewer needs to inspect real UI pixels.

Real Claude-flow Accessibility matrix smoke:

```bash
swift build --product pdtbar
swift run pdtbar-smoke real-claude-flow-ax
```

This launches the actual no-argument app path with isolated app-support
directories and scripted Claude/PDT dependencies. It opens the menu-bar item
through macOS Accessibility and verifies stable status/menu identifiers plus
visible text for setup, fetching, all-quiet, pressure, Data health, and retryable
fetch-error surfaces. Fixture env is injected only as a guard; the smoke fails if fixture
snapshot state is written. Missing macOS Accessibility permission exits
successfully with `skipped` and names that exact TCC permission. Proof artifacts
contain selectors, status text, scenario booleans, and redacted state only; no
Claude credentials or raw portfolio payloads are used.

This launches the fixture-mode app, routes it through an isolated snapshot
directory, verifies `latest-portfolio-snapshot.json` was written, and verifies
the app stays running. It does not need live PDT credentials.

Real-user pulse e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/concentration-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse-concentration
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/income-event.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse-income
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/big-mover.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse-big-mover
```

This launches the real fixture-mode app, opens the menu-bar pulse through
macOS Accessibility, and verifies fixture status plus pulse, allocation, income,
big-mover, and freshness rows using the descriptor's stable accessibility
identifiers. Fixtures with a prior snapshot, such as `big-mover.json`, seed that
prior into an isolated smoke snapshot directory before launch; cold-start and
seeded-prior runs do not read or write the user's real app state. If macOS
Accessibility permission is missing, it exits successfully with `skipped` and
reports that exact TCC permission to grant.

Peekaboo-only local UI proof:

```bash
swift run pdtbar-smoke peekaboo --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/peekaboo-snapshot
```

The Peekaboo smoke checks CLI availability and TCC permissions first. If Screen
Recording or Accessibility is missing, it exits successfully with `skipped` and
reports the missing permissions. When permissions are granted, it inspects the
fixture-mode menu-bar item for expected fixture text and writes a screenshot
artifact under `.build/pdtbar-smoke-artifacts/`.

Fixture-rendered proof, usable when TCC blocks macOS UI capture:

```bash
swift run pdtbar-smoke fixture-proof --fixture docs/pdt/fixtures/quiet-no-pressure.json
```

Menu polish proof for PR review:

```bash
swift run pdtbar-smoke menu-polish-proof --output docs/smoke/menu-polish-proof.svg
```

This renders sanitized setup, fetching, all-quiet, pressure, and retryable-error
menu cards from the same descriptors used by the app and AX smoke. It contains
only fixture/scripted copy and no live portfolio payloads.
