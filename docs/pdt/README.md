# docs/pdt — PDT data reality & fixtures

Evidence captured by exercising the PDT MCP live (2026-06-22) for issue #8.
This resolves the "PDT data reality" open question in `../../CONTEXT.md` and
feeds ADR-0001.

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
