---
summary: "Smoke checks, proof commands, redaction rules, and live/scripted validation boundaries."
read_when:
  - Updating smoke tests or proof artifacts
  - Changing launch, PDT connection, fetch, or status-icon behavior
  - Preparing PR proof for UI/runtime changes
---

# Smoke Checks

## Current setup assumptions

- Product launch is no-argument `pdtbar`; fixture mode is explicit `--fixture`.
- The PDT REST API connection is the only setup path: Sign in with PDT (browser) or a pasted PDT token, stored in the Keychain. Launch and the menu never run the Claude CLI or an MCP server.
- Scripted app smokes launch `pdtbar --app-support-dir <isolated> --scripted-pdt <file>`. The file is a `ScriptedPDTConnection` JSON: stored connection (`notConnected`, `browserSession`, `personalToken`, `signInExpired`, `tokenRevoked`), an optional `keychainStatus` that drives the real Keychain store over a fake `SecItem` API, a scripted sign-in outcome, PDT API replies in request order, and an `eventLog` that records `check`, `sign-in`, `token`, `disconnect`, and `request <path>`. The app refuses `--scripted-pdt` without `--app-support-dir`.
- Scripted smokes inject fixture env vars only as sentinels and put a fake `claude` and `mcporter` first on `PATH`; they fail if the fixture sentinel is written or either fake runs.
- Manual Claude reachability proof (`manual-claude-pdt`) and live `mcporter` smoke (`live-pdt`) exercise the legacy MCP path only (#250 removes it); neither is the product runtime path.
- Missing macOS Accessibility/Screen Recording permission should skip with a setup-required detail unless the smoke is specifically testing that failure.

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
bars. Data freshness and fetch failure belong in tooltip/menu copy and may optionally
dim the whole icon.
Smoke proof should check the Codable `StatusVisualState`/surface state or
sanitized rendered SVG, not private screenshots or raw portfolio payloads.

Normal deterministic gate:

```bash
make check
swift build
swift test
swift run pdtbar-checks
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-api-client
swift run pdtbar-smoke scripted-api-snapshot
swift run pdtbar-smoke scripted-api-auth
swift run pdtbar-smoke scripted-sign-in
swift run pdtbar-smoke scripted-setup-retry
swift run pdtbar-smoke scripted-pulse-mark-read
swift run pdtbar-smoke copy-holding-identifier-action
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
```

`make check` is bounded to local deterministic checks: script syntax, Swift
build, `pdtbar-checks`, and the sharded Swift test runner. The checks executable
keeps command-style fixture/connector and tooling-contract proof; Swift tests
own core model, parser, runner, normalization, and rendering regressions. Non-AX
scripted smokes can be run directly with `swift run pdtbar-smoke <name>` when
launch/setup/menu behavior is in scope. Live Claude/PDT, Keychain, 1Password,
and packaged-app checks stay opt-in.

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

Scripted PDT API client:

```bash
swift run pdtbar-smoke scripted-api-client
```

This uses no network, no real credentials, and no Keychain. It drives
`PDTAPIClient` through `ScriptedPDTHTTPTransport` with a fake in-memory token and proves GET-only
requests to the PDT API origin, page and offset pagination, a 429 retry, a typed
expired-token error, and a proof file without the token.

Scripted PDT REST snapshot:

```bash
swift run pdtbar-smoke scripted-api-snapshot
```

This uses no network, no real credentials, and no Keychain. It replays
`docs/pdt/fixtures/api/full/` through `PDTAPIDataSource` and writes
`pdtbar-scripted-api-snapshot-proof.json` with the request paths, GET-only and
PDT-origin checks, per-facet counts, and the degraded flag. It fails if any facet
degrades or the fake token appears in the proof.

Scripted PDT sign-in:

```bash
swift run pdtbar-smoke scripted-api-auth
```

This uses no network, no real credentials, and no Keychain. It runs
`PDTBrowserSignIn` against a real loopback listener on a free port with a fake
browser and a scripted token endpoint, then drives `PDTConnection` over an
in-memory store: 6 concurrent reads after expiry share one refresh,
`invalid_grant` moves to needs-reconnect, a pasted token reads, and disconnect
clears the store. `pdtbar-scripted-api-auth-proof.json` holds request counts and
checks only; the smoke fails if any scripted code or token appears in it.

Live PDT sign-in (opt-in, needs Bram's PDT account and a browser):

```bash
swift run pdtbar-dev pdt-sign-in --store <file>   # add --no-browser to print the URL instead of opening it
swift run pdtbar-dev pdt-status --store <file>
swift run pdtbar-dev pdt-refresh --store <file>
swift run pdtbar-dev pdt-disconnect --store <file>
```

Live app over that store (opt-in, live PDT reads; never in the default gate):

```bash
swift build --product pdtbar
.build/debug/pdtbar --app-support-dir .build/live/<run>/app-support --pdt-credential-file <file>
```

`--pdt-credential-file` runs the product path (connection check, first fetch,
background refresh) over the dev file store instead of the Keychain, which an
ad-hoc dev build cannot use. It requires an isolated `--app-support-dir`, and
the snapshot it writes holds real portfolio data: keep it under `.build/`, never
in proof. Report counts, statuses, and outcomes only.

These use the registered "pdtbar" app, port 47245, and a mode-0600 file store at
the given path (plus a sibling `<name>.lock`), never the Keychain. Output is states, expiry, HTTP statuses,
`/v1/me` key names, and token SHA-256 fingerprints; never token values. Delete
the store file after proof and revoke the grant in PDT's connected apps page.

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

Scripted PDT sign-in e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-sign-in
```

This uses isolated app-support directories and the scripted PDT connection; no
browser, Keychain, or network. A not-connected launch must stay idle (one
`check`, no `sign-in`, no request) until the user clicks `Sign in with PDT`.
With Accessibility it clicks that row, sees `Signing in with PDT`, and waits for
the scripted success to reach the first fetch and write the snapshot. A second
launch scripts a declined sign-in and verifies `Sign-in failed` with no fetch.
Without Accessibility it proves the idle launch and returns `skipped`. The proof
artifact contains event counts, click attempts, status booleans, and AX
selectors only.

Scripted setup retry e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-setup-retry
```

This uses isolated app-support directories and the scripted PDT connection. It
launches three connection problems: a revoked token (`Reconnect to PDT`), a
subscription paused on the holdings request (`403 API_ACCESS_PAUSED`, then `200`
after `Check again`), and a Keychain that answers `-34018` (`Keychain
unavailable`). Each launch must run exactly one `check` and write no snapshot.
With Accessibility it verifies each row set, clicks `Check again` twice in a
row, and requires exactly two `check` lines: the paused launch reaches the
fetch (holdings requests: the 403, the first fetch, and the background refresh
that follows it), and the duplicate click starts no second fetch. The proof
artifact contains event counts, click attempts, and AX selectors only.

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

Portfolio summary real-menu proof:

```bash
swift build --product pdtbar
swift run pdtbar-smoke portfolio-summary-proof --peekaboo /opt/homebrew/bin/peekaboo
```

This launches freshly built fixture-mode PDTBar with isolated state, opens the
actual menu through Accessibility, verifies the Summary selectors precede the
portfolio overview, and requires a visible PNG screenshot. Fixture values are
synthetic; no live portfolio values enter the artifact. Missing Accessibility,
Screen Recording, or Peekaboo permission is reported instead of substituting a
generated image. PDTBar's supported macOS menu is fixed-width and has no
orientation-specific presentation. For a supported whole-UI larger-scale proof,
select **System Settings → Displays → Larger Text**, run the same command, then
restore the prior display setting. The AX evidence records the active logical and
pixel display dimensions. Layout tests also cover narrower widths and larger
system-font metrics while preserving the two-column grid.

Manual Claude `-p` PDT reachability smoke:

```bash
swift run pdtbar-smoke manual-claude-pdt --model opus
```

This optional local smoke uses the installed `claude` CLI with normal `-p`
mode plus an explicit `--allowedTools` list for the seven required PDT read tools
under the observed Desktop server name and renamed MCP server names, structured
output, and non-mutating tool discovery; a broad `--disallowedTools` denylist
for built-ins plus PDT mutate-tool prefixes on the configured Claude CLI MCP
server (`ClaudePDTReadOnlyToolPolicy` in PDTBarCore — the same shared denylist
the legacy `ClaudeLocalConnection` sends); verbose stream JSON telemetry; and
schema-enforced structured output to
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

This uses isolated app-support directories and the scripted PDT connection with
a stored personal token. The success launch answers the holdings request from
`docs/pdt/fixtures/api/full/01-holdings.json` and verifies the first fetch writes
`latest-portfolio-snapshot.json` (as-of `2026-06-22`) under isolated app state
and, with Accessibility, shows the pulse. The failure launch answers every
holdings attempt with `503` and verifies no snapshot is written, the app reports
the failed first fetch, and, with Accessibility, the menu shows `Could not fetch
portfolio` and `Try again`. Both launches fail if the fake `claude`/`mcporter`
runs or the fixture sentinel is written. Proof artifacts contain paths,
selectors, status text, counts, and booleans only.

Scripted returning-launch e2e:

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-returning-launch
```

This uses isolated app-support directories and the scripted PDT connection with
a stored browser session. It seeds a previous complete local snapshot, launches
the app with a delayed scripted PDT REST refresh (the
`docs/pdt/fixtures/api/full` replies, served through the script's `api` to
`PDTAPIBackgroundDetailRefresh`), and verifies the cached pulse stays visible while the
refresh is in progress. It then verifies complete refreshed data replaces the
snapshot and pulse only after the scripted fetch finishes. A second launch
whose holdings requests all answer `503` proves the previous snapshot stays in place and the
menu shows `Details fill failed` plus `Fill details again`. Proof artifacts contain
paths, selectors, status text, as-of dates, and booleans only.

Read-only live PDT pulse smoke:

```bash
npm ci
./node_modules/.bin/mcporter list <pdt-server> --schema --json > /tmp/pdt-schema.json
PDTBAR_LIVE_PDT_SERVER=<pdt-server> PDTBAR_LIVE_PDT_SCHEMA_JSON=/tmp/pdt-schema.json swift run pdtbar-smoke live-pdt
```

Default behavior is a clean skip. The live smoke requires a configured/authenticated
mcporter PDT server via `--server <pdt-server>` or `PDTBAR_LIVE_PDT_SERVER`, plus
the pinned repo-local `./node_modules/.bin/mcporter` installed from
`package-lock.json`. Run `npm ci` after checkout or lockfile changes. To use a
manually audited local binary instead, pass `--mcporter <path>` or
`PDTBAR_MCPORTER_BIN=<path>`; unversioned `npx mcporter` is not accepted for the
live smoke. Missing or mismatched pinned mcporter setup fails once a server is
explicitly configured, with an actionable `npm ci` setup message. When
`PDTBAR_LIVE_PDT_SCHEMA_JSON` is set, the gate first confirms the expected read
tools are present in the schema. It then calls only read tools through the live
`PortfolioDataSource`, runs the same `PressureRunner` path used by fixture e2e,
renders the pulse descriptor, and keeps the raw live snapshot in an unreported
temporary directory that is removed after the render check.

Missing server credentials or local PDT access must stay `skipped`, not failed,
so local runs can distinguish environment gaps from regressions. Passing live
proof is sanitized: the reported artifact contains selector IDs/counts only,
never raw portfolio payloads, holding names, or values.

Live read calls default to a 60s timeout. Pass `--timeout <seconds>` to use a
shorter local bound.

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

The logged-out launch smoke starts the app with a scripted not-connected PDT
connection, injects fixture environment variables as a guard, and verifies the
app stays running, checks once, fetches nothing, and does not enter fixture
mode. With macOS Accessibility permission, it also opens the menu and verifies
`Not connected`, `Sign in with PDT`, `Use a PDT token…`, and `Quit PDTBar`.
Without Accessibility, it reports a clean `skipped` with the exact missing
permission caveat after proving launch liveness and isolation.

The ready launch smoke starts the app with a scripted browser session and a
scripted holdings reply. It verifies the connected path skips setup, completes
the first fetch, writes isolated first-fetch state, renders the first pulse,
avoids fixture state and the fake CLIs, and writes only selector/status proof
under `.build/pdtbar-smoke-artifacts/`.

The app-bundle packaging smoke builds `PDTBar.app` through
`Scripts/package_app.sh`, verifies `Info.plist` bundle identifier/executable/
`LSUIElement` metadata, verifies the local code signature, launches the bundle
through LaunchServices with isolated app support and a scripted not-connected
PDT connection (`--scripted-pdt`), checks the running process
matches `Contents/MacOS/PDTBar`, and opens the setup menu-bar surface when
Accessibility is granted. Missing Accessibility exits successfully with
`skipped` after packaging, signing, and LaunchServices launch proof. Its JSON
artifact contains only bundle paths, signature posture, process metadata,
selectors, and redacted status text.

The packaged onboarding smoke is the first-run onboarding regression gate. It
requires a packaged `PDTBar.app`, launches the bundle executable with fresh
isolated app-support state and a scripted not-connected PDT connection whose
sign-in succeeds, injects fixture env only as a sentinel, opens the setup menu
through Accessibility, clicks `Sign in with PDT`, sees `Signing in with PDT`,
and verifies the scripted first fetch writes the snapshot. Missing
Accessibility exits successfully with `skipped` after proving packaged launch
liveness, an idle connection, and isolation. Proof artifacts contain
app/support/sentinel paths, selectors, status text, and booleans only.
Passing `--peekaboo` additionally captures a sanitized full-screen PNG while
signing in.

For UI PRs that need screenshot proof, follow the PR #68 convention: capture
real macOS PNG screenshots from packaged `PDTBar.app` using sanitized fixtures or
isolated scripted state, wrap PNG pixels in SVG only as a viewable container, verify
raw URLs with `curl -I -L`, and put the links in a PR comment. Do not use SVG as
the only proof when the reviewer needs to inspect real UI pixels.

The packaged-app smoke launches the fixture-mode app, routes it through an isolated snapshot
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
big-mover, and data rows using the descriptor's stable accessibility
identifiers. Fixtures with a prior snapshot, such as `big-mover.json`, seed that
prior into an isolated smoke snapshot directory before launch; cold-start and
seeded-prior runs do not read or write the user's real app state. If macOS
Accessibility permission is missing, it exits successfully with `skipped` and
reports that exact TCC permission to grant.
When `--peekaboo` is available, successful runs also capture real menu PNGs for
the main pulse plus allocation, attention, Data/Prices, and Data health
drill-downs when those submenus are present.

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
menu cards from the same descriptors used by the app and AX smoke, including the
quiet Data/Prices overview row. It contains only fixture/scripted copy and no
live portfolio payloads.
