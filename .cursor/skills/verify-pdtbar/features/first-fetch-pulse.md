# First fetch and pulse

The user is connected to PDT (browser sign-in or pasted token) and launches PDTBar. The app checks the connection, shows `Fetching portfolio`, reads holdings from the PDT REST API, writes a local snapshot, renders the pulse menu, and then fills details in the background.

Proof that it works: `<app-support>/pdtbar/state/latest-portfolio-snapshot.json` is written in isolated state with open holdings and as-of `2026-06-22`. The app stays running and the fixture sentinel stays empty. With AX granted, the opened menu contains the pulse identifiers (`pdtbar.section.pulse`, `pdtbar.row.pulse.status`). A scenario whose required holdings request fails writes no snapshot and shows `Could not fetch portfolio` with `Try again`.

## Sub-features

- Cold first fetch, with the snapshot published only after a complete fetch.
- A failed required holdings request (503 after every retry), which blocks publication.
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

Read `$RUN/evidence/pdtbar-scripted-first-fetch-proof.json`. Pass requires `successSnapshotWritten: true`, `successSnapshotAsOf: 2026-06-22`, `successOpenHoldingCount > 0`, `failureSnapshotWritten: false`, `failureReported: true`, and for both launches `processStillRunning: true` and `fixtureSentinelEmpty: true`. When `accessibilityChecked: true`, `successPulseMenu.visible` and `failureMenu.visible` must be true, with the identifiers in `pdtbar-scripted-first-fetch-{success,failure}-ax.json`.

Related prompt-free scenarios: `ready-launch` (a connected browser session straight to the pulse) and `scripted-returning-launch` (a seeded snapshot stays visible during the background refresh and survives a failed one).

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. The smokes launch their own app, so capture a fixture run that shows the end state of a first fetch. Take a screenshot. The pulse is static.

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh capture screenshot "$RUN" pulse-menu
Scripts/verify_pdtbar.sh stop "$RUN"
```

The image must show the status item and the open menu with `Pulse` at the top and the attention rows under it. It shows the fixture pulse, not a scripted first fetch. Label it that way.

## Gotchas

- The smoke scripts PDT at the app's connection boundary (`--scripted-pdt`). It does not prove live PDT reachability, and live PDT is never driven without the user.
- `scripted-returning-launch` falls back to a full-screen `screencapture` when AX is granted. Treat it as opt-in.
- After a successful first fetch the app starts a background detail refresh, which also requests holdings. The success launch scripts only one reply, so that refresh fails and logs `background refresh failed`; the pulse stays.
- With AX granted, the smoke visibly opens and closes the real menu on the current display.
