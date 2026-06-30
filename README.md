# PDTBar

PDTBar is a quiet macOS menu bar companion for a Portfolio Dividend Tracker portfolio.

It watches the whole portfolio through the user's existing Claude CLI + PDT MCP setup and surfaces only the few things worth attention right now: concentration, income events, big movers, freshness, and calm "all quiet" days.

## What It Does

- Shows a compact Concentration Stack icon in the macOS menu bar.
- Fills up to three bars when attention items are present.
- Opens to a ranked pulse instead of a dashboard grid.
- Keeps `Refresh now` and `Open PDT` available from top-level menu actions.
- Keeps portfolio data local and read-only by default.
- Uses deterministic pressure rules, not financial advice.

## Current Status

The product path is Claude-first:

1. Launch PDTBar.
2. PDTBar checks Claude CLI login and the configured PDT MCP server.
3. If ready, it fetches read-only PDT data and publishes the pulse.
4. If setup is missing, the menu offers `Log in with Claude` and `Check again`.

Fixture mode exists for development only and must be launched explicitly.

## Install

Homebrew cask distribution is the primary install path once the first public release is published:

```bash
brew install --cask BramVR/tap/pdtbar
open -a PDTBar
```

Update and uninstall through Homebrew:

```bash
brew update
brew upgrade --cask BramVR/tap/pdtbar
brew uninstall --cask BramVR/tap/pdtbar
```

Homebrew owns updates for cask installs. PDTBar does not include an in-app updater yet.

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
