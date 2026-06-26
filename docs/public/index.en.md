---
summary: "Public English home page for the PDTBar docs site."
read_when:
  - Updating the public docs-site copy
title: "PDTBar"
lang: "en"
permalink: "/en/"
description: "PDTBar is a quiet macOS menu bar companion for Portfolio Dividend Tracker portfolios."
---

# PDTBar

PDTBar is a quiet macOS menu bar companion for your Portfolio Dividend Tracker portfolio. It watches through your existing Claude CLI + PDT MCP setup and surfaces only the few things worth attention right now.

## What You See

- Concentration: which positions carry the most weight.
- Income events: dividend and cash-flow moments coming up.
- Big movers: holdings that clearly moved.
- Freshness: how recent the PDT data is.
- All quiet: a calm status when nothing needs attention.

## How It Works

PDTBar uses the same data as PDT, but with the opposite rhythm. PDT remains the full dashboard. PDTBar lives in the menu bar and gives you a short pulse: the two or three facts you would otherwise have to hunt for.

The current product path is Claude-first:

```text
open PDTBar
check Claude CLI login
check PDT MCP server
fetch read-only PDT data
show the portfolio pulse
```

When setup is missing, PDTBar offers `Log in with Claude` and `Check again`. Daily use does not require terminal commands.

## Trust And Privacy

PDTBar is local and read-only by default. It does not place trades, move money, upload your portfolio to its own backend, or give financial advice. The pressure engine ranks facts and changes; you decide what they mean.

## Status

PDTBar is in active development. Fixture mode exists for development and smoke tests, but real portfolio updates use the local Claude CLI + PDT MCP route.

## Source

Source code lives on [GitHub](https://github.com/BramVR/pdtbar).
