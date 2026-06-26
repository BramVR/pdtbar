---
summary: "Public PDTBar home page."
read_when:
  - Changing the public docs-site home page
title: "PDTBar"
description: "PDTBar is a quiet macOS menu bar companion for Portfolio Dividend Tracker portfolios."
lang: "en"
alternate: "../index.md"
---

# PDTBar

PDTBar is a quiet macOS menu bar companion for a Portfolio Dividend Tracker portfolio.

It uses the user's existing Claude CLI + PDT MCP setup, fetches read-only portfolio data, and surfaces only what is worth attention right now: concentration, income events, big movers, freshness, or a calm all-quiet state.

![PDTBar menu states](../assets/pdtbar-menu.png)

## What It Does

- Shows a compact Concentration Stack icon in the macOS menu bar.
- Fills up to three bars when attention items are present.
- Opens to a ranked pulse instead of a dashboard grid.
- Keeps portfolio data local and read-only by default.
- Uses deterministic pressure rules, not financial advice.

## How It Works

1. Launch PDTBar.
2. PDTBar checks Claude CLI login and the configured PDT MCP server.
3. If ready, it fetches read-only PDT data and publishes the pulse.
4. If setup is missing, the menu offers `Log in with Claude` and `Check again`.

Fixture mode exists for development only and is never the default product path.

## Why The Menu Bar

PDT is a place you visit to inspect your portfolio. PDTBar inverts that: it watches quietly and brings forward only the two or three things useful today.

On calm days, silence is a designed state. You get context without manufactured urgency.

## Privacy And Trust

- No trades.
- No buy or sell advice.
- No generic OAuth flow or token paste box.
- No partial pulse if fetching data fails.
- Local, read-only route through Claude CLI and PDT MCP.

## Source

PDTBar is open source at [BramVR/pdtbar](https://github.com/BramVR/pdtbar).

```sh
git clone https://github.com/BramVR/pdtbar.git
cd pdtbar
make start
```
