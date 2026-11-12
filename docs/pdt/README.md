---
summary: "PDT data reality, fixture set, and sanitized evidence index."
read_when:
  - Working with PDT fixtures or live-shaped data
  - Changing portfolio normalization inputs
  - Reviewing PDT data evidence
---

# docs/pdt — PDT data reality & fixtures

The product reads PDT through its public REST API (ADR-0002): `PDTAPIDataSource`
decodes REST envelopes into the same normalization inputs and builds
`PortfolioSnapshot`. Connection and launch flow:
[`../pdt-connection-workflow.md`](../pdt-connection-workflow.md).

The MCP material here is historical evidence: it was captured by exercising
the PDT MCP live (2026-06-22) for issue #8, resolved the "PDT data reality" open
question in `../../CONTEXT.md`, and fed ADR-0001. PDTBar no longer talks to the
PDT MCP (#250).

- [`portfolio-data-source.md`](portfolio-data-source.md) — the `PortfolioDataSource`
  seam described in terms of facets, the normalized interface, freshness rules,
  documented gaps/missing fields, and the ADR-0001 evidence.
- [`fixtures-schema-notes.md`](fixtures-schema-notes.md) — raw PDT MCP tool
  schemas (field names/types) observed live on 2026-06-22; historical, and still
  the reference for the scenario fixtures.
- [`fixtures/`](fixtures/) — sanitized scenario fixtures captured through the
  retired PDT MCP on 2026-06-22 and frozen. They are dev/test input only, read
  by `PDTFixtureDataSource` when `pdtbar --fixture <file>` is passed explicitly,
  and by checks, dev commands, smokes, and tests. Each mirrors the MCP response
  envelopes (field names/types verbatim) with fake securities and redacted
  account data:
  - `concentration-pressure.json` — allocation pressure (top weight 24.2% > 20%).
  - `income-event.json` — ex-dividend in window + payment landed + derivable raise.
  - `big-mover.json` — +12.4% move via price history and prior-vs-current snapshot.
  - `quiet-no-pressure.json` — the explicit all-quiet state.
  - `worst-case-height.json` — composed from the frozen fixtures above, not captured: every facet firing at once (three big movers fill Pulse, both allocation pressures spill into Allocation, full Income list). Menu height stress case (#296).
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
  - [`provenance.json`](fixtures/api/provenance.json) — the bodies are
    synthetic, hold no account data, were written for #265 against PDT REST
    docs v0.8.1 and checked against ADR-0002's live envelope findings, and were
    not re-checked against openapi v0.9.0. It lists every reply per scenario
    with its `GET /v1/...` request; `pdtbar-checks` fails when it drifts from the
    directories. It sits at the `api/` root because replay reads every `*.json`
    in a scenario directory.

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
