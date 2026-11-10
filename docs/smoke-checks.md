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
- The PDT REST API connection is the only setup path: Sign in with PDT (browser) or a pasted PDT token, stored in the Keychain. Product code starts no process; `pdtbar-checks` fails on a process start, or a mention of a local CLI or MCP tool, in `Sources/PDTBarCore`, `Sources/PDTBarAppSupport`, or `Sources/PDTBarApp`.
- Scripted app smokes launch `pdtbar --app-support-dir <isolated> --scripted-pdt <file>`. The file is a `ScriptedPDTConnection` JSON: stored connection (`notConnected`, `browserSession`, `personalToken`, `signInExpired`, `tokenRevoked`), an optional `keychainStatus` that drives the real Keychain store over a fake `SecItem` API, a scripted sign-in outcome, PDT API replies in request order, and an `eventLog` that records `check`, `sign-in`, `token`, `disconnect`, and `request <path>`. The app refuses `--scripted-pdt` without `--app-support-dir`.
- Scripted smokes inject fixture env vars only as sentinels; they fail if the fixture sentinel is written.
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
make smoke-api
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
build, `pdtbar-checks`, and the sharded Swift test runner. It does not run
`make smoke-api`. The checks executable keeps command-style proof: the scenario
fixture corpus, REST fixture provenance (below), the coalesced API first fetch,
a degraded-then-repaired API background refresh, PDT API Data health over an
in-memory script (a saved copy is never healthy, last sync stays apart from
price freshness after a failed refresh, and copied diagnostics hold nothing a
`429` answer carried), and the product source scan above. Swift tests own core
model, parser, runner, normalization, and rendering regressions. Non-AX
scripted smokes can be run directly with `swift run pdtbar-smoke <name>` when
launch/setup/menu behavior is in scope. Live PDT, Keychain, 1Password, and
packaged-app checks stay opt-in.

REST fixture provenance: `docs/pdt/fixtures/api/provenance.json` says the
bodies are synthetic, holds no account data, names the PDT API docs version
they were written against (v0.8.1) and the spec version they were not
re-checked against (openapi v0.9.0), and lists the fields still assumed rather
than seen live. Per scenario directory it lists every reply file in replay
order with the `GET /v1/...` request it answers. `pdtbar-checks` fails when the
scenario keys differ from the directories, a file list differs from the
directory's `*.json` files, a request is not a `GET /v1/` request, the version
is empty, or `synthetic` is false. It lives at the `api/` root because the
replay loaders read every `*.json` in a scenario directory.

Scripted API smoke matrix:

```bash
make smoke-api   # ./Scripts/api_smoke_matrix.sh [<artifacts-dir>]
```

`Scripts/api_smoke_matrix.sh` builds `pdtbar` and `pdtbar-smoke`, then runs
`pdtbar-smoke scripted-api-matrix --app .build/debug/pdtbar --timeout 5` under
`env -i` (`HOME` and `TMPDIR` in a throwaway directory, `PATH=/usr/bin:/bin`)
and `sandbox-exec` with the profile written in the script. CI runs it after
the deterministic checks.

The matrix runs five rows in its own process, each with `--no-menu-checks`:
`scripted-api-client`, `scripted-api-snapshot`, `scripted-api-auth`,
`scripted-first-fetch`, and `scripted-returning-launch`. They use the scripted
HTTP transport, in-memory or fake-`SecItem` credential stores, and the
synthetic REST fixtures; the last two launch the real app with
`--scripted-pdt`, and the app inherits the sandbox. Each row also runs on its
own, as described below. The registry in `Sources/PDTBarSmoke/main.swift`
marks which commands are matrix rows.

Row zero checks the environment first. No `PATH` entry may hold a file named
`claude`, `codex`, or `mcporter` (an existence check: an execute check would
trip the exec rule), and every sandbox rule below must hold. Otherwise the
matrix fails and runs no row. A failed or `skipped` row fails the matrix.
`<artifacts>/pdtbar-scripted-api-matrix-proof.json` (default
`.build/pdtbar-smoke-artifacts/api-matrix/`) records the `PATH`, any resolved
CLI, each rule's expected and observed outcome, every row report, and
`menuChecks: "menu: not checked (TCC unreachable by design)"`. Each row writes
its own proof under `<artifacts>/<row>/`.

Each rule is probed from inside the sandbox. Fatal rules run in a child
`pdtbar-smoke sandbox-probe <connect|resolve|mach <service>|exec <path>>`, so a
rule that holds kills the child and leaves the matrix running. The TCC rule and
the control lookup run in-process first; outside the sandbox they come back
allowed and no child probe runs, so the network probe never sends a packet.

- **Network.** `(deny network-outbound (with send-signal SIGKILL) (remote ip))`.
  Probe: a non-blocking connect to `192.0.2.1:443` (TEST-NET-1) is killed by
  SIGKILL. Control: with the deny but no SIGKILL, the connect fails with
  errno 1 and no packet leaves.
- **Loopback.** `(allow network-outbound (remote ip "localhost:*"))`, after the
  deny because the last matching rule wins. Only `scripted-api-auth` uses it:
  its token exchange calls its own listener, and the row asserts the callback
  host is `127.0.0.1`. Control: without the allow, the matrix is killed by
  SIGKILL in `scripted-api-auth`, while the other four rows pass on their own
  under that profile. The claim is no non-loopback network and no account
  access, not zero sockets.
- **DNS.** `(deny network-outbound (with send-signal SIGKILL) (remote unix-socket (path-literal "/private/var/run/mDNSResponder")))`.
  Probe: `getaddrinfo("localhost")` is killed by SIGKILL. Control: outside the
  sandbox it returns 0, and with the deny but no SIGKILL it still returns 0
  (the resolver answers `localhost` without mDNSResponder), so the SIGKILL is
  what makes this rule observable.
- **Exec.** `(deny process-exec (with send-signal SIGKILL) (regex #"/(claude|codex|mcporter)$"))`.
  Probe: `execv` of a `#!/bin/sh` script named `claude`, `codex`, or `mcporter`
  is killed by SIGKILL; the same script named `claudette` exits 0. Control:
  outside the sandbox each runs and exits 0; with the deny but no SIGKILL,
  `execv` fails with errno 1. The probe calls `execv` in the child because a
  denied `posix_spawn` kills the spawner.
- **Keychain.** `(deny mach-lookup (with send-signal SIGKILL) (global-name-regex #"^com\.apple\.(SecurityServer|securityd\.)"))`.
  Probe: looking up `com.apple.SecurityServer` or `com.apple.securityd.xpc` is
  killed by SIGKILL. Control: outside the sandbox both lookups return 0 (a
  lookup reads no item and shows no prompt); with the deny but no SIGKILL they
  return 1100. The launch rows pass under this rule, so the app reaches no
  Keychain daemon.
- **TCC.** `(deny mach-lookup (global-name-regex #"^com\.apple\.tccd"))`, with no
  SIGKILL. Probe: the in-process `com.apple.tccd` lookup returns 1100, while a
  `com.apple.cfprefsd.daemon` lookup still returns 0. With SIGKILL, the
  launched app is killed before its first fetch. No TCC prompt is reachable,
  and the rows pass `--no-menu-checks`, so the menu is not checked; that is
  recorded, not counted as a skip.
- **PATH.** Not a sandbox rule: `env -i` sets `PATH=/usr/bin:/bin`. Control: a
  fake `claude` first on `PATH` fails row zero (`claude` resolved, rules 10/10)
  and no row runs.

Whole-matrix controls: without `sandbox-exec`, row zero reports 1 of 10 rules
enforced (only the control lookup) and no row runs. With every SIGKILL removed
from the profile, it reports 3 of 10 (TCC and the two controls) and no row runs.

Dropped: the fake `claude` and `mcporter` that app-launch smokes used to put
first on `PATH` (and their `cli-spawned.log`). They caught only a `PATH` lookup
of two names; the exec rule catches any path for all three, row zero checks
`PATH`, and `pdtbar-checks` scans product sources. The manual Claude
(`manual-claude-pdt`), live mcporter (`live-pdt`), and MCP connector
(`scripted-pdt-connector`) smokes were deleted with the Claude/MCP path (#250).

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

It then runs six failed background refreshes in-process, each over a store that
holds a saved copy: `401 TOKEN_INVALID`, `403 INSUFFICIENT_SCOPE`,
`403 API_ACCESS_PAUSED`, `429` with `Retry-After: 120`, `503`, and an
undecodable `200`. Every answer carries a planted token, account id, URL, and
body text. `failedSyncs` in the proof records, per answer, the stored
`PDTSyncFailure`, the Data health Diagnostics detail, the copied diagnostics
text, and the saved copy's last sync. The smoke fails unless each refresh
stores the expected failure kind, the Diagnostics detail says what to do, the
saved copy and its last sync are unchanged and not healthy, and no planted
value appears in the stored failure, the Data health JSON, any Data health row,
the copied text, or the proof.

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
portfolio` and `Try again`. Both launches fail if the fixture sentinel is
written. Proof artifacts contain paths,
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
avoids fixture state, and writes only selector/status proof
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
