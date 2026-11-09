# Claude setup and login

The user launches PDTBar without a working Claude CLI login or PDT MCP server. The menu explains what is missing and offers `Log in with Claude` and `Check again`.

Proof that it works: when the Claude login is missing, the menu shows `Not connected`, `Log in with Claude`, and `Check again`. When PDT MCP is missing, it shows `Add the PDT MCP server to Claude`. One `Check again` click reruns readiness exactly once and reaches the first fetch. A successful login shows `Signing in with Claude` and then `Fetching portfolio`. It never returns to the signed-out menu.

## Sub-features

- Signed-out setup menu.
- Missing PDT MCP setup menu.
- `Check again`, which reruns readiness once.
- `Log in with Claude`, which runs `claude auth login` and rechecks readiness. A failure shows `Claude login failed` with a retry.

## How to get to it (user POV)

On a Mac with no Claude sign-in, launch PDTBar and click the menu bar icon. The setup rows are the whole menu.

## Driving it with pdtbar-smoke

```bash
swift build --product pdtbar
swift run pdtbar-smoke scripted-setup-retry   --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke scripted-login-handoff --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke logged-out-launch      --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
```

Read `pdtbar-scripted-setup-retry-proof.json` (readiness probe counts and status booleans) and `pdtbar-scripted-login-handoff-proof.json` (fake CLI not called before the click, login invoked, readiness rerun, fetch started).

## Gotchas

- These smokes need AX to click menu items. Without AX they write descriptor and probe-gate proof and return `skipped` with the missing permission named. Report that as not driven, not as passed.
- Login uses a scripted fake Claude CLI through `--scripted-claude-login-bin`. A real `claude auth login` opens a browser and touches Keychain, so never run it during verification.
- `packaged-onboarding` is the packaged-bundle variant. It needs `./Scripts/package_app.sh` first, and with `--peekaboo` it captures the screen, which makes it opt-in.
