---
summary: "Architecture overview: modules, entry points, data flow, and boundaries."
read_when:
  - Reviewing architecture before feature work
  - Refactoring modules, app lifecycle, or data flow
  - Changing engine/bar boundaries
---

# Architecture

## Modules

- `Sources/PDTBarCore`: normalized portfolio model, pressure engine, fixture/live data sources, menu descriptor rendering.
- `Sources/PDTBarAppSupport`: shared AppKit-adjacent support used by the app, smoke runner, and tests for app state, status visuals, menu actions, status-item menu hosting, scripted launch seams, and local Claude/PDT connection handling.
- `Sources/PDTBarApp`: AppKit status item, Claude-first readiness probe, first fetch, cached pulse, menu actions.
- `Sources/PDTBarDev`: command-line model and descriptor inspection.
- `Sources/PDTBarSmoke`: scripted, packaged, Accessibility, manual Claude, and live PDT smoke checks.
- `Sources/PDTBarChecks`: deterministic invariant checks.

## Entry Points

- `pdtbar`: product menu-bar app.
- `pdtbar-dev`: developer fixture/model inspection.
- `pdtbar-smoke`: smoke proof runner.
- `pdtbar-checks`: deterministic checks.

## Data Flow

Claude/PDT readiness probe -> `PortfolioDataSource` -> normalized `PortfolioSnapshot` -> `SnapshotStore` -> pressure engine + Data Health -> `PortfolioPulseModel` -> `MenuDescriptor` -> `PDTBarAppSupport` action/status helpers -> AppKit menu/status item.

`PressureRunner` is the Pulse lifecycle seam for cached snapshots, first fetches,
and refreshed snapshots: it loads prior state, computes pressure, applies/reset
read state, commits snapshot metadata when needed, and returns the rendered
descriptor as one `PulseLifecycleResult`. `SnapshotStore.commitCurrentSnapshot`
removes the read marks of concentration items that cross back above the
threshold against the snapshot it replaces before it writes, so a quit between
the two writes cannot record a crossing whose old read mark is still stored.

`PDTLaunchRuntime` is the scripted no-argument launch seam for readiness,
cached-pulse display, first-fetch success/failure, returning-launch background
detail refresh progress/completion/failure, retry gating, and descriptor updates.
The AppKit delegate renders runtime descriptors, forwards menu actions, and
performs platform lifecycle work such as timers, async process calls, and
status-item installation.

`ClaudeLocalConnection` is the local Claude/PDT connection seam for real product
launches: readiness, login handoff process handling, MCP list parsing,
ToolSearch resolution, PDT read-tool calls, retry classification, read-only
allowlists, and Claude tool-result parsing flow through app support instead of
the AppKit delegate.

`PDTAPIClient` is the read-only PDT REST transport (#244, ADR-0002), not yet
wired into launch: an allowlisted `PDTAPIResource` enum (every case a `GET` to
`https://api.portfoliodividendtracker.com/v1`), an injected token provider
(Keychain in production, in-memory in tests), typed `PDTAPIError`s from PDT's
error envelope, bounded retries for 429/5xx/transient transport failures with
`Retry-After`, page and offset pagination with stall and page-cap guards, and no
response logging. `URLSessionPDTHTTPTransport` refuses redirects so the bearer
token never leaves the PDT origin. `getReportingAttempts` and
`getAllReportingAttempts` also return how many requests a call sent, retries
and pages included, and throw `PDTAPIRequestFailure` with that count, so
refresh diagnostics persist real attempt counts.

`PDTConnection` (#245) is the PDT credential layer, not yet wired into the
app (#248). The stored value is `PDTConnectionState`: `disconnected`,
`connected(PDTCredential)` (a browser session or a pasted personal token), or
`needsReconnect(kind, reason)`, and `PDTConnectionState.applying` holds every
transition. `PDTConnection` is the API client's token provider: it re-reads
the store on each call, refreshes the browser session shortly before expiry or
on `401 TOKEN_INVALID` while holding the store's exclusive access (an in-process
lock, or `flock` on a lock file for the file and Keychain stores) from load
through the token endpoint to save, writes the rotated pair before returning
it, keeps a pair the store refused until it is stored or a sign-in, pasted
token, or disconnect is stored in its place, backs off after a refresh that
got no answer, and moves to `needsReconnect` on `invalid_grant`. That state
names the rejected refresh token by SHA-256, so only a refresh of that pair
reconnects it.
`PDTBrowserSignIn` runs S256 PKCE with a random `state`, opens the injected
browser, and waits on a `127.0.0.1:47245` loopback listener for the callback
that carries that `state`; other requests get an error page. Stores are
`InMemoryPDTCredentialStore` (tests, smokes), `FilePDTCredentialStore` (dev
proof, mode 0600, sibling `.lock`), and `KeychainPDTCredentialStore` in app
support (production, lock file in a given directory). Tokens print only as
redacted descriptions or SHA-256 fingerprints.

`PDTAPIDataSource` (#246) is the `PortfolioDataSource` over that client, also not
yet wired in: it decodes REST envelopes into the existing normalization inputs,
requires holdings, and degrades the snapshot when an optional facet fails.

`PDTAPIBackgroundDetailRefresh` (#247) is the background detail refresh over the
same client. It shares `PDTBackgroundDetailRefreshResult` and the
`PDTBackgroundDetailRefreshing` seam with the Claude refresh, which stays the
shipped path until a PDT token source exists (#245, #248). Phases run in order
with no tool discovery and no per-holding lookups: holdings carry `symbolId`
for the income join, and prices come from `prices/batch` in chunks of 50. Every
phase fills one in-memory snapshot. The store is written once, by
`PressureRunner.refreshedPulse`, so a cancel (quit, account switch) or a failed
required base leaves the last good snapshot on disk. A failed optional phase
keeps the prior facet and degrades the outcome. An auth or setup outage skips
every later phase, price batches included. Performance is reported unavailable
until the REST performance shapes are mapped. The app runs it only for scripted
`scripted-pdt-api.json` replays today.

`DataHealth` composes runtime/source facts into model state: Claude/PDT
readiness, required read tools, read-only policy, cache/source, detail-fill,
freshness, read-state, and redacted diagnostics. Menu descriptors render this
state; AppKit does not derive health facts. Source facts follow the pulse
source: live fetches claim verified readiness/tools/policy, cached snapshots
claim nothing until the launch flow's last-known readiness is applied on
republish, and cached-pulse freshness is evaluated against the current day
rather than only the snapshot's own asOf.

Live and fixture PDT decoders both feed PDT-shaped DTO inputs into
`PDTSnapshotNormalizer`, so holding filtering, symbol quote joins, dividend
correction handling, optional facets, price history, and fixture/live parity
stay in one core normalization path. Fixture mode uses the same engine/render
path but is explicit developer tooling.

## Boundaries

- Engine computes pressure. Bar renders descriptors.
- App support holds reusable AppKit-adjacent glue; it is not a second engine.
- Launch runtime owns setup, retry, cached-pulse display, and background detail refresh state; Bar forwards menu actions.
- `ClaudeLocalConnection` owns local Claude CLI process/result handling; AppKit chooses when to start work and renders descriptors.
- PDT/MCP adapters normalize raw shapes before engine logic sees them.
- Financial data stays local; public proof is sanitized.

See also: [`claude-login-workflow.md`](claude-login-workflow.md), [`pdt/portfolio-data-source.md`](pdt/portfolio-data-source.md), [`reuse-notes.md`](reuse-notes.md).
