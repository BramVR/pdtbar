# First fetch and pulse

The user signs in to Claude and configures the PDT MCP server, then launches PDTBar with no arguments. The app shows `Fetching portfolio`, reads the 7 required PDT read tools once, writes a local snapshot, and renders the pulse menu.

Proof that it works: `<app-support>/pdtbar/state/latest-portfolio-snapshot.json` is written in isolated state with open holdings and as-of `2026-03-29`. The app stays running. With AX granted, the opened menu contains the pulse identifiers (`pdtbar.section.pulse`, `pdtbar.row.pulse.status`). A scenario with a required tool missing writes no snapshot and shows the fetch-failed setup menu.

## Sub-features

- Cold first fetch, with the snapshot published only after a complete fetch.
- Missing required read tool (`pdt-list-dividends`), which blocks publication.
- Returning launch, where the cached pulse stays visible during refresh and is replaced only on success.
- Progressive background detail fill (`Filling details`, `Step 1/6: Base holdings`), plus `Details fill failed` / `Fill details again`.

## How to get to it (user POV)

Launch PDTBar, wait for the status icon to stop showing fetch progress, then click the menu bar icon. The pulse sits at the top of the menu.

## Driving it with pdtbar-smoke

```bash
swift build --product pdtbar
RUN=$(Scripts/verify_pdtbar.sh launch | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh doctor "$RUN"
swift run pdtbar-smoke scripted-first-fetch --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
Scripts/verify_pdtbar.sh stop "$RUN"
```

Read `$RUN/evidence/pdtbar-scripted-first-fetch-proof.json`. Pass requires `snapshotWritten: true`, `openHoldingCount > 0`, and `missingRequiredToolBlockedPublication: true`. When `accessibilityChecked: true`, it also requires `successPulseVisibleThroughAccessibility` and `failureVisibleThroughAccessibility`, with the identifiers in `pdtbar-scripted-first-fetch-{success,failure}-ax.json`.

Related prompt-free scenarios: `ready-launch` (the same path, with the logged-out menu skipped) and `scripted-pdt-connector` (connector only, with no app; it proves each required tool is called exactly once and that degraded detail refresh can be retried).

## Gotchas

- The smoke scripts PDT at the production MCP connector boundary (`scripted-pdt-mcp.json`). It does not prove live PDT reachability. That is `live-pdt` or `manual-claude-pdt`, both opt-in, and live PDT is never driven without the user.
- `scripted-returning-launch` falls back to a full-screen `screencapture` when AX is granted. Treat it as opt-in.
- The failure scenario sleeps for the full `--timeout` (default 2s) before it checks that nothing was published. That pause is expected, not a hang.
- With AX granted, the smoke visibly opens and closes the real menu on the current display.
