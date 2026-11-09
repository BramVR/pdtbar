---
summary: "PDT data reality, fixture set, and sanitized evidence index."
read_when:
  - Working with PDT fixtures or live-shaped data
  - Changing portfolio normalization inputs
  - Reviewing PDT data evidence
---

# docs/pdt — PDT data reality & fixtures

Evidence captured by exercising the PDT MCP live (2026-06-22) for issue #8.
This resolves the "PDT data reality" open question in `../../CONTEXT.md` and
feeds ADR-0001.

Current product fetch path is Claude-first: no-argument launch probes Claude
Desktop/PDT MCP readiness, then the connector checks the required v1 read tools
before normalizing into `PortfolioSnapshot`. The PDT shapes below are still the
normalization source of truth; setup/login flow lives in
[`../claude-login-workflow.md`](../claude-login-workflow.md).

- [`portfolio-data-source.md`](portfolio-data-source.md) — the `PortfolioDataSource`
  seam described in terms of facets, the normalized interface, freshness rules,
  documented gaps/missing fields, and the ADR-0001 evidence.
- [`fixtures-schema-notes.md`](fixtures-schema-notes.md) — raw PDT tool schemas
  (field names/types) observed live, the reference for the adapter.
- [`fixtures/`](fixtures/) — sanitized scenario fixtures, each mirroring the real
  PDT response envelopes (field names/types verbatim) with fake securities and
  redacted account data:
  - `concentration-pressure.json` — allocation pressure (top weight 24.2% > 20%).
  - `income-event.json` — ex-dividend in window + payment landed + derivable raise.
  - `big-mover.json` — +12.4% move via price history and prior-vs-current snapshot.
  - `quiet-no-pressure.json` — the explicit all-quiet state.
- [`fixtures/api/`](fixtures/api/) — synthetic PDT REST response bodies, one file
  per request, numbered in the order `PDTAPIDataSource` sends them. Replay a
  directory's files sorted by name through `ScriptedPDTHTTPTransport`. Same fake
  universe (`symbolId` = `symbolQuoteId` − 4000). Bodies mix JSON numbers and
  numeric strings on purpose. No `_meta` keys.
  - `full/` — every facet: GBX/FX and second-currency cash holdings, an inactive
    zero-worth row and a closed row, two calendar pages with an estimated event,
    a dividend correction pair, x-ray offset pages, symbol quotes, prices/batch.
    Drives `swift run pdtbar-smoke scripted-api-snapshot`.
  - `quiet-no-pressure/`, `concentration-pressure/` — the MCP fixtures of the same
    name in REST envelopes, for pressure parity tests.
  - Assumed, not yet seen live: calendar, dividend, and symbol-quote row fields
    match the MCP tools; x-ray items carry `weight` (0-100) beside `symbolName`.

## Sanitization rules applied

- **No real account data.** No real names, account/user/broker/import/transaction/
  dividend ids, emails, or ISINs. `pdt-get-user-profile` PII is never reproduced.
- **Shapes preserved.** PDT field names and types are kept verbatim: Money objects
  `{value:String, currency}`, weights as fractions, ISO-8601 dates, +/− dividend
  correction pairs, trading-vs-portfolio currency pairs and exchange rates.
- **Fake securities.** A consistent fake universe (`Nova Lithography`/`NOVA`,
  `Helix Pharma A/S`/`HLX`, etc.) reused across fixtures so the
  `symbolId ↔ symbolQuoteId` joins still demonstrate correctly.
- A `_meta` block (and `_query`/`_note` keys) document provenance and the scenario;
  these are clearly underscore-prefixed and are NOT PDT fields.
