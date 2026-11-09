---
name: verify-pdtbar
description: "Drive and prove the PDTBar macOS menu bar app (status item + pulse menu) from a fresh build without macOS permission prompts. Use when verifying a PDTBar launch, setup/login, first-fetch, pulse, menu, or settings change, or when collecting PR proof."
---

# Verify PDTBar

PDTBar is a menu-bar-only macOS app (`LSUIElement`, no Dock icon, no window at launch). The surface a user touches is the status item (`pdtbar.status`) and its menu. The Settings window is secondary. Engine logic lives in `PDTBarCore`; the app renders `MenuDescriptor`s. Every menu row carries a stable accessibility identifier: `pdtbar.section.<id>` for sections and `pdtbar.row.<id>` for rows (for example `pdtbar.row.pulse.status` or `pdtbar.row.actions.settings`).

Feature journeys live in [features/README.md](features/README.md).

## Hard rules

- Never launch `pdtbar` with no arguments unless `PDTBAR_DISABLE_REAL_CLAUDE=1` is set or the isolated app support dir holds `pdtbar/claude-readiness.json`. Otherwise the app runs the real `claude` CLI, which can read the login Keychain and show a Keychain prompt.
- Never point a run at the user's real app support dir or `UserDefaults`. Always set `PDTBAR_APP_SUPPORT_DIR`, `--snapshot-dir`, and `PDTBAR_USER_DEFAULTS_SUITE` to isolated values (`Scripts/verify_pdtbar.sh` does this).
- Live Claude/PDT (`manual-claude-pdt`, `live-pdt`), Peekaboo, and any screenshot-capturing smoke are opt-in only. Do not run them unless the user asks. PDT write tools are never called.
- Never kill by process name. A user may run an installed `PDTBar.app`, and other checkouts may run their own build.
- Never call `AXIsProcessTrustedWithOptions` with the prompt option, `CGRequestScreenCaptureAccess`, or `osascript`/System Events UI scripting. Those can show TCC dialogs.

## Launch

```bash
swift build --product pdtbar
Scripts/verify_pdtbar.sh launch                                        # quiet-no-pressure fixture
Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json
```

This starts `.build/debug/pdtbar --fixture <f> --snapshot-dir <run>/snapshots` with `PDTBAR_DISABLE_REAL_CLAUDE=1`, an isolated `PDTBAR_APP_SUPPORT_DIR`, and a throwaway `PDTBAR_USER_DEFAULTS_SUITE`. Each launch gets a fresh, empty run dir under `.build/verify-pdtbar/<stamp>-<pid>/`, holding `pid`, `app.log`, `snapshots/`, `app-support/`, `evidence/`, and `defaults-suite`.

Ready means the script printed `ready: <run-dir>`. That requires the process to be alive and `snapshots/latest-portfolio-snapshot.json` to be written, which happens after `PressureRunner` produced the descriptor the status item renders. A live PID alone is not ready. A failed launch prints `app.log`, stops the process, and exits 1.

Fixture mode never probes Claude or PDT. To exercise the no-argument Claude-first path (setup, login, first fetch), use the scripted smokes under Drive. They seed scripted readiness and scripted PDT MCP responses at the production connector boundary.

Two runs can coexist. Each gets its own status item and run dir. Each `pdtbar-smoke` invocation also isolates its own state under `--artifacts` / `--app-support-dir`.

Teardown: `Scripts/verify_pdtbar.sh stop <run-dir>`. See Cleanup.

## Doctor

Run this first, and again whenever anything looks off:

```bash
Scripts/verify_pdtbar.sh doctor <run-dir>
```

It is read-only. It fails unless:
- the recorded PID is alive,
- its command line is exactly this checkout's `.build/debug/pdtbar` with this run's snapshot dir,
- the binary has not been rebuilt since launch (inode and mtime recorded in `<run>/binary`), and no `Sources/**/*.swift` is newer than it,
- the fixture snapshot exists.

It also lists other `pdtbar`/`PDTBar.app` processes so you know not to touch them. `doctor: ok` is the only green result. On a stale build, run `stop`, then `swift build --product pdtbar`, then `launch` again.

Doctor does not check Claude auth, and it should not. Fixture and scripted runs never use it.

## Drive

PDTBar has no in-process automation port. The repo's driver is `swift run pdtbar-smoke <scenario>` (`Sources/PDTBarSmoke/main.swift`). It launches the real app binary with isolated state, scripts external boundaries only, and opens the real status menu through macOS Accessibility when the calling process is already trusted. It finds elements by the `pdtbar.*` identifiers above, never by coordinates. Each scenario prints a JSON report `{name,status,detail,artifacts}`. It exits 1 only on `failed`. `skipped` means a missing permission or setup, and the `detail` field names it.

Pass `--artifacts <run-dir>/evidence` (and `--app-support-dir <run-dir>/smoke-app-support` where accepted) so proof lands in the run dir.

Prompt-free scenarios. None of these captures the screen. They open the menu through AX only if AX is already granted, and otherwise skip that part cleanly:
- No app launch: `scripted-pdt-connector`, `scripted-pulse-mark-read`, `copy-holding-identifier-action`, `fixture-proof`, `menu-polish-proof`.
- Real app launch: `scripted-first-fetch`, `scripted-setup-retry`, `scripted-login-handoff`, `ready-launch`, `logged-out-launch`, `real-claude-flow-ax`.

These are opt-in. They capture the screen (`/usr/sbin/screencapture` or Peekaboo), which can show a Screen Recording prompt or a periodic re-confirmation: `real-user-pulse`, `portfolio-summary-proof`, `portfolio-values-settings-proof`, `peekaboo`, `packaged-onboarding --peekaboo`, and `scripted-returning-launch`, which falls back to a full-screen capture when AX is granted.

These are opt-in. They use live Claude or PDT: `manual-claude-pdt`, `live-pdt`.

A `pdtbar-smoke` scenario launches its own app. It does not attach to a `verify_pdtbar.sh` instance. Use the launched instance to inspect by hand, to hand to a user, or to prove fixture-mode launch side effects.

The rendered descriptor is not a user path. Use it to read the exact identifiers a fixture produces:

```bash
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json
```

## Evidence

- Run dir: `.build/verify-pdtbar/<run>/`. It is gitignored and survives `stop`. Smoke proof JSON goes to `--artifacts`. The default is `.build/pdtbar-smoke-artifacts/`.
- Capture the action and the resulting state together. Examples: the smoke report JSON plus its proof file (`pdtbar-scripted-*-proof.json`, `*-ax.json` with the identifiers seen in the open menu), or the fixture snapshot plus `doctor` output for a manual launch.
- Verify side effects, not just exit codes. Check that snapshots were written in isolated state, that fixture sentinel dirs stayed empty, and that readiness probe counts match.
- Read the proof. `accessibilityChecked: false` means the menu was never opened. That proves launch and state, not what the menu showed. Say so in the PR.
- Mocks are allowed only where the repo already isolates a production boundary: scripted readiness (`claude-readiness.json`), scripted PDT MCP (`scripted-pdt-mcp.json`), and the scripted login binary (`--scripted-claude-login-bin`). Never use internal setters or test-only code paths as proof.
- Redaction (`docs/smoke-checks.md`): proof may carry selectors, row text, counts, booleans, and fixture names. It must never carry live holdings, values, account IDs, endpoints, or raw PDT payloads.
- PR images must be PNG uploaded to the PR so GitHub serves a `user-attachments` URL (see `AGENTS.md`). A permission-free visual: `swift run pdtbar-smoke fixture-proof --output <run>/evidence/fixture-proof.svg`, then `qlmanage -t -s 1200 -o <run>/evidence <run>/evidence/fixture-proof.svg`. It is descriptor-rendered, not real menu pixels. Label it that way.

## Cleanup

```bash
Scripts/verify_pdtbar.sh stop <run-dir>
```

`stop` re-checks that the recorded PID is this run's app before it sends TERM, and refuses otherwise. It deletes the throwaway defaults suite and `app-support/`. It keeps `snapshots/`, `evidence/`, and `app.log`. Smokes terminate their own child processes. Their isolated dirs under `--artifacts` are evidence, so leave them. Run `stop` after every failed iteration too. Delete old run dirs only when the user asks. Never use `make stop` or `Scripts/stop.sh` for a verify run, because they target the packaged app and every raw build for this checkout.

## Helpers

- `Scripts/verify_pdtbar.sh launch [fixture] | doctor <run-dir> | stop <run-dir>` is executable and syntax-checked by `make check`.
- `swift run pdtbar-smoke` with no arguments prints every scenario and its flags.

Keep this skill and `features/` honest as behavior changes with `/maintain-verification-skill`, if installed, or by hand. When a journey fails because a precondition is missing, record why under that feature's Gotchas. Never weaken the journey to make it pass.
