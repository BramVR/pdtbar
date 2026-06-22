# Issue 6 proof

- Scope: freshness and no-advice copy gates on the fixture-backed Allocation Pulse path.
- Model proof: `AllocationFacetChecks` covers current and stale EOD freshness facts derived from PDT freshness dates.
- Render proof: `PulseFixtureChecks` covers cold-start quiet, active pressure, model-driven stale rendering, and v1 no-advice copy scan.
- No durable history store added; no live PDT auth or external calls added.
