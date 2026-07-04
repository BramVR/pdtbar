---
summary: "Public English install and first-use guide for PDTBar."
read_when:
  - Updating public install or first-use copy
title: "Install PDTBar"
lang: "en"
permalink: "/en/install/"
description: "Install and use PDTBar on macOS without Homebrew."
---

# Install PDTBar

Homebrew is not supported yet. There is no `brew install` command for PDTBar right now.

There is also no public app download attached to GitHub releases yet. For now, use a shared `PDTBar.app.zip` build from the project maintainer. When public downloads are ready, they will appear on the [PDTBar releases page](https://github.com/BramVR/pdtbar/releases).

## Before You Start

You need:

- A Mac running macOS 14 or newer.
- Your Portfolio Dividend Tracker portfolio.
- Your existing Claude CLI + PDT MCP setup.

If the Claude/PDT setup is not ready yet, PDTBar can still open, but it will ask you to finish that connection before it can show portfolio data. Ask the person who gave you PDTBar to help set up the PDT connection.

## Install The App

1. Double-click `PDTBar.app.zip` if your Mac does not unzip it automatically.
2. Drag `PDTBar.app` into Applications.
3. Open PDTBar from Applications.

If macOS says the app was downloaded from the internet, right-click `PDTBar.app`, choose `Open`, then choose `Open` again. You should only need to do this once.

## First Use

After PDTBar opens, look for the small stack icon in the macOS menu bar.

- If you see your portfolio pulse, you are done.
- If you see `Log in with Claude`, click it, follow the browser steps, then click `Check again`.
- If you see `Add the PDT MCP server to Claude`, PDTBar is installed, but the PDT connection is not ready yet.

## Daily Use

- Click the menu-bar icon to see what needs attention.
- Use `Refresh now` to fetch fresh PDT data.
- Use `Open PDT` when you want the full Portfolio Dividend Tracker dashboard.

PDTBar is read-only by default. It does not place trades, move money, upload your portfolio to its own backend, or give financial advice.
