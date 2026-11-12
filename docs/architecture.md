---
summary: "Architecture overview: modules, entry points, data flow, and boundaries."
read_when:
  - Reviewing architecture before feature work
  - Refactoring modules, app lifecycle, or data flow
  - Changing engine/bar boundaries
---

# Architecture

## Modules

- `Sources/PDTBarCore`: normalized portfolio model, pressure engine, fixture and PDT API data sources, menu descriptor rendering.
- `Sources/PDTBarAppSupport`: shared AppKit-adjacent support used by the app, smoke runner, and tests for app state, status visuals, menu actions, status-item menu hosting, and the PDT connection seam (`PDTAppConnection`, Keychain store).
- `Sources/PDTBarApp`: AppKit status item, PDT connection check and sign-in, first fetch, cached pulse, menu actions.
- `Sources/PDTBarDev`: command-line model and descriptor inspection.
- `Sources/PDTBarSmoke`: scripted, packaged, and Accessibility smoke checks, and the sandboxed scripted API matrix.
- `Sources/PDTBarSmokeProof`: the pure check that decides whether a scripted app launch proved its fetch or refresh (`ScriptedLaunchEvidence`), shared by the smoke runner and tests.
- `Sources/PDTBarChecks`: deterministic invariant checks.

## Entry Points

- `pdtbar`: product menu-bar app.
- `pdtbar-dev`: developer fixture/model inspection.
- `pdtbar-smoke`: smoke proof runner.
- `pdtbar-checks`: deterministic checks.

## Data Flow

PDT connection check -> `PDTAPIDataSource` -> normalized `PortfolioSnapshot` -> `SnapshotStore` -> pressure engine + Data Health -> `PortfolioPulseModel` -> `MenuDescriptor` -> `PDTBarAppSupport` action/status helpers -> AppKit menu/status item.

`PressureRunner` is the Pulse lifecycle seam for cached snapshots, first fetches,
and refreshed snapshots: it loads prior state, computes pressure, applies/reset
read state, commits snapshot metadata when needed, and returns the rendered
descriptor as one `PulseLifecycleResult`. `SnapshotStore.commitCurrentSnapshot`
removes the read marks of concentration items that cross back above the
threshold against the snapshot it replaces before it writes, so a quit between
the two writes cannot record a crossing whose old read mark is still stored.

`PDTLaunchRuntime` is the no-argument launch state machine: cached-pulse load,
then the PDT connection check, sign-in, pasted token, disconnect, first-fetch
success/failure, returning-launch background detail refresh, retry gating, and
descriptor updates. Its state is `PDTLaunchState` (checking, not connected,
connecting, connected with a sync phase and whether the credential is saved or
kept for this session only, needs reconnect with a cause, subscription paused,
Keychain unavailable, disconnecting). Work never overlaps.
`PDTAppConnection` is the app's one PDT connection (Keychain store, browser
sign-in, URLSession, or an offline `--scripted-pdt` script for smokes) and the
one place store and API errors become connection states. See
[`pdt-connection-workflow.md`](pdt-connection-workflow.md).
The AppKit delegate renders runtime descriptors, forwards menu actions, and
performs platform lifecycle work such as timers, background work, and
status-item installation. Product code starts no process; `pdtbar-checks`
fails on any process start or Claude/MCP mention in the three product targets.

`PDTAPIClient` is the read-only PDT REST transport (#244, ADR-0002): an allowlisted `PDTAPIResource` enum (every case a `GET` to
`https://api.portfoliodividendtracker.com/v1`), an injected token provider
(Keychain in production, in-memory in tests), typed `PDTAPIError`s from PDT's
error envelope, bounded retries for 429/5xx/transient transport failures with
`Retry-After`, page and offset pagination with stall and page-cap guards, and no
response logging. `URLSessionPDTHTTPTransport` refuses redirects so the bearer
token never leaves the PDT origin. `getReportingAttempts` and
`getAllReportingAttempts` also return how many requests a call sent, retries
and pages included, and throw `PDTAPIRequestFailure` with that count, so a
stored sync failure names the real request count. The failure also carries the
trace id of the response that failed the call (`X-Request-Id`, else
`error.traceId`), kept only when it is a canonical UUID or 32 hex digits
(`PDTTraceID`).

`PDTConnection` (#245) is the PDT credential layer; the app holds one per
store through `PDTAppConnection` (#248). The stored value is `PDTStoredConnection`: a
`PDTConnectionState` and a generation. The state is `disconnected`,
`connected(PDTCredential)` (a browser session or a pasted personal token), or
`needsReconnect(kind, reason)`, and `PDTConnectionState.applying` holds every
transition. The generation counts the sign-ins, pasted tokens, and disconnects
that replaced what was stored. `PDTConnection` is the API client's token provider: it re-reads
the store on each call, refreshes the browser session shortly before expiry or
on `401 TOKEN_INVALID` while holding the store's exclusive access (an in-process
lock, or `flock` on a lock file for the file and Keychain stores) from load
through the token endpoint to save, writes the rotated pair before returning
it when the store accepts it, uses a sign-in, token, or pair the store refused
from memory and tries the save again on every later operation (ADR-0003
decision 3), drops that held change once the stored generation shows another
process has replaced the connection since, backs off after a refresh that
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

`PDTAPIDataSource` (#246) is the `PortfolioDataSource` over that client and the
app's first fetch (#248): it decodes REST envelopes into the existing normalization inputs,
requires holdings, and degrades the snapshot when an optional facet fails.

`PDTAPIBackgroundDetailRefresh` (#247) is the background detail refresh over the
same client and the app's refresh since #248. Phases run in order
with no tool discovery and no per-holding lookups: holdings carry `symbolId`
for the income join, and prices come from `prices/batch` in chunks of 50. Every
phase fills one in-memory snapshot. The store is written once, by
`PressureRunner.refreshedPulse`, so a cancel (quit, account switch) or a failed
required base leaves the last good snapshot on disk. A failed optional phase
keeps the prior facet and degrades the outcome. A failure that ends the sync
skips every later phase, price batches included: lost access (`401`, `403`, an
unreadable credential store) or a `429` that outlasts the client's own retries
(`PDTSyncFailure.Kind.endsSync`). Performance is reported unavailable until the
REST performance shapes are mapped.

`PDTSyncFailure` (`Sources/PDTBarCore/PDTSyncFailure.swift`) is why one PDT
request of a sync failed: the phase, the `PDTAPIEndpoint`, a `Kind`, the
request count, and an optional `PDTTraceID`. `Kind.init` is one exhaustive
switch over `PDTAPIError` with no `default`. Every stored property is a closed
enum, an Int, or a validated trace id, and no initializer takes text, so a
token, account id, URL, or response body cannot be stored, shown, or copied.
`DataHealthRedactionTests` holds that line with a `Mirror` walk and planted
secrets. The last failure is persisted as `latest-sync-failure.json`
(`SnapshotStore.lastSyncFailure`); an unreadable or foreign file is no failure.
A `latest-detail-refresh-diagnostic.json` left by a build before #250 is never
read.

`DataHealth` (`Sources/PDTBarCore/FreshnessHealth.swift`) reports PDT API
access as separate facts, one row each in the Data health submenu:

- Source: PDT, read-only, and whether the pulse was fetched this session or is
  a saved copy.
- Access: the connection, from `PDTLaunchState` (`DataHealthAccess`).
- Cache: the last sync (`asOf` of the committed snapshot) and, when it differs,
  the last sync that filled every detail.
- Prices: price freshness, judged against the current day for a saved copy.
- Detail fill, Read state, and Diagnostics: the last `PDTSyncFailure` with what
  to do about it, plus `Copy diagnostics`.

Each fact has one writer. The pulse owns source, cache, prices, read state, and
the detail fill and failure of the sync that built it (`DataHealth.build`). The
running app owns access and live sync activity, and
`DataHealth.snapshot(_:in:)` merges those onto the pulse's health.
`PDTLaunchRuntime.descriptor()` is the only caller in the app, through
`PulseLifecycleResult.descriptor(in:)`, so every screen that keeps a pulse
(refresh progress, failure, reconnect, paused, Keychain) shows the same health.
The merge cannot write source, cache, or prices, so a failed refresh moves no
date. A saved copy is never `healthy`, so a pulse from disk cannot look freshly
fetched. Menu descriptors render this state; AppKit does not derive health
facts. `FacetSnapshots` rebuilds `dataHealth` when the stored shape is not this
one, so model JSON from an older build still decodes.

Live and fixture PDT decoders both feed PDT-shaped DTO inputs into
`PDTSnapshotNormalizer`, so holding filtering, symbol quote joins, dividend
correction handling, optional facets, price history, and fixture/live parity
stay in one core normalization path. Fixture mode uses the same engine/render
path but is explicit developer tooling.

## Boundaries

- Engine computes pressure. Bar renders descriptors.
- App support holds reusable AppKit-adjacent glue; it is not a second engine.
- Launch runtime owns setup, retry, cached-pulse display, and background detail refresh state; Bar forwards menu actions.
- `PDTAppConnection` owns the credential, sign-in, and error-to-state mapping; AppKit chooses when to start work and renders descriptors.
- PDT API and fixture adapters normalize raw shapes before engine logic sees them.
- Financial data stays local; public proof is sanitized.

See also: [`pdt-connection-workflow.md`](pdt-connection-workflow.md), [`pdt/portfolio-data-source.md`](pdt/portfolio-data-source.md), [`reuse-notes.md`](reuse-notes.md).
