---
summary: "Public English feature guide for PDTBar."
read_when:
  - Updating public functionality or feature copy
title: "Features"
lang: "en"
permalink: "/en/features/"
description: "Detailed guide to PDTBar's menu-bar pulse, portfolio sections, refresh states, and privacy model."
---

# Features

PDTBar is built around one small question: what is worth noticing in your Portfolio Dividend Tracker portfolio right now?

The app keeps the full dashboard in PDT and uses the macOS menu bar for a shorter view: a status icon, a ranked pulse, and drill-down sections for the facts behind it.

## Menu-Bar Pulse

The menu-bar icon is a compact Concentration Stack. It stays visible while PDTBar runs.

- Bar heights show the current concentration shape.
- Filled bars show how many unread attention items exist, capped at three.
- The tooltip and accessibility label include the current status in words.
- If nothing needs attention, the icon stays calm instead of showing a fake alert.

Click the icon to open the menu. The first section is `Pulse`, which shows the portfolio value and either the top attention items or `All quiet`.

## Attention Items

Attention items are facts that crossed a deterministic line. They are not recommendations.

PDTBar can currently surface:

- Holding concentration at or above 20%.
- Sector concentration at or above 30%.
- Cash allocation at or above 10%.
- Top concentration drift of 5% or more when a prior snapshot exists.
- Big holding price moves of 10% or more over the recent window.
- Confirmed ex-dividend dates inside the next 30 days.

Each attention item can expand to show the trigger, severity, threshold, current value, prior value when available, and the source data PDTBar used.

## Allocation

The `Allocation` section shows the shape of the portfolio without opening PDT.

- `Portfolio` shows a compact allocation chart.
- `Detailed info` opens the holding list.
- Holdings show their portfolio weight and value when available.
- Holding details can include recent move, next income event, average buy price, gain/loss, and a copyable identifier when PDT provides them.
- Sector and asset-type summaries appear below the holding list when PDT provides that data.

Allocation pressure can appear in `Pulse`, but the underlying allocation facts stay available even after the attention item is marked read.

## Income

The `Income` section is a browsable calendar view, not just an alert list.

- `Income window` summarizes upcoming events.
- `Next income` highlights the next dividend or cash-flow event.
- Later events are grouped into short buckets such as `This week` and `Later`.
- Event rows show date, kind, confirmed/estimated state, amount, and change when that information is available.

Only confirmed ex-dividend dates inside the current 30-day window become Pulse attention items. Other income events remain available in the Income section.

## Big Movers

The `Big movers` section summarizes recent price movement.

When a holding crosses the 10% move line, PDTBar can show it in Pulse with the before/after price, the move size, and the source window. If no holding crosses the line, the section still shows how many price rows were checked.

When a prior snapshot exists, PDTBar compares the current holding against that snapshot first. If prior data is missing, it falls back to PDT price history.

## Data And Prices

The `Data` section explains whether the numbers are current enough to trust for a quick glance.

- `Prices` shows whether price data is current, stale, partial, or unknown.
- Stale data can show the oldest price date and affected holdings.
- Partial data can show the latest completed detail fill.
- `Data health` appears when source health is degraded.
- Diagnostics can be copied when a refresh failure needs troubleshooting.

Cached data can keep the menu useful while PDTBar refreshes in the background, but the Data section tells you when that is happening.

## Actions

The `Actions` section keeps daily use short.

- `Refresh now` asks PDTBar to fetch fresh PDT data and fill latest details.
- `Open PDT` opens the full Portfolio Dividend Tracker dashboard.
- `Log in with Claude` appears only when Claude login is missing.
- `Check again` retries setup after login or PDT MCP setup changes.

## Read State

Unread attention items fill the status icon and appear in Pulse. After you mark an item read, it disappears from the Pulse count, but the underlying facts remain in Allocation, Income, Big movers, or Data.

If the material fact changes later, it can surface again. For example, a concentration item that crosses the line again with new material values is treated as new.

## Privacy And Limits

PDTBar reads through your local Claude CLI + PDT MCP setup. It is local and read-only by default.

PDTBar does not place trades, move money, upload your portfolio to its own backend, or give financial advice. It ranks facts and changes; you decide what they mean.

See the [install guide](install.en.md) for setup and first-use steps.
