# PDTBar

PDTBar is a quiet macOS menu bar companion for a Portfolio Dividend Tracker portfolio.

It reads the whole portfolio straight from PDT, read-only, and surfaces only the few things worth attention right now: concentration, income events, big movers, current prices, and calm "all quiet" days.

## What It Does

- Shows a compact Concentration Stack icon in the macOS menu bar.
- Fills up to three bars when attention items are present.
- Opens to a ranked pulse instead of a dashboard grid.
- Keeps `Refresh now` and `Open PDT` available from top-level menu actions.
- Keeps portfolio data local and read-only by default.
- Uses deterministic pressure rules, not financial advice.

## Current Status

The product path connects to PDT directly ([ADR-0002](docs/adr/0002-pdt-public-rest-api.md)):

1. Launch PDTBar.
2. PDTBar checks its stored PDT connection. Nothing opens on its own.
3. If you are not connected, the menu offers `Sign in with PDT` (your browser opens PDT's approval page) or `Use a PDT token…` (paste a read-only token from PDT's Integrations > API page).
4. Once connected, it fetches read-only PDT data, saves it on this Mac, then shows the pulse.
5. If PDT stops accepting the connection, the menu says `Reconnect to PDT` and keeps your last pulse visible. If your PDT subscription ended, it says `PDT access paused`.

The connection is stored in this Mac's Keychain only. `Disconnect from PDT` deletes it; PDT keeps the approval until you remove PDTBar on PDT's connected apps page. No other tool is needed.

Fixture mode exists for development only and must be launched explicitly.

## Install

Homebrew is not supported yet. There is also no public app download attached to GitHub releases yet.

For now, use a shared `PDTBar.app.zip` build from the project maintainer. When public downloads are ready, they will appear on the [PDTBar releases page](https://github.com/BramVR/pdtbar/releases).

Once you have the zip:

1. Double-click the zip if your Mac does not unzip it automatically.
2. Drag `PDTBar.app` into Applications.
3. Open PDTBar from Applications.

If macOS says the app was downloaded from the internet, right-click `PDTBar.app`, choose `Open`, then choose `Open` again. You should only need to do this once.

PDTBar needs a PDT account with API access. Open the menu and choose `Sign in with PDT`. If the menu says `Keychain unavailable`, this copy of PDTBar was not signed for the Keychain; install the signed release instead.

## Use

After launch, look for the small Concentration Stack icon in the macOS menu bar.

- Click the icon to see the portfolio pulse.
- Use `Refresh now` to fetch fresh PDT data.
- Use `Open PDT` when you want the full dashboard.
- Use `Settings...` to show or hide displayed portfolio values.
- Use `Sign in with PDT` if PDTBar is not connected, then approve PDTBar in the browser.
- Use `Check again` after renewing a paused PDT subscription, and `Disconnect from PDT` to remove the stored connection.

## Product Principles

- Informational, never prescriptive.
- Quiet by default.
- Plug-and-play: no commands in daily use.
- Local-first and privacy-conscious.
- Bar renders; engine decides.

## For Contributors And Agents

Implementation notes, architecture, smoke checks, and reuse guidance live in [`docs/`](docs/README.md). Start there before changing behavior.

Common local workflow:

```bash
make docs-list
make docs-site
make docs-site-test
make start
make stop
make test
make check
swift test
swift run pdtbar-checks
./Scripts/compile_and_run.sh
```

Use `make start` or `./Scripts/compile_and_run.sh` for manual UX testing. Both
package and launch `PDTBar.app`; do not use raw `.build/debug/pdtbar` as the
first-run product path.

Packaging smoke:

```bash
swift run pdtbar-smoke app-bundle-packaging
```

Release app archive smoke:

```bash
ARCHES="$(uname -m)" ./Scripts/package_release_app.sh v0.0.0-test
```

## License

License pending. Reused MIT-licensed code or direct copies must keep attribution; see [`docs/reuse-notes.md`](docs/reuse-notes.md).
