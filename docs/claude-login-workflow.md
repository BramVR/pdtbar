# Claude Login Workflow

This is the current Claude-first product flow. Older PRD/planning text is historical when it conflicts with this file, the Swift code, or closed child issues #44-#53 and #64.

## Product launch

No-argument `pdtbar` launch is the user path. It uses isolated app support when `--app-support-dir` or `PDTBAR_APP_SUPPORT_DIR` is supplied for smoke tests; otherwise it uses normal app state. Fixture mode is explicit only:

```bash
pdtbar --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
```

On product launch the app enters `probingClaude` before visible login UI. The probe checks whether the existing signed-in Claude user can reach the configured PDT MCP server. It must not open surprise prompts or fall back to fixtures.

## Setup states

- Ready Claude/PDT setup: skip logged-out UI and start first fetch.
- Missing Claude login: show `Not connected`, `Log in with Claude`, and `Check again`.
- Missing PDT MCP: show `Add the PDT MCP server in Claude Desktop` and `Check again`.
- Missing Claude Desktop or failed handoff: show `Claude Desktop not found` and retryable `Log in with Claude`.
- Probe/fetch failure: keep setup or the previous good pulse visible; show retry copy in the menu.

`Log in with Claude` is user-initiated. It opens or focuses Claude Desktop through the app handoff path. Browser OAuth, generic providers, Codex login, API keys, tokens, raw MCP JSON, and mcporter are not product login paths.

## First fetch and returning launch

The first fetch calls only required v1 PDT read tools through the Claude/PDT MCP connector:

- `pdt-get-portfolio-holdings`
- `pdt-get-portfolio-distributions`
- `pdt-list-x-ray-holdings`
- `pdt-list-calendar-events`
- `pdt-list-dividends`
- `pdt-list-symbol-prices`
- `pdt-get-symbol-quote`

Complete data normalizes into `PortfolioSnapshot`, writes `latest-portfolio-snapshot.json`, runs the pressure engine, and then publishes the pulse. Missing required read tools or malformed/partial data prevents pulse publication.

Returning launches may render the previous real snapshot immediately while a fresh fetch runs. Transient fetch failures preserve that previous pulse and show `Could not fetch portfolio` plus `Try again`; retries coalesce so one replacement fetch runs.

## Status icon

The menu bar always shows the Concentration Stack icon. It is a stable portfolio mark, not top-three holdings and not a mini dashboard:

- bar heights: fixed side bars with a middle bar scaled by whole-portfolio concentration
- concentration shape prefers X-ray look-through weights, then direct holding weights
- filled bars: ranked attention item count, capped at three
- zero attention: no filled bars
- no separate round notification dot
- stale/fetch-failed/setup states: tooltip/menu copy and optional whole-icon dimming only

Full status copy remains in tooltip, accessibility label, and the first Pulse menu row.

## Redaction and proof

Public docs/proof may include command names, selectors, row text, counts, durations, scenario booleans, fixture names, and redacted status. They must not include private portfolio data, credentials, private endpoints, raw live payloads, account identifiers, holding names/values from live data, or non-public model IDs.

Use `claude -p` only for optional manual PDT reachability proof. Do not use `claude --bare`; bare mode does not prove the signed-in Desktop MCP setup. The smoke defaults to the public `opus` alias and lets local users override via `--model` or `PDTBAR_CLAUDE_MODEL`.
