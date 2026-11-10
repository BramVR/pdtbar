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

PDTBar is a quiet macOS menu bar companion for your Portfolio Dividend Tracker portfolio. It reads your portfolio straight from PDT over a read-only connection and shows only the few things worth attention right now.

## What you see

- Concentration: which positions carry the most weight.
- Income events: dividend and cash-flow moments coming up.
- Big movers: holdings that clearly moved.
- Prices: whether price data is current.
- All quiet: a calm status when nothing needs attention.

## How it works

PDTBar uses the same data as PDT for a different job. PDT remains the full dashboard. PDTBar stays in the menu bar and summarizes the two or three facts you would otherwise have to look for.

PDTBar connects to PDT directly:

```text
open PDTBar
check the stored PDT connection
sign in with PDT, or paste a read-only PDT token
fetch read-only PDT data
show the portfolio pulse
```

When PDTBar is not connected, the menu offers `Sign in with PDT` and `Use a PDT token…`. You do not need the terminal for daily use.

## Install

Homebrew is not supported yet. A public app download is not posted yet either, so testers should use a shared `PDTBar.app.zip` build for now.

1. Unzip `PDTBar.app.zip`.
2. Drag `PDTBar.app` into Applications.
3. Open PDTBar and use the menu-bar icon.

The [install guide](install.en.md) covers first-use steps and setup messages.

The [features guide](features.en.md) has more detail on Pulse, Allocation, Income, Big movers, Data, and Actions.

## Trust and privacy

PDTBar is local and read-only by default. It stores your PDT connection only in this Mac's Keychain, and `Disconnect from PDT` deletes it. PDTBar does not place trades, move money, upload your portfolio to its own backend, or give financial advice. The pressure engine ranks facts and changes. You decide what they mean.

## Status

PDTBar is in active development. Fixture mode exists for development and smoke tests, but real portfolio updates come from PDT's read-only API.

## Source

Source code lives on [GitHub](https://github.com/BramVR/pdtbar).
