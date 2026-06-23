# Smoke Checks

Normal deterministic gate:

```bash
swift build
swift run pdtbar-checks
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-first-fetch
# Optional once Tests/ exists; currently exits with "no tests found".
swift test
```

Scripted Claude PDT connector e2e:

```bash
swift run pdtbar-smoke scripted-pdt-connector
```

This uses no live Claude credentials. It drives the connector-backed
`PortfolioDataSource` path with live-shaped scripted MCP responses, checks all
required v1 PDT read tools are available, verifies only those tools are called,
and proves each required read tool is called exactly once for the coalesced
fetch. The proof artifact reports selectors/counts/scenario status only; no raw
portfolio payloads, values, account identifiers, or live data are written.

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
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
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
