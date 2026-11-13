---
summary: "Public English install and first-use guide for PDTBar."
read_when:
  - Updating public install or first-use copy
title: "Install"
lang: "en"
permalink: "/en/install/"
description: "Install and use PDTBar on macOS without Homebrew."
---

# Install

Homebrew is not supported yet. There is no `brew install` command for PDTBar right now.

There is also no public app download attached to GitHub releases yet. For now, use a shared `PDTBar.app.zip` build from the project maintainer. When public downloads are ready, they will appear on the [PDTBar releases page](https://github.com/BramVR/pdtbar/releases).

## Before you start

You need:

- A Mac running macOS 14 or newer.
- Your Portfolio Dividend Tracker portfolio.
- A PDT account to connect PDTBar to.

PDTBar opens without a connection and asks you to connect to PDT before it shows portfolio data.

## Install the app

1. Double-click `PDTBar.app.zip` if your Mac does not unzip it automatically.
2. Drag `PDTBar.app` into Applications.
3. Open PDTBar from Applications.

If macOS says the app was downloaded from the internet, right-click `PDTBar.app`, choose `Open`, then choose `Open` again. You should only need to do this once.

## First use

After PDTBar opens, look for the small stack icon in the macOS menu bar.

- If you see your portfolio pulse, you are done.
- If you see `Sign in with PDT`, click it and approve PDTBar on PDT's page in your browser.
- To use a token instead, choose `Use a PDT token…` and paste a read-only token from PDT's Integrations > API page.
- If you see `Reconnect to PDT`, PDT stopped accepting the connection. Sign in again or paste a new token. Your last pulse stays visible.
- If you see `PDT access paused`, your PDT subscription has ended. Renew it, then click `Check again`.
- If you see `Connection not saved`, PDTBar could not save the connection to the Keychain. It keeps working until you quit PDTBar. After that you sign in again. A copy of PDTBar built without Keychain access never saves it, and says so on `Not connected` before you sign in.
- If you see `Keychain unavailable`, this copy of PDTBar could not read or remove its connection in the Keychain.

## Daily use

- Click the menu-bar icon to see what needs attention.
- Use `Refresh now` to fetch fresh PDT data.
- Use `Open PDT` when you want the full Portfolio Dividend Tracker dashboard.
- Use `Disconnect from PDT` to remove the stored connection.

PDTBar is read-only by default. It does not place trades, move money, upload your portfolio to its own backend, or give financial advice.

The [features guide](features.en.md) explains what each menu section does.
