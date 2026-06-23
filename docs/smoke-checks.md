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

Default behavior is a clean skip. The live smoke checks required PDT read-tool
availability from schema JSON and runs sanitized fixture normalization checks.
It must not assert private portfolio values or print private PDT payloads.

Local/release packaged-app smoke:

```bash
swift build --product pdtbar
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json
```

This launches the fixture-mode app and verifies it stays running. It does not
need live PDT credentials.

Peekaboo-only local UI proof:

```bash
swift run pdtbar-smoke peekaboo --fixture docs/pdt/fixtures/quiet-no-pressure.json
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
