# Issue 4 Proof

Allocation pressure is fixture-backed only. No live PDT credentials or private portfolio data used.

Local proof:

```bash
swift run AllocationFacetChecks
swift run PDTContractChecks
swift test
swift build
swift run PulseFixtureChecks
```

Covered model facts:
- Open holdings at or above 20% emit Allocation concentration attention.
- Multiple concentration items rank by `portfolioWeight`, then stable ticker fallback.
- Allocation attention items expose ranking inputs and threshold facts.
- Allocation snapshots emit `activePressure` or `allQuiet` with holding weights.
- PDT-shaped closed zero-worth holdings never create Allocation pressure.
