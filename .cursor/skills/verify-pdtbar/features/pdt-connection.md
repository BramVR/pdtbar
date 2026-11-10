# PDT connection

The user launches PDTBar without a working PDT connection, or with one PDT stopped accepting. The menu names the state and offers what fits it: `Sign in with PDT`, `Use a PDT token…`, `Check again`, and `Disconnect from PDT`.

Proof that it works: not connected shows `Not connected`, `Sign in with PDT`, and `Use a PDT token…`, and hides any cached pulse. A revoked token shows `Reconnect to PDT` with `Check again` and `Disconnect from PDT`. `403 API_ACCESS_PAUSED` shows `PDT access paused`. A build without the Keychain entitlement (`-34018`) shows `Keychain unavailable`. One `Check again` click reruns the connection check exactly once; a second click while the check or fetch runs starts nothing. `Sign in with PDT` shows `Signing in with PDT`, then `Fetching portfolio`. A declined sign-in shows `Sign-in failed`. No path runs `claude` or `mcporter`.

## Sub-features

- Not-connected setup menu.
- Reconnect (`signInExpired`, `tokenExpired`, `tokenRevoked`, `tokenInvalid`, `readAccessMissing`), paused subscription, and Keychain unavailable, each keeping a cached pulse visible below the connection rows.
- `Check again`, which reruns the connection check once.
- `Sign in with PDT` (browser, loopback) with `Cancel sign-in`; a failure shows `Sign-in failed` with its reason.
- `Use a PDT token…`, a secure field whose token is stored without a verification request; the first fetch answers.
- `Disconnect from PDT`, which deletes the credential and shows `Remove PDTBar in PDT…`, opening connected apps (sign-in) or Integrations (token).

## How to get to it (user POV)

On a Mac with no PDT connection, launch PDTBar and click the menu bar icon. The connection rows are the whole menu.

## Driving it with pdtbar-smoke

```bash
swift build --product pdtbar
RUN=$(Scripts/verify_pdtbar.sh launch | sed -n 's/^ready: //p')   # run dir; evidence lands in $RUN/evidence
swift run pdtbar-smoke scripted-setup-retry --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke scripted-sign-in     --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke logged-out-launch    --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
Scripts/verify_pdtbar.sh stop "$RUN"
```

Read `pdtbar-scripted-setup-retry-proof.json` (per scenario: `initialChecks`, `finalChecks`, `finalHoldingsRequests`, `snapshotWritten`, the isolation booleans) and `pdtbar-scripted-sign-in-proof.json` (idle before the click, `sign-in` logged, snapshot written; the declined run fetched nothing).

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. `capture` works only on a `verify_pdtbar.sh launch` run, which is fixture mode, so it cannot show the connection menus. There is no capture path for this feature yet. Prove it with the smoke JSON and AX identifiers above, and say in the PR that no image exists.

## Gotchas

- These smokes need AX to click menu items. Without AX they prove the launch state from the event log (one `check`, no fetch where none is due) and return `skipped` with the missing permission named. Report that as not driven, not as passed.
- Sign-in is scripted (`signIn: succeeds|denied|portBusy|timedOut|waitsForCancel`). A real `Sign in with PDT` opens a browser and stores a credential in the Keychain, so never run it during verification.
- The paused scenario expects three holdings requests after Check again: the 403, the first fetch, and the background detail refresh that follows it. A fourth means a duplicate fetch.
- `packaged-onboarding` is the packaged-bundle variant. It needs `./Scripts/package_app.sh` first, and with `--peekaboo` it captures the screen, which makes it opt-in.
