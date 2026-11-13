---
summary: "Product launch over the PDT connection: connection states, sign-in, pasted token, disconnect, first fetch, cached pulse, and status icon semantics."
read_when:
  - Changing no-argument launch, PDT sign-in, pasted token, reconnect, or disconnect behavior
  - Changing first fetch, cached pulse, or retry behavior
  - Changing status icon semantics
---

# PDT Connection Workflow

The shipped launch flow since #248, which replaced the Claude CLI + PDT MCP flow; #250 removed the remaining Claude code. Decisions: [ADR-0002](adr/0002-pdt-public-rest-api.md). Bram signed off on the auth path and token storage on 2026-11-10 ([#243](https://github.com/BramVR/pdtbar/issues/243)).

## Product launch

No-argument `pdtbar` launch is the user path. It uses isolated app support when `--app-support-dir` or `PDTBAR_APP_SUPPORT_DIR` is supplied; otherwise it uses normal app state. Fixture mode is explicit only:

```bash
pdtbar --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
```

Launch shows `Checking PDT connection`, loads the cached pulse, and only then reads the stored connection. Reading the store can wait on another PDTBar process's token refresh (the store lock), so it runs off the main queue; the cached pulse is already on screen while it waits. Because the check starts after the cached load, a connected result always knows whether a pulse is shown: a returning user gets a background refresh, never a full first fetch.

Launch never opens a browser, a Keychain prompt, or any other prompt. It never starts a process and never falls back to fixtures.

Smokes pass `--scripted-pdt <file>` together with an isolated `--app-support-dir`: an in-memory credential (or the Keychain store over a fake SecItem API), a scripted sign-in, and scripted API replies (`ScriptedPDTConnection`). The flag is refused without an isolated app support directory. For dev live proof, `--pdt-credential-file <file>` runs the same path over the mode-0600 file store `pdtbar-dev pdt-*` uses (see [`smoke-checks.md`](smoke-checks.md)); it also needs an isolated app support directory.

## Connection states

`PDTLaunchState` (`Sources/PDTBarCore/LaunchRuntime.swift`) is what the menu says. Each state lists its rows:

- `checkingConnection`: `Checking PDT connection`. Also shown while a pasted token is saved.
- `notConnected(signInWouldBe: saved | thisSessionOnly)`: `Not connected`, `Sign in with PDT`, `Use a PDT token…`. A cached pulse is not shown. The payload is what the credential store says about a sign-in made now (`PDTCredentialStore.persistence`), read without touching the store. With `saved` the status detail is `PDTBar reads your PDT portfolio read-only`. With `thisSessionOnly` it is `This PDTBar build can't save your sign-in. You'll sign in each time PDTBar starts`, and both sign-in rows stay.
- `connecting`: `Signing in with PDT` (approve in the browser) and `Cancel sign-in`.
- `connected(fetching | failed | current, saved | thisSessionOnly)`: the portfolio sync, and whether the credential outlives this process. `failed` without a pulse shows `Could not fetch portfolio` with the failure and its next action (`PDT rate limit; try again in 2 min`, `Could not reach PDT; check your connection`, `PDT server problem; try again later`), `Try again`, `Disconnect from PDT`. With a pulse, `Disconnect from PDT` joins the Actions section. `thisSessionOnly(missingEntitlement | failed)` means PDT accepted the sign-in or token and the credential store refused to save it ([ADR-0003](adr/0003-credential-storage-and-unsaved-connections.md) decision 3). Every connected screen then carries one `Connection not saved` row (`pdtConnection.notSaved`) beside how PDTBar is connected: in the PDT section without a pulse, and in the Data section after `Data health` (whose Access row reads `Connected, not saved`) with one. It is there while fetching too, when Disconnect is not. Its detail is `This PDTBar build can't save to the Keychain. You stay connected until you quit` for a build without the keychain access entitlement, otherwise `PDTBar could not save it on this Mac. You stay connected until you quit`.
- `needsReconnect(kind, cause)`: `Reconnect to PDT` with the cause (sign-in expired, token expired, access revoked in PDT, no longer accepted, cannot read the portfolio), then `Sign in with PDT`, `Use a PDT token…`, `Check again`, `Disconnect from PDT`.
- `subscriptionPaused`: `PDT access paused` (`403 API_ACCESS_PAUSED`). The token stays stored. `Check again` re-reads the store and fetches again; the fetch decides whether access is back.
- `keychainUnavailable(missingEntitlement | failed)`: `Keychain unavailable` (`This PDTBar build has no Keychain access, so it can't read or remove your PDT connection`) or `Could not read the Keychain`, with `Check again`. The store could not be read, or it refused a disconnect and still holds the credential. PDTBar never retries against the login keychain.
- `disconnecting`: `Disconnecting from PDT`.

Every state except `notConnected` keeps a cached pulse visible, with the connection rows above it and `Refresh now` shown but not clickable until the connection is back.

A build without the keychain access entitlement, such as a local `make start` build, reads the data protection keychain as empty (`errSecItemNotFound`, -25300) and gets `errSecMissingEntitlement` (-34018) on every write (measured on an ad-hoc signed binary, #301). It launches as `notConnected(signInWouldBe: thisSessionOnly(missingEntitlement))`, so the menu says before any sign-in, and again after every relaunch, that this build can't save one. The Keychain store knows that from its own code signature: it reads the `keychain-access-groups` entitlement with `SecTaskCopyValueForEntitlement`, which makes no Keychain call and shows no prompt. The answer never blocks a sign-in and never picks another store. A sign-in or token connects for this session only and fetches like any connection, with the `Connection not saved` row from the moment sign-in returns. The next launch is `notConnected` again. `--pdt-credential-file` is the dev path that survives a relaunch; the file store and the in-memory store always answer `saved`.

Connection actions (`Sign in`, `Use a token`, `Check again`, `Disconnect`) and fetch retries never overlap: the runtime refuses each one while the cached load, another connection operation, a first fetch, or a background refresh runs, and the menu does not offer them then. A stale result (an older connection attempt) is ignored. See `formal/launch-runtime/`.

## Sign-in, token, and disconnect

- `Sign in with PDT` runs `PDTBrowserSignIn` (S256 PKCE, loopback `127.0.0.1:47245`) and stores the session through `PDTConnection.signedIn` before reporting connected. A session the store refuses is used from memory, and the report is connected for this session only. A failure keeps the previous state and adds a `Sign-in failed` row: the port is busy (use a token), the browser could not open, PDT declined, or it timed out. `Cancel sign-in` stops the listener; the menu returns to the stored state.
- `Use a PDT token…` opens a secure text field. The pasted value is parsed by `PDTAPIToken.personal(pasted:)`, stored, and never shown or logged. It is not verified before storing; the first fetch answers.
- `Disconnect from PDT` deletes the stored credential and adds `Remove PDTBar in PDT…`, which opens PDT's connected apps page (browser sign-in) or Integrations (pasted token). PDT has no revoke API for app tokens. The store keeps a record with only the generation in it, so another PDTBar process can see the disconnect.
- A change the store refuses is held and used, never dropped (#301, [ADR-0003](adr/0003-credential-storage-and-unsaved-connections.md) decisions 2 and 3). `PDTConnection` keeps what the store refused (a sign-in, a pasted token, a refreshed pair, a rejection from PDT, or a disconnect) in memory and tries to store it again at the start of every operation, each token hand-out included. Checks and token hand-outs answer from it before the store, so only PDT or `Disconnect from PDT` signs a user out. A held sign-in, token, or refreshed pair is sent to PDT like a stored one, shows `connected(…, thisSessionOnly)`, and is gone when PDTBar quits. A refresh or rejection of a held credential is held behind it. A held rejection shows `needsReconnect`, and the rejected credential is never sent again. A held disconnect drops the credential from use at once and shows `keychainUnavailable` until the delete lands. Only a disconnect that leaves nothing stored shows the `Remove PDTBar in PDT…` row. The retry replays the held events through the connection event table, so a newer sign-in another PDTBar process stored still wins over a held refresh or rejection. A held sign-in, pasted token, or disconnect replaces the stored state instead, so the stored generation guards it: every stored sign-in, pasted token, or disconnect starts a new generation, a held change counts only for the generation it was decided against, and a retry that finds another generation drops the held change and answers from the store. A token entered again starts one too, and a change decided while the store could not be locked or read counts for the generation the first read finds. A held change therefore never brings back a credential another process replaced, disconnected, or saw PDT reject. A refresh or rejection keeps the generation, so a held sign-in still replaces a pair another process has only refreshed, and a held refreshed pair still revives one whose refresh another process saw rejected.

`PDTAppConnection` (`Sources/PDTBarAppSupport/PDTAppConnection.swift`) owns all of this, plus the API client, over one `PDTConnection` per process. It turns store and API errors into connection states: a rejected refresh or token is already stored, or held, as `needsReconnect` by `PDTConnection`, `API_ACCESS_PAUSED` becomes `subscriptionPaused`, `INSUFFICIENT_SCOPE` becomes reconnect with missing read access, and network, `429`, `5xx`, decode failures, and a plain `403` stay connected and retryable while `PDTConnection` still says connected. The same mapping (`failure(for: PDTSyncFailure.Kind)`) runs for a thrown base failure and for the failure that ended an optional phase. Every sync end reports how the credential is kept at that moment: a retryable failure carries it, and a committed first fetch or refresh carries `status(afterSyncEnding:)`. So the `Connection not saved` row appears after a sync whose refreshed pair the store refused, and goes after a sync in which the store took the credential.

## First fetch and returning launch

The first fetch reads holdings only (`PDTAPIDataSource` with `.firstFetch`) through `PDTCoalescedFirstPortfolioFetch`. The snapshot is written to `latest-portfolio-snapshot.json`, the pressure engine runs, and only then is the pulse published. A failed holdings request writes no snapshot and publishes nothing. Right after a successful first fetch, the background detail refresh (`PDTAPIBackgroundDetailRefresh`) fills allocation, X-ray, income, and price history and commits once at the end.

Returning launches show the previous snapshot while the connection check runs, then refresh details in the background. Progress rows (`Filling details`, `Step n/6`) keep the pulse visible. Optional phase failures degrade the refresh (`Details partially filled`, `Fill details again`) and keep last-good facets; a failed base holdings request keeps the pulse and shows `Details fill failed`, or moves to the matching connection state when the connection was the cause. An optional phase that loses access (`401`, `403 INSUFFICIENT_SCOPE`, `403 API_ACCESS_PAUSED`) still commits the fresh holdings, then moves the menu to `Reconnect to PDT` or `PDT access paused` over that pulse (#191). In those two states (`Details partially filled`, `Details fill failed`) `Fill details again` is the only retry: Actions leaves out `Refresh now`, which would start the same refresh.

Data health describes PDT API access (#249). It is hidden while healthy, and while stale or unknown price dates are its only cause, because the Prices row above it already shows them. Otherwise its rows are Source (fetched this session, or a saved copy and its date), Access (`Checking`, `Connected`, `Connected, not saved`, `Reconnect needed:` with the cause, `Paused:`, `Keychain unavailable`, or `Not checked this session` for a saved copy nothing has verified; `Connected, not saved` is not a cause by itself), Cache (last sync, and last complete sync when it differs), Prices, Detail fill, Read state, and Diagnostics. A saved copy is never healthy: the summary reads `Checking` during the connection check, `Refreshing` during a sync, and otherwise names the first cause, in this order: a blocked connection, a failed detail fill, a saved copy or a pulse not fetched this session, an unchecked connection, unknown or stale prices (`2 stale prices`), an incomplete detail fill, a recorded sync failure. Each cause has a row that shows it (`DataHealthAttentionCause.rowID`). A portfolio with no open holdings is not a cause: Prices reads `No holdings to price`.

Diagnostics names the step that failed and what to do: reconnect, renew the subscription, try again in N min after a `429` with `Retry-After`, check the connection, try again later, or update PDTBar. The wait is fixed when the failure is recorded; there is no countdown, and `Fill details again` stays enabled. `Copy diagnostics` copies the step, `GET /v1/<endpoint>`, the failure category with its HTTP status, the request count, and PDT's trace id when it is a UUID or 32 hex digits. It holds no token, account id, query value, date, or response text. A sync that commits no snapshot keeps its failure record in the runtime (`uncommittedSync`) until the next sync starts (#191). Over a pulse, Diagnostics and `Copy diagnostics` stay on the reconnect and paused screens and through `Check again`. A failed first fetch has no pulse and so no Data health; its menu names the failure in the `Could not fetch portfolio` row instead.

## Status icon

The menu bar always shows the Concentration Stack icon. It is a stable portfolio mark, not top-three holdings and not a mini dashboard:

- bar heights: middle bar is always max height; side bars show X-ray look-through concentration shoulders
- missing X-ray data: deterministic default silhouette with left half-height and right two-thirds height
- filled bars: ranked attention item count, capped at three
- zero attention: no filled bars
- no separate round notification dot
- connection, stale, and fetch-failed states: tooltip/menu copy and whole-icon dimming only

Full status copy remains in tooltip, accessibility label, and the first menu row.

## Redaction and proof

Public docs and proof may include command names, row text, counts, durations, scenario booleans, fixture names, and redacted status. They must not include private portfolio data, tokens, account identifiers, raw live payloads, or holding names and values from live data. Tests and smokes never use real credentials, the real Keychain, or live PDT portfolio reads.
