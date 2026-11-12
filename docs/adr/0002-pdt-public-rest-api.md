---
summary: "Accepted decision: read PDT through its public REST API with browser sign-in (main) or a pasted read-only token (fallback); retire the Claude CLI + PDT MCP path."
read_when:
  - Changing how PDTBar connects to or authenticates with PDT
  - Adding PDT REST requests, token storage, or sign-in/disconnect behavior
  - Writing setup, reconnect, or Data Health copy about PDT access
  - Removing or touching the Claude CLI + PDT MCP path
---

# ADR-0002: Adopt the PDT public REST API

- **Status:** Accepted. #250 removed the Claude CLI + PDT MCP path (decision 9).
- **Date:** 2026-11-09
- **Deciders:** Bram
- **Supersedes:** the Claude-only connection model in `docs/claude-login-workflow.md`, `docs/product-brief.md`, and `docs/v1-scope.md`. ADR-0001 (native Swift, engine/bar separation) still holds.
- **Sign-off:** [#252 decisions](https://github.com/BramVR/pdtbar/issues/252#issuecomment-6733477391), [#245 long-lived connection](https://github.com/BramVR/pdtbar/issues/245#issuecomment-6733711618). Tracking: [#243](https://github.com/BramVR/pdtbar/issues/243).

## Context

PDTBar reads PDT by running the signed-in Claude CLI, which calls the PDT MCP server one tool at a time (`Sources/PDTBarAppSupport/ClaudeLocalConnection.swift`). Every read is a full Claude CLI run with an LLM round trip and stream-json parsing. Portfolio data passes through an Anthropic-hosted Claude session on its way to PDTBar.

PDT now publishes a REST API (`https://api.portfoliodividendtracker.com/v1`, docs v0.8.1) that serves the same data over HTTPS with a bearer token. `VISION.md` puts new data sources, token handling, and privacy-impacting behavior under **Needs Sign-Off**. Bram signed off on 2026-11-09.

## Decision

1. **Data source.** The PDT REST API replaces the Claude CLI + PDT MCP path as the product data source. PDTBar sends only `GET` requests to an explicit allowlist of read endpoints. It never calls a PDT write endpoint. OAuth registration and token requests are authentication operations, not portfolio writes.
2. **Main path: browser sign-in.** OAuth 2 Authorization Code with S256 PKCE, opened in the user's browser. The loopback listener answers a request without this sign-in's `state`, or with a repeated parameter, with an error page and keeps waiting, so only PDT's redirect, the timeout, or a cancel ends the sign-in. PDTBar is the registered public PDT app "pdtbar": `client_id` `01a1c518-271d-73cb-b279-9d2207283ce2`, no client secret, shipped in the code. The redirect is the fixed loopback `http://127.0.0.1:47245/callback` (Bram's decision). PDT matches a registered redirect exactly and apps cannot be edited, so the port is fixed and a busy port is a typed sign-in error. No custom URL scheme, no dynamic client registration (it only grants `mcp:use`), and no discovery: the authorize and token endpoints on `auth.portfoliodividendtracker.com` are hardcoded. PDTBar requests the `read` scope only, never `write` or `mcp:use`, and sends an explicit `User-Agent` (`pdtbar/<version>`).
3. **Long-lived connection.** Access tokens last one hour. PDTBar refreshes shortly before expiry and on any `401 TOKEN_INVALID`, with one refresh in flight at a time. Each refresh rotates both tokens and revokes the previous access token at once, so callers re-read the token after a refresh, and the rotated pair is stored before it is used when the store accepts it; otherwise it is used from memory, retried on every later operation, and lost on quit (reworded by ADR-0003 decision 3, which waits for sign-off; before it, a pair the store refused was never used). The credential store is a mutex held from load through the token endpoint to save, across every PDTBar process that shares it, so two processes never refresh the same pair. A refresh PDT accepted wins over a concurrent `invalid_grant` for the pair it rotated, and only for that pair: the reconnect state names the rejected refresh token by SHA-256. A rotated pair the store refused is kept in memory and offered to the store again before every later token hand-out, until a sign-in, pasted token, or disconnect takes its place (ADR-0003 decision 2 holds every refused change this way). A refresh that fails without an answer (timeout, `429`, `5xx`) is not retried before `Retry-After` or a backoff from 5 s doubling to 60 s has passed; callers in that window share the failure. `invalid_grant` from the token endpoint moves the connection to a reconnect state. The user should not have to sign in again while PDTBar keeps running at least once inside PDT's refresh window.
4. **Fallback: pasted personal access token.** The user creates a read-only token in PDT under Integrations > API and pastes it once. Setup copy recommends the `read` scope and lets the user pick `1_year` or `never` expiry. These tokens cannot be refreshed. PDTBar can read their `scopes`, `status`, and `expiresAt` from `GET /v1/personal-access-tokens` by matching `tokenHint` (the last 8 characters).
5. **Read-only only.** Both paths are read-only. A `read` token makes PDT enforce it too: write endpoints answer `403 INSUFFICIENT_SCOPE`.
6. **Token storage.** One Keychain item scoped to PDTBar in the data protection keychain (`kSecUseDataProtectionKeychain`), `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never syncs through iCloud Keychain and never restores onto another Mac. Without the data protection keychain, macOS puts the item in the legacy login keychain and ignores the accessibility class. Tokens never appear in Application Support files, snapshots, logs, diagnostics, Data Health copy, or proof artifacts. Tests and smokes use an in-memory store and never touch the Keychain. Dev live proof (`pdtbar-dev pdt-*`) uses an explicit mode-0600 file store instead, because a re-signed dev build would prompt for the Keychain item. The Keychain has no cross-process mutex, so the Keychain store takes a PDTBar-owned directory and holds `pdt-connection.lock` there with `flock`; the file store locks a sibling `<name>.lock`. Lock files hold no secret.
7. **Disconnect.** `Disconnect` deletes the stored credential. PDT has no API revoke for app tokens, so its copy points to PDT's connected apps page (`https://app.portfoliodividendtracker.com/account/integrations/authorizations`), or to Integrations for a pasted token, for revoking on PDT's side.
8. **Expiry is never silent.** Data Health shows the token expiry date and warns on `expiring_soon` (within 14 days). `401 TOKEN_INVALID` (`details.reason` = `invalid`, `expired`, or `revoked`) moves the menu to a reconnect state and keeps the cached pulse visible. `403 API_ACCESS_PAUSED` (subscription ended) is its own state; the token stays valid.
9. **Claude/MCP path: deleted.** #250 removes it in one wave once the REST path reaches parity. No hidden fallback and no user toggle. Until then the Claude path stays the shipped behavior.
10. **Copy rules.** Visible menu copy may say "token" (setup and expiry need it). It still never says `codex`, `oauth`, `api key`, `fixture`, or `mcporter`, and never echoes a token value (`pdt_…`). Users see "Sign in with PDT", not "OAuth".

## Privacy

Portfolio data now flows PDT → PDTBar directly. No LLM sees the payload, which is a privacy improvement over the Claude path. PDTBar holds one more secret (the token), kept on this device only.

## Live findings (2026-11-09)

From [#243 tested answers](https://github.com/BramVR/pdtbar/issues/243#issuecomment-6733678312): public OAuth endpoints plus GET-only calls with Bram's read-only token. Only shapes and counts were recorded.

- **Redirect.** `pdtbar://oauth/callback` is rejected at registration (`400 invalid_redirect_uri`). `http://127.0.0.1:53682/callback` registers (`201`), and authorize accepts the same client on another port. An unregistered host gets `401 invalid_client`.
- **Scope.** `scope=read` passes authorize validation; an unknown scope gets `invalid_scope`. Registration reports `scope: mcp:use`. Bram's personal token lists `scopes: ["read"]`.
- **Registration.** Dynamic registration works without authentication. Superseded on 2026-11-10: it only grants `mcp:use`.
- **`/portfolios`.** Fixed: every row has a non-zero `summary.currentWorth`. Rows carry only `date` and `summary`; historical holdings still come from `/portfolio/holdings?date=`.
- **Calendar.** All upcoming dividend events carry per-share `dividend.amount`; some are `isEstimated`.
- **Versioning.** No version header. Responses carry `X-RateLimit-Limit` (1000), `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `X-Request-Id`.
- **Envelopes.** Holdings return `{data: [...]}` with no `meta`. Paged lists return `{data, meta, links}` with camelCase `meta` (`currentPage`, `lastPage`, `perPage`, `total`). X-ray uses `limit`/`offset` and returns `{data: {items, hasMore, totalCount, …}}`. Errors use `{error: {code, message, details, traceId}}`.
- **Identity.** All holdings carry `symbolId`; nearly all carry `isin`. `/me` returns `portfolioCurrency`.

## Live findings (2026-11-10)

From [#245 sign-in test results](https://github.com/BramVR/pdtbar/issues/245#issuecomment-6765213724): one real PKCE sign-in on Bram's account with scope `read`, docs `llms.txt`/`llms-full.txt`/`openapi.json` v0.9.0, and the developer guide at `https://build.portfoliodividendtracker.com/llms-full.txt`. Only shapes, statuses, SHA-256 prefixes, and lengths were recorded.

- **Registration.** Dynamic registration grants only `mcp:use`; authorize with `scope=read` answers `invalid_scope` and points to build.portfoliodividendtracker.com. A registered public app is required, so PDTBar ships the fixed "pdtbar" `client_id`. Apps cannot be edited after registration (1 to 10 redirect URIs, matched exactly), and stay unverified, with a warning on the consent screen, until PDT support verifies them.
- **Discovery.** Lives on `mcp.portfoliodividendtracker.com` and lists only `mcp:use`, so the app endpoints are hardcoded.
- **Redirect back and consent.** PDT redirects back to the loopback listener after consent. The consent screen asks to read portfolio data only, and connected apps then lists the app as read only. `pdtbar://` stays rejected.
- **Tokens.** The code exchange returns `access_token`, `expires_in` (3600), `refresh_token`, and `token_type` (`Bearer`), with no `scope` and no refresh lifetime.
- **Refresh.** Refresh rotates the refresh token and immediately revokes the previous access token (`401 TOKEN_INVALID`, `details.reason: revoked`). Reusing an old refresh token answers `400 invalid_grant` and leaves the live chain working.
- **Revoke.** `/oauth/revoke` answers `405`; `/v1/authorizations` answers `403` to app tokens. Revoking happens in PDT's connected apps page.
- **Cloudflare.** Default user agents such as `Python-urllib` get `403` (error 1010).
- **Token endpoint.** Allows 60 requests per minute per `client_id`.

## Open risks

- **Refresh window reset.** Refresh tokens last 30 days. Unknown whether each refresh restarts that window; the developer guide does not say. If it does not, the main path needs a fresh sign-in every 30 days. Needs PDT's answer or a 30-day wait.
- **Loopback for a verified app.** The developer guide allows `http://localhost` and `http://127.0.0.1` redirects "for development". Ask PDT before verification whether a production app may keep its loopback redirect.
- **Fixed port.** Only port 47245 is registered, so another app holding it blocks sign-in until it is free; the pasted token is the way around it.
- **Write-scope labels.** OpenAPI write-scope metadata looks inconsistent. Not blocking: the client is GET-only and never relies on those labels.
- **Leftover test clients.** "PDTBar redirect test" (DCR) and an anonymous DCR client were left on PDT with no grants; the API cannot delete DCR clients. The unverified "pdtbar probe" app was deleted on 2026-11-10.
- **One connection per store.** The refresh backoff lives in the `PDTConnection` instance, not in the store. The store lock serializes refreshes across processes but does not share a cooldown, so a second process on the same store (in practice only `pdtbar-dev` beside the app) can refresh again inside another process's `Retry-After` window. The app must create one `PDTConnection` per store; persisting the cooldown was judged not worth a larger persisted format for a dev-only case.
- **Keychain entitlement.** The data protection keychain needs the signed app's keychain access entitlement. Measured on an ad-hoc signed binary (#301): an unentitled build reads the item as missing (`errSecItemNotFound`, -25300) and gets `errSecMissingEntitlement` (-34018) on add, update, and delete. So it launches as `Not connected`, not `Keychain unavailable`, and a sign-in or token it cannot save is used from memory until PDTBar quits and shown as `Connection not saved` (ADR-0003 decision 3). #248 maps -34018 to a typed `missingKeychainEntitlement` error, and on a read to the `Keychain unavailable` menu state, never a login-keychain fallback (proven with a fake SecItem API). `Scripts/package_app.sh` signs a `keychain-access-groups` entitlement (`Scripts/PDTBar.entitlements.template`) when `PDTBAR_PROVISIONING_PROFILE` names a Developer ID provisioning profile, and a notarized release refuses to build without one. Still open: create that profile (secret `PDTBAR_PROVISIONING_PROFILE_BASE64`) and prove a real Keychain write on the packaged, notarized app.
- **Shared token limit.** The 60 requests per minute on the token endpoint is per `client_id`, and every PDTBar install shares the one registered client. Hourly refreshes stay far below it for a small user base, but a fleet-wide retry storm would hit it. Revisit before a wide release (jitter on refresh timing, or ask PDT about the limit).

## Options considered

- **Token paste only.** No client registration, redirect, or refresh logic. Rejected as the main path: every user has to create and manage a token, and PDT recommends OAuth for production integrations.
- **OAuth only.** Best onboarding. Rejected as the only path: it depends on the open risks above. The fallback lets users connect while those are settled.
- **Keep Claude/MCP as a hidden fallback.** Rejected: two runtime paths to maintain, and the Claude path keeps routing portfolio data through an LLM session.

## Consequences

- PDTBar owns a credential for the first time. Keychain, redaction, and in-memory test stores become required infrastructure (#245).
- Transport is a plain read-only HTTP client with typed errors, pagination, and rate-limit handling (#244), not CLI orchestration.
- Normalization keeps its shape; REST envelopes map into the existing facets (#246).
- Onboarding, background refresh, and Data Health change to describe PDT access instead of Claude/MCP readiness (#247-#249).
- The release waits for the browser sign-in to work end to end. The token fallback can be built first behind the same token-store seam.
