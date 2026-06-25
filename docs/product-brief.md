---
summary: "Product brief: mission, target user, menu-bar surface, and non-goals."
read_when:
  - Changing product scope, positioning, or user-facing copy
  - Deciding whether a feature belongs in PDTBar
  - Updating setup/login promises
---

# Product Brief

## Mission

A plug-and-play, ambient companion for an investor's **whole portfolio**, built on the data in the Portfolio Dividend Tracker (PDT). PDT is a *pull* experience — you visit the dashboard and dig to find what changed. This is the inverse: it lives in the menu bar and does the digging, surfacing only the few things that matter right now, with near-zero effort.

## Target user

A retail investor who already tracks their portfolio in PDT and wants to **stay aware of it without effort** — across income, performance, allocation/risk, and corporate events. Income-focused investors are one sub-persona, not the whole audience. Design for whole-portfolio awareness.

## The aha (why it's not just another balance app)

Every brokerage app shows your value and a list of holdings. None of them curate "here are the two or three things to actually look at this week." The aha is **curated relevance**: within a minute of connecting, you see the handful of things worth knowing — a holding that moved hard, rising concentration, a dividend cut, an upcoming corporate action, idle cash, a benchmark divergence — that you'd otherwise have to hunt for. Value and performance are *context*; "what changed and what needs you" is the headline.

## The surface: the menu bar, layered

The product lives in the macOS menu bar (the **pulse**), and **all information is reachable through it** — but via progressive disclosure, never a dashboard grid:

- **Status item (always visible):** the Concentration Stack icon. Bar heights show the concentration shape; filled bars show attention count capped at three; full status copy stays in tooltip/accessibility and the first Pulse row.
- **The menu (the glance):** the ranked attention items, or "all quiet"; each expands to the numbers that triggered it.
- **Submenus (drill-down):** the full picture — holdings/allocation, income/calendar, performance vs benchmark, cash — without leaving the bar.

Quiet at the top, everything available underneath.

## Current connection model

PDTBar is Claude-only. No-argument launch probes the user's existing Claude CLI login and PDT MCP server, then performs the first read-only PDT fetch when ready. If setup is missing, the menu offers `Log in with Claude` and `Check again`; PDTBar does not implement generic OAuth, Codex login, API-key entry, token paste, raw MCP JSON, or a mcporter runtime path.

## What it is NOT

- **Not the PDT dashboard.** No grid of every holding as the primary view. If you want the full dashboard, open PDT.
- **Not noisy.** Quiet-by-default and curation are features, not gaps.
- **Not a trading tool.** It never places trades or moves money.
- **Not financial advice.** It reports facts, changes, and forward schedules; it never tells you what to buy or sell.

## Differentiation, in one line

Same data as PDT, opposite delivery: **push/glance + curation** (the few things under "pressure") instead of a dashboard you visit and scan.

## The core bet

The product's IP is the **pressure engine** — the logic that decides what's worth surfacing across the whole portfolio. Nothing off-the-shelf does this; it's where the effort goes. See `v1-scope.md` for the first coherent product scope.
