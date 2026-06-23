# Smoke Checks

Normal deterministic gate:

```bash
swift build
swift run pdtbar-checks
# Optional once Tests/ exists; currently exits with "no tests found".
swift test
```

Opt-in live PDT contract smoke:

```bash
npx -y mcporter list <pdt-server> --schema --json > /tmp/pdt-schema.json
PDTBAR_LIVE_PDT_SMOKE=1 PDTBAR_LIVE_PDT_SCHEMA_JSON=/tmp/pdt-schema.json swift run pdtbar-smoke live-pdt
```

Default behavior is a clean skip. The live smoke check requires PDT read-tool
availability from schema JSON and runs sanitized fixture normalization checks.
It must not assert private portfolio values or print private PDT payloads.

Local/release packaged-app smoke:

```bash
swift build --product pdtbar
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/quiet-snapshot
```

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
