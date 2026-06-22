# Issue 3 Proof

PDT contract ingestion is fixture-backed only. No live PDT credentials or private portfolio data used.

Local proof:

```bash
swift run PDTContractChecks
swift test
swift build
swift run PulseFixtureChecks
```

Covered contract facts:
- Money objects parse as `Money(decimal:currency:)`; bare-number `currentWorth` is rejected.
- Holdings with `currentWorth.value = "0.00"` are excluded from live holdings.
- `portfolioWeight` stays fractional; `0.1557` exposes `15.57` percent.
- Portfolio and holding EOD date fields emit freshness facts.
