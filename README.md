# PDTBar

PDTBar is a quiet macOS menu bar companion for a Portfolio Dividend Tracker portfolio.

It watches the whole portfolio through the user's existing Claude CLI + PDT MCP setup and surfaces only the few things worth attention right now: concentration, income events, big movers, freshness, and calm "all quiet" days.

## What It Does

- Shows a compact Concentration Stack icon in the macOS menu bar.
- Fills up to three bars when attention items are present.
- Opens to a ranked pulse instead of a dashboard grid.
- Keeps portfolio data local and read-only by default.
- Uses deterministic pressure rules, not financial advice.

## Current Status

The product path is Claude-first:

1. Launch PDTBar.
2. PDTBar checks Claude CLI login and the configured PDT MCP server.
3. If ready, it fetches read-only PDT data and publishes the pulse.
4. If setup is missing, the menu offers `Log in with Claude` and `Check again`.

Fixture mode exists for development only and must be launched explicitly.

## Product Principles

- Informational, never prescriptive.
- Quiet by default.
- Plug-and-play: no commands in daily use.
- Local-first and privacy-conscious.
- Bar renders; engine decides.

## For Contributors And Agents

Implementation notes, architecture, smoke checks, and reuse guidance live in [`docs/`](docs/README.md). Start there before changing behavior.

## License

License pending. Reused MIT-licensed code or direct copies must keep attribution; see [`docs/reuse-notes.md`](docs/reuse-notes.md).
