---
summary: "PortfolioDataSource seam: PDT tools, normalized facets, joins, freshness, and gaps."
read_when:
  - Changing PDT/MCP data fetching or normalization
  - Updating pressure facets sourced from PDT
  - Debugging joins, freshness, or fixture realism
---

# PortfolioDataSource — PDT seam, facets & evidence

> Output of issue #8: exercise the PDT MCP, describe the `PortfolioDataSource`
> seam in terms of facets, and capture sanitized fixtures so the engine can be
> built against real PDT shapes instead of assumed ones.
>
> Exercised live against the PDT MCP on **2026-06-22**. All numbers below are
> redacted/sanitized; see `fixtures/` for the runnable JSON and
> `fixtures-schema-notes.md` for the raw per-tool schemas.

## 1. What PDT actually exposes (v1 facets)

| v1 facet | PDT tool(s) | Cold-start? | Key fields |
|---|---|---|---|
| **Allocation / concentration** | `pdt-get-portfolio-holdings`, `pdt-get-portfolio-distributions`, `pdt-list-x-ray-holdings` | ✅ absolute thresholds need no history | `portfolioWeight` (fraction), `currentWorthLocal`, X-ray `items[].weight`, `distributions.sectors[].percentage` |
| **Income events** | `pdt-list-calendar-events`, `pdt-list-dividends` | ✅ ex-div dates are forward-looking | event `type`/`date`/`isEstimated`/`symbolId`; dividend `amount`/`tax`/`date`/`symbolQuoteId` |
| **Big movers** | `pdt-list-symbol-prices`, `pdt-get-portfolio?date=` | ✅ via PDT price history; ✅✅ via prior snapshot | `close`/`closeAdjusted`/`closeCurrency`/`date`; prior-vs-current `portfolioWeight`/`currentPrice` |

Beyond v1, PDT also exposes (confirmed present): performance & benchmark
(`pdt-get-portfolio-performance`, `-performance-benchmark`, `-performance-chart`,
`-gains`), cash (`summary.cash`), corporate actions
(`pdt-list-corporate-actions`), ETF look-through (`pdt-list-x-ray-holdings`),
transactions, bookings, expenses, exchange rates, and investment strategies.
The data is broad and read-only-friendly — every v1 facet has a dedicated
read tool. The product's job is curation, not coverage.

## 2. The normalized `PortfolioDataSource` interface (facets)

The seam hides raw PDT/MCP shapes from the engine. One interface, three current
adapters (live PDT via a `PDTLiveToolClient`, Claude/PDT MCP connector-backed
fetch via `PDTMCPConnectorDataSource`, and a fixture adapter reading
`fixtures/*.json`). It returns
**normalized facets**, not raw PDT payloads:

```
PortfolioDataSource
  snapshot(asOf?) -> PortfolioSnapshot

PortfolioSnapshot
  asOf:        Date                      // when the engine asked
  freshness:   Freshness                 // see §4
  totals:      { currentWorth: Money, cash: Money, currency: String }
  holdings:    [Holding]                 // §facet: allocation, big-movers
  xRayWeights: [Weight]                  // look-through underlying weights
  incomeEvents:[IncomeEvent]             // §facet: income
  // prices/weights for change detection come from prior snapshots + price series

Money    = { value: String (decimal), currency: String }   // PDT shape, verbatim
Weight   = Double                                            // fraction, 0.1567 = 15.67%

Holding
  name:           String          // PDT symbolName
  quoteId:        Int             // PDT symbolQuoteId  (join key for dividends/prices)
  symbolId:       Int?            // resolved via pdt-get-symbol-quote (join key for calendar)
  isin:           String?
  weight:         Weight          // PDT portfolioWeight
  worth:          Money           // PDT currentWorthLocal (portfolio currency)
  price:          Money           // PDT currentPriceLocal (portfolio currency)
  priceNative:    Money           // PDT currentPrice (trading currency, e.g. GBX/DKK/USD)
  fx:             Double          // PDT currentExchangeRate
  priceAsOf:      Date            // PDT currentPriceDate  (per-holding freshness!)
  fxAsOf:         Date            // PDT currentExchangeRateDate
  unrealisedPct:  Double          // PDT unrealisedGainsPercentage
  isCash:         Bool            // PDT symbolName == "Cash"
  isClosed:       Bool            // PDT closedAt != null  (exclude from current views)

IncomeEvent
  kind:    ex-dividend | payment-dividend | earnings-release | ...  // PDT calendar type
  date:    Date
  estimated: Bool                 // PDT isEstimated
  symbolId: Int                   // PDT symbolId — must be joined to a Holding.symbolId
  name:    String
  // "raise/cut" is DERIVED here from pdt-list-dividends, not read (see §3 gaps)

Freshness
  worstPriceAsOf: Date            // min(holding.priceAsOf) across open holdings
  stale:          Bool            // worstPriceAsOf older than N market days vs asOf
```

Normalization the seam owns (all pure logic, no UI):
- **Weights are fractions** in PDT (`0.1567`), not percents — convert once here.
- **Two currencies per holding**: `currentPrice`/`currentWorth` are in the
  *trading* currency (GBX, DKK, USD…); `…Local` variants are in the *portfolio*
  currency (EUR). The engine should consume the `…Local` values + `currentExchangeRate`.
- **Closed positions are included** in `holdings` with `currentWorth = 0` and
  `closedAt` set — filter them out for current allocation/movers.
- **Cash is a holding** (`symbolName: "Cash"`, `symbolQuoteId` present) as well as
  `summary.cash`.
- **X-ray holdings are weight-only in the normalized snapshot** for the status
  icon concentration scalar; underlying names/ISINs/tickers are not needed.
- **Join keys differ across tools** — see §3.

## 3. Gaps / missing PDT fields (impact on v1)

1. **No cross-tool join key.** Holdings & dividends key on `symbolQuoteId`;
   calendar events & corporate actions key on `symbolId`; distributions key on
   *name strings only* (no id at all). `pdt-get-symbol-quote` returns **both**
   `id` (quote) and `symbolId`, so the join is possible but requires an extra
   call (or a built map) per security. **Impact:** the adapter must maintain a
   `symbolId ↔ symbolQuoteId ↔ name` map to attach an income event to a held
   position. Cheap, but it is real plumbing, not a field lookup.

2. **No first-class "dividend raise/cut" or per-share rate.** `pdt-list-dividends`
   returns raw payment rows (gross `amount`, `tax`, `exchangeRate`) but **no
   amount-per-share and no raise/cut flag**. To say "X raised its dividend" the
   engine must divide `amount` by share count (from holdings/transactions at the
   pay date) and compare across periods. Corrections appear as **+/− row pairs**
   (e.g. `+61.20` then `−61.20`) that must be netted first. **Impact:** the
   income "cut/raise" signal is derived, not given — modest engine logic, and
   accuracy depends on having the share count at each historical pay date.

3. **No single portfolio "as-of" timestamp.** Freshness is **per-holding**
   (`currentPriceDate`, `currentExchangeRateDate`); different holdings close on
   different exchange days (US holdings showed `2026-06-18`, EU `2026-06-19`,
   Cash `today`). `pdt-get-portfolio-distributions` carries **no date at all**.
   **Impact:** the engine must compute portfolio freshness as the *worst*
   per-holding `currentPriceDate`, and treat distributions as "freshness unknown".

4. **`pdt-list-portfolios` (snapshot list) is summary-only and looked unreliable.**
   It paginates 1,708 daily snapshots but every row returned `holdings: []` and a
   **zeroed/likely-stale summary** (`currentWorth: 0.00`, identical `totalGains`
   across all rows). Historical *holdings* must instead come from
   `pdt-get-portfolio?date=` / `pdt-get-portfolio-holdings?date=`. **Impact:** for
   big-mover prior-vs-current, rely on dated `get-portfolio` calls and/or
   `pdt-list-symbol-prices`, **not** on `list-portfolios`. (Worth a follow-up to
   confirm whether `list-portfolios` summaries are genuinely broken or just
   not backfilled.)

5. **`isEstimated` on calendar events.** Many ex-dividend/payment dates are
   `isEstimated: true`. **Impact:** income copy must hedge estimated dates
   ("≈ Aug 14") and the engine should not fire high-severity pressure on an
   estimated date alone.

6. **Payload size.** A full `pdt-get-portfolio` / `pdt-get-portfolio-holdings`
   response is ~195 KB / ~90 fields per holding and exceeds a single MCP result
   window. **Impact:** the adapter must stream/curate (or call the
   holdings-only tool and project the ~15 fields the engine needs) rather than
   load the whole blob into the model each tick.

None of these block v1 — every gap is closable with derivation or an extra
join call. The implemented Claude-first connector checks the same required v1
read-tool list before fetching and refuses non-v1 read tools at the connector
seam. These gaps mean the **PortfolioDataSource is non-trivial normalization
logic**, which was the key input to ADR-0001 below.

## 4. Freshness (concrete, observed)

- Per-holding `currentPriceDate` lagged "today" by 1–3 calendar days (weekend +
  per-exchange close). The Cash holding alone was dated *today*.
- `currentExchangeRateDate` is tracked separately from `currentPriceDate`.
- Engine rule: `freshness.worstPriceAsOf = min(currentPriceDate over open
  holdings)`. Fixture-backed v1 flags `stale` when that is older than the
  one-business-day grace; this is a proxy until normalized holdings carry
  per-exchange market calendars. Render a quiet "prices as of \<date>" line
  rather than implying real-time data.

## 5. Fixtures captured (acceptance criteria)

| Fixture | Scenario | Proves |
|---|---|---|
| `fixtures/concentration-pressure.json` | top weight 24.2% > 20% line | allocation pressure, cold-start, sector corroboration |
| `fixtures/income-event.json` | ex-div in window + payment landed + derivable +18% raise | income facet incl. the derive-it gap and the symbolId↔quoteId join |
| `fixtures/big-mover.json` | +12.4% over 5 sessions, weight 9.4%→11.6% | big-mover via price series **and** prior-vs-current snapshot |
| `fixtures/quiet-no-pressure.json` | top weight 11.7%, no events, flat prices, fresh | the explicit all-quiet state |

All fixtures mirror the **real PDT response envelopes** (field names and types
verbatim) with fake securities/ids and redacted account data, so they double as
adapter contract-test inputs.

## 6. ADR-0001 evidence (mcporter: research-only vs runtime adapter)

See `../adr/0001-core-architecture-and-stack.md` (Evidence section). Summary of
what exercising PDT tells us:

- **No PDT capability is reachable only via mcporter.** Every v1 facet is a
  plain MCP tool call returning plain JSON. There is nothing TS-only here that
  would force mcporter into the runtime.
- **The shapes are decode-friendly for Swift.** Money is `{value:String,
  currency:String}`, weights are doubles, dates are ISO-8601. A `Codable`
  layer over the ~15 engine-relevant holding fields is straightforward; the
  only friction is payload size (project to the needed fields) — not type
  complexity.
- **The real work is normalization, not transport.** The valuable, testable
  logic is the `PortfolioDataSource` (joins, FX, freshness, derive raise/cut,
  filter closed) — and it is pure and language-agnostic.

**Conclusion: ADR-0001 is accepted.** The choice is no longer gated by unknown
PDT feasibility; it is a packaging preference. Accepted path: **Option A
(native Swift, mcporter = research/dev tool only)** for a bar-first
single-language app, because (a) nothing in PDT requires a TS runtime and (b)
the shapes decode cleanly in Swift. Option B remains reasonable only if the team
later chooses to reuse this normalization layer as shipped TypeScript.
