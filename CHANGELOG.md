# Changelog

## Unreleased

- Stopped in-flight Claude process trees when background detail refreshes time out or PDTBar quits, with a bounded worker shutdown grace.
- Declined to annualize portfolio returns over periods shorter than 90 days and now explains when the reporting period is too short.
- Fixed invalid PDT income pagination sizes that caused deterministic server rejections and unnecessary Claude CLI retries.
- Prevented background detail retries from multiplying Claude CLI runs, added phase deadlines, and made Data Health report the true run count.
- Bounded PDT list pagination with empty-page termination, 50-page caps, phase deadlines, and Data Health diagnostics for partial results.
- Removed the fixed one-second delay and repeated Claude project scans from inline PDT reads while preserving file-delivered result handling and cleanup.
- Fixed first portfolio fetches discarding completed holdings when an optional PDT facet fails.
- Fixed optional PDT performance reads timing out below observed production latency, which left CAGR and total increase permanently unavailable.
- Fixed a blank allocation-chart panel remaining visible after opening and closing Settings.
- Added a native Settings window with a `Show portfolio values` checkbox that hides displayed monetary portfolio values without deleting cached local data.
- Added a compact portfolio summary above the overview with total value, inception-to-latest total increase, and CAGR annualized from PDT's selected full-period return.
