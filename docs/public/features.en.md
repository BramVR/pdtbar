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

PDTBar shows what is worth noticing in your Portfolio Dividend Tracker portfolio right now.

The app keeps the full dashboard in PDT and uses the macOS menu bar for a shorter view: a status icon, a ranked pulse, and drill-down sections for the facts behind it.

## Menu-bar pulse

The menu-bar icon is a compact Concentration Stack. It stays visible while PDTBar runs.

- Bar heights show the current concentration pattern.
- Filled bars show how many unread attention items exist, capped at three.
- The tooltip and accessibility label include the current status in words.
- If nothing needs attention, the icon shows no alert.

Click the icon to open the menu. It starts with a summary card: `Total portfolio value`, plus `CAGR` and `Total increase` when PDT has those figures. Without open holdings the card reads `No open holdings`.

The first section is `Pulse`, which shows either the top attention items or `All quiet`. `All quiet` reads `No attention items right now.` and opens to `Open holdings`, the weight of your top holdings, and how current your `Prices` are.

## Attention items

Attention items are facts that crossed a line set by deterministic rules. They are not recommendations.

PDTBar can currently show:

- Holding concentration at or above 20%.
- Sector concentration at or above 30%.
- Cash allocation at or above 10%.
- Top concentration drift of 5% or more when a prior snapshot exists.
- Big holding price moves of 10% or more over the recent window.
- Confirmed ex-dividend dates inside the next 30 days.

Each attention item expands to show:

- `Trigger`: the line it crossed, such as `Concentration line crossed`, `Sector concentration line crossed`, `Price move crossed recent-window line`, or `Ex-dividend date in income window`.
- `Severity`, `Threshold`, and `Current`, plus `Prior` when an earlier value exists.
- `Sources`: the PDT data PDTBar used, such as `Open holdings`, `Sector breakdown`, `Calendar events`, or `Price rows`.
- `Mark as read`, which takes the item out of the Pulse count.

## Allocation

The `Allocation` section shows the shape of the portfolio without opening PDT.

- `Portfolio` shows a compact allocation chart.
- `Full allocation list` opens the holding list. Each holding shows its portfolio weight.
- A holding opens to `Worth`, `Price`, `ISIN`, `Recent move`, `Next income`, `Average buy price`, `Gain/loss`, `Gain/loss %`, and `Copy identifier`, each when PDT provides it.
- `Sectors` and `Asset types` summaries appear below the holding list when PDT provides that data.
- Without holdings, the section reads `No holdings to show`.

Allocation pressure can appear in `Pulse`, but the underlying allocation facts stay available even after you mark the attention item read.

## Income

The `Income` section is a calendar view you can browse. It also lists events that are not alerts.

- `Income window` summarizes upcoming events.
- `Next income` highlights the next dividend or cash-flow event.
- PDTBar groups later events into short buckets such as `This week` and `Later`.
- An event opens to `Date`, `Kind` (such as `Ex-dividend date` or `Dividend payment date`), `State` (`Confirmed` or `Estimated`), `Amount`, and `Change`, when that information is available.
- With nothing coming up, the section reads `No income events in the next window`.

Only confirmed ex-dividend dates inside the current 30-day window become Pulse attention items. Other income events remain available in the Income section.

## Big movers

The `Big movers` section summarizes recent price movement.

When a holding crosses the 10% move line, PDTBar can show it in Pulse with the before/after price, the move size, and the source window. If no holding crosses the line, the section still shows how many price rows PDTBar checked. Without any price history it reads `No price history to compare yet`.

When a prior snapshot exists, PDTBar compares the current holding against that snapshot first. If prior data is missing, it falls back to PDT price history.

## Data and prices

The `Data` section tells you whether the numbers are current enough for a quick look.

- `Prices` shows whether price data is current, stale, partial, or unknown. Without holdings it reads `No holdings to price`.
- The `Prices` submenu lists each holding's last price from PDT with the day it is for, such as `EUR 1,376.80 on 2026-11-12`. That day can lag today by a day or more. A holding PDT has not priced reads `No price from PDT`. With `Show portfolio values` off, the price is hidden but its date stays.
- Stale data shows `Stale holdings` and the `Oldest price` date.
- Partial data can show the `Latest complete detail fill`.
- `Data health` appears when source health is degraded, for example `Not fetched this session` before PDTBar has fetched from PDT. It opens to:
  - `Source`, such as `PDT, read-only; not fetched this session`.
  - `Access`, such as `Not checked this session`.
  - `Cache`, with the day of the last sync.
  - `Prices`, with the price freshness.
  - `Detail fill`, such as `Not started`.
  - `Read state`, with how many attention items you marked read.
  - `Diagnostics`, which reads `None recorded` until a refresh fails. After a failure, `Copy diagnostics` copies the details so you can troubleshoot it.

Cached data can keep the menu useful while PDTBar refreshes in the background, but the Data section tells you when that is happening.

## Actions

The `Actions` section keeps daily use short.

- `Refresh now` asks PDTBar to fetch fresh PDT data and fill in the latest details.
- `Open PDT` opens the full Portfolio Dividend Tracker dashboard.
- `Settings...` opens the native Settings window, where `Show portfolio values` can hide or restore displayed monetary portfolio values.
- `Disconnect from PDT` deletes the stored PDT connection.
- `Sign in with PDT` and `Use a PDT token…` appear when PDTBar is not connected or PDT asks you to reconnect.
- `Check again` checks the PDT connection again, for example after you renew a paused PDT subscription.

## Read state

Unread attention items fill the status icon and appear in Pulse. After you mark an item read, it disappears from the Pulse count, but the underlying facts remain in Allocation, Income, Big movers, or Data.

If the material fact changes later, it can show up again. For example, PDTBar treats a concentration item as new if it crosses the line again with materially changed values.

## Privacy and limits

PDTBar reads PDT through its API over a read-only connection stored in this Mac's Keychain. It is local and read-only by default.

The `Show portfolio values` setting hides monetary values in the menu, status copy, tooltips, accessibility labels, chart details, and submenus. It does not delete fetched snapshots or cached local portfolio data. Turning it back on restores the displayed values from the current in-memory pulse.

PDTBar does not place trades, move money, upload your portfolio to its own backend, or give financial advice. It ranks facts and changes. You decide what they mean.

The [install guide](install.en.md) covers setup and first-use steps.
