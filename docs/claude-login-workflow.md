---
summary: "Claude-first product launch, setup states, first fetch, cached pulse, and status icon semantics."
read_when:
  - Changing no-argument launch or setup/login behavior
  - Changing first fetch, cached pulse, or retry behavior
  - Changing status icon semantics
---

# Claude Login Workflow

This is the current Claude-first product flow. Older PRD/planning text is historical when it conflicts with this file, the Swift code, or closed child issues #44-#53 and #64.

## Product launch

No-argument `pdtbar` launch is the user path. It uses isolated app support when `--app-support-dir` or `PDTBAR_APP_SUPPORT_DIR` is supplied for smoke tests; otherwise it uses normal app state. Fixture mode is explicit only:

```bash
pdtbar --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
```

On product launch the app enters `probingClaude` before visible login UI. Scripted smoke files can drive this state in isolated test runs; otherwise the probe checks whether the existing signed-in Claude CLI user can reach the configured PDT MCP server through `claude mcp list`. It must not open surprise prompts or fall back to fixtures.

## Setup states

- Ready Claude/PDT setup: skip logged-out UI and start first fetch.
- Missing Claude login: show `Not connected`, `Log in with Claude`, and `Check again`.
- Missing PDT MCP: show `Add the PDT MCP server to Claude` and `Check again`.
- Missing Claude CLI or failed login: show the matching CodexBar-style login failure (`Claude CLI not found`, `Claude login timed out`, `Claude login failed`, or `Could not start claude auth login`) plus retryable `Log in with Claude`.
- Probe/fetch failure: keep setup or the previous good pulse visible; show retry copy in the menu.

`Log in with Claude` is user-initiated. It runs `claude auth login` through the same PTY-style flow CodexBar uses for Claude Code auth, then waits for CLI login success. Browser OAuth, generic providers, Codex login, API keys, tokens, raw MCP JSON, and mcporter are not product login paths.
After a successful login, PDTBar re-runs Claude/PDT readiness before deciding whether to fetch, show signed-out setup, show missing PDT MCP setup, or show probe failure. A failed login shows the matching retryable login failure state.

## First fetch and returning launch

The first fetch calls only required v1 PDT read tools through the Claude/PDT MCP connector. Scripted smoke runs use an isolated scripted connector file; real launches use the logged-in Claude CLI account and PDT MCP server.

- `pdt-get-portfolio-holdings`
- `pdt-get-portfolio-distributions`
- `pdt-list-x-ray-holdings`
- `pdt-list-calendar-events`
- `pdt-list-dividends`
- `pdt-list-symbol-prices`
- `pdt-get-symbol-quote`

Complete data normalizes into `PortfolioSnapshot`, writes `latest-portfolio-snapshot.json`, runs the pressure engine, and then publishes the pulse. Missing required read tools or malformed/partial data prevents pulse publication.
Real Claude CLI first-fetch runs are bounded for launch responsiveness: they fetch portfolio holdings first and publish a minimal pulse quickly, then start a background refresh for distributions, X-ray holdings, calendar events, and dividends. Slow per-holding quote/price enrichment is skipped during onboarding. The manual live smoke still proves all seven required read tools are reachable.

Returning launches may render the previous real snapshot immediately while a fresh fetch runs. After a pulse has been published, transient background detail-fill failures preserve that pulse and show `Details fill failed` plus `Fill details again`; retries coalesce so one replacement detail fill runs. First-fetch failures with no usable pulse still show `Could not fetch portfolio`, `Try again`, and the Claude login action.

## Status icon

The menu bar always shows the Concentration Stack icon. It is a stable portfolio mark, not top-three holdings and not a mini dashboard:

- bar heights: middle bar is always max height; side bars show X-ray look-through concentration shoulders
- missing X-ray data: deterministic default silhouette with left half-height and right two-thirds height
- filled bars: ranked attention item count, capped at three
- zero attention: no filled bars
- no separate round notification dot
- stale/fetch-failed/setup states: tooltip/menu copy and optional whole-icon dimming only

Full status copy remains in tooltip, accessibility label, and the first Pulse menu row.

## Redaction and proof

Public docs/proof may include command names, selectors, row text, counts, durations, scenario booleans, fixture names, and redacted status. They must not include private portfolio data, credentials, private endpoints, raw live payloads, account identifiers, holding names/values from live data, or non-public model IDs.

Use `claude -p` only for optional manual PDT reachability proof. Do not use `claude --bare`; bare mode does not prove the signed-in Claude CLI MCP setup. The smoke defaults to the public `opus` alias and lets local users override via `--model` or `PDTBAR_CLAUDE_MODEL`.
