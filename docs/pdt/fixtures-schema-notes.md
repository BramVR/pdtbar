---
summary: "Observed PDT raw tool schemas and field notes for fixture and adapter contracts."
read_when:
  - Updating PDT fixture shapes
  - Decoding raw PDT tool responses
  - Auditing adapter field mappings
---

# PDT raw tool schemas (observed 2026-06-22)

Field names/types as returned live by the PDT MCP. Values here are illustrative
and sanitized. This is the reference the fixtures and the `PortfolioDataSource`
adapter are built against.

## pdt-get-portfolio-holdings → `{ holdings: [...] }`

~90 fields per holding. Engine-relevant subset (full list omitted for brevity):

```
symbolName            String            // e.g. "Nova Lithography"; "Cash" for cash
isin                  String|null
symbolQuoteId         Int               // join key: dividends, symbol-prices, symbol-quote
currentPrice          Money             // TRADING currency (GBX/DKK/USD/EUR...)
currentPriceLocal     Money             // PORTFOLIO currency (EUR)
currentPriceDate      ISODateTime       // per-holding price freshness
currentExchangeRate   Number            // trading->portfolio (e.g. 86.665 for GBX)
currentExchangeRateDate ISODateTime
currentWorth          Money             // trading currency
currentWorthLocal     Money             // portfolio currency
portfolioWeight       Number            // FRACTION (0.1567 == 15.67%)
portfolioWeightRelative Number
unrealisedGains       Money
unrealisedGainsPercentage Number        // FRACTION
dividendsReceived     Money
brokers               [Int]             // broker ids
corporateActions      [..]
startsAt              ISODateTime|null
closedAt              ISODateTime|null  // non-null => closed; currentWorth == 0
periods               [..]
```
Plus full realised/unrealised/total bought/sold cost-basis blocks, dividend
tax/exchange-rate breakdowns, and `*Local` variants. ~195 KB total — exceeds one
MCP result window; project to the needed fields.

## pdt-get-portfolio → `{ holdings: [...], summary: {...} }`
Same holdings array + a `summary` with `currentWorth`, `cash`,
`unrealised/realised/total Gains{,Product,ExchangeRate}`, `dividendsReceived`,
`dividendsTax`, `transactionsCosts/Taxes`, `totalBooked`, `totalBought/SoldShares`.
All as Money objects (currency EUR). No top-level as-of date. Accepts `date=` for
a historical snapshot.

## pdt-get-portfolio-distributions → category breakdowns (no date field)
Keys: `sectors, industries, industryGroups, countries, continents, currencies,
assetTypes, marketCapitalizations, exchanges, brokers, strategies`.
Each entry: `{ categoryName: String, totalValue: Money, percentage: Number /*0–100*/ }`.
Note: `percentage` here is 0–100, unlike holding `portfolioWeight` which is a fraction.

## pdt-list-calendar-events → `{ data: [...], meta }`
```
id          Int
date        "YYYY-MM-DD"
type        ex-dividend | payment-dividend | earnings-release | earnings-call |
            shareholder-meeting | investor-day | economic | no-events-today | ...
isEstimated Bool
symbolId    Int|null       // join key (NOT symbolQuoteId); null for no-event sentinels
symbolName  String|null    // null for no-event sentinels
```

## pdt-list-dividends → `{ data: [...], meta }`
```
id, date(ISODateTime), description(null), lastModifiedAt(null),
amount Money, tax Money, exchangeRate String,
symbolId(null in live data), symbolQuoteId Int,
importId, userId, brokerId Int,
source "import", sourceIdentifier "<broker>-account-csv", sourceVersion Int,
externalId(null), createdAt, updatedAt
```
Corrections appear as +/− amount pairs. No per-share rate, no raise/cut flag.

## pdt-list-symbol-prices → `{ data: [...] }` (newest-first)
```
id Int, date "YYYY-MM-DD",
close String, closeAdjusted String (split-safe), closeCurrency String,
symbolQuoteId Int
```

## pdt-list-corporate-actions → `{ data: [...], meta }`
```
id, type: stock_split | isin_change | exchange_change,
date, symbolId,
details: { in, out, newSymbolId } (split) | { newSymbolId } (isin change),
createdAt, updatedAt
```

## pdt-get-symbol-quote → resolves the join
```
id Int (== symbolQuoteId), code String (ticker), symbolId Int,
exchangeId, exchangeName, currencyId, currencyCode
```

## pdt-get-user-profile → ACCOUNT PII (never put in fixtures)
`id, firstname, lastname, email, locale, timezone, currency, emailVerified,
twoFactorEnabled, createdAt`. Redacted everywhere.

## pdt-list-portfolios → `{ data: [{holdings:[], summary:{...}}], meta }`
Summary-only; in live data `holdings` was empty and summary fields were
zeroed/stale (see gap #4 in portfolio-data-source.md). Use `pdt-get-portfolio?date=`
for historical holdings instead.
