# Settings and portfolio values

`Settings...` (`pdtbar.row.actions.settings`) dismisses the menu and opens the Settings window. `Show portfolio values` is stored in `UserDefaults` under `showPortfolioValues`. Turning it off masks money values in the menu, including detail rows, and re-renders the open menu.

Proof that it works: after toggling `Show portfolio values` off, the reopened menu shows `######` and no raw amounts. Hiding survives a relaunch. Turning it back on restores the amounts, and toggling never rewrites the snapshot. The setting persists in the smoke's own throwaway defaults suite (`pdtbar-smoke-<uuid>`).

## Sub-features

- Opening Settings from the menu, which closes the menu first.
- The `Show portfolio values` toggle.
- Masking in summary, allocation, detail rows, the `Prices` submenu (the price hides, its date stays), and the cash drag in Pulse.

## How to get to it (user POV)

Click the menu bar icon, choose `Settings...`, and switch `Show portfolio values`.

## Driving it with pdtbar-smoke

The flow is opt-in only, because it captures the screen. It launches its own app twice, so no `verify_pdtbar.sh launch` is needed:

```bash
swift build --product pdtbar
OUT=.build/verify-pdtbar/settings-$(date +%Y%m%d-%H%M%S)
swift run pdtbar-smoke portfolio-values-settings-proof --artifacts "$OUT/evidence" --snapshot-dir "$OUT/settings-snapshot"
```

It writes `pdtbar-portfolio-values-settings-proof.json` (`visibleSensitiveTexts`, `hiddenTexts`, `relaunchHiddenTexts`, `restoredTexts`, `snapshotUnchangedOnToggle`) and PNGs: a crop around the toggle through Peekaboo (`--peekaboo`, default `/opt/homebrew/bin/peekaboo`) and the masked menu through `/usr/sbin/screencapture`.

The masking rules, without the window or the click, are prompt-free from the descriptor:

```bash
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/concentration-pressure.json --portfolio-values hidden
```

Its output holds `######` and no amounts. The `visible` output holds the amounts.

Without screen capture, the masking contract is covered by `swift test` (`Tests/PDTBarTests/PortfolioValueVisibilityTests.swift`). That is not a user-path proof.

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. `capture` frames only the status item and menu, never the Settings window, and it cannot flip the toggle. Use it for the default, unmasked menu. Masked-state pixels still come from `portfolio-values-settings-proof`.

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh capture screenshot "$RUN" values-shown
Scripts/verify_pdtbar.sh stop "$RUN"
```

The image must show the open menu with fixture money amounts visible and no `######`. The `Total portfolio value` label shows either way, so the amount beside it is the proof.

## Gotchas

- There is no prompt-free user-path journey. Without AX, or without Peekaboo and its permissions, the scenario returns `skipped` before it launches or captures anything. With AX it clicks the toggle and always calls `/usr/sbin/screencapture`. With Screen Recording missing or needing re-confirmation, macOS can show a dialog. Run it only when the user asked and is present.
- Always run with `PDTBAR_USER_DEFAULTS_SUITE` isolated. The smoke and `verify_pdtbar.sh` both set it. A bare launch would flip the user's real setting.
