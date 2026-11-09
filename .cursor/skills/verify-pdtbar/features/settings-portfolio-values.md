# Settings and portfolio values

`Settings...` (`pdtbar.row.actions.settings`) dismisses the menu and opens the Settings window. `Show portfolio values` is stored in `UserDefaults` under `showPortfolioValues`. Turning it off masks money values in the menu, including detail rows, and re-renders the open menu.

Proof that it works: after toggling `Show portfolio values` off, the reopened menu shows masked values and no raw amounts. Turning it back on restores them. The setting persists in the run's isolated defaults suite.

## Sub-features

- Opening Settings from the menu, which closes the menu first.
- The `Show portfolio values` toggle.
- Masking in summary, allocation, and detail rows.

## How to get to it (user POV)

Click the menu bar icon, choose `Settings...`, and switch `Show portfolio values`.

## Driving it with pdtbar-smoke

The flow is opt-in only, because it captures the screen:

```bash
RUN=$(Scripts/verify_pdtbar.sh launch | sed -n 's/^ready: //p')   # run dir; evidence lands in $RUN/evidence
swift run pdtbar-smoke portfolio-values-settings-proof --artifacts "$RUN/evidence" --snapshot-dir "$RUN/settings-snapshot"
Scripts/verify_pdtbar.sh stop "$RUN"
```

It writes `pdtbar-portfolio-values-settings-proof.json` and PNGs.

Without screen capture, the masking contract is covered by `swift test` (`Tests/PDTBarTests/PortfolioValueVisibilityTests.swift`). That is not a user-path proof.

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. `capture` frames only the status item and menu, never the Settings window, and it cannot flip the toggle. Use it for the default, unmasked menu. Masked-state pixels still come from `portfolio-values-settings-proof`.

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh capture screenshot "$RUN" values-shown
Scripts/verify_pdtbar.sh stop "$RUN"
```

The image must show the open menu with fixture money values visible, such as `Total portfolio value`.

## Gotchas

- There is no prompt-free user-path journey. The scenario needs AX to click the toggle, and it always calls `/usr/sbin/screencapture`. With Screen Recording missing or needing re-confirmation, macOS can show a dialog. Run it only when the user asked and is present.
- Always run with `PDTBAR_USER_DEFAULTS_SUITE` isolated. The smoke and `verify_pdtbar.sh` both set it. A bare launch would flip the user's real setting.
