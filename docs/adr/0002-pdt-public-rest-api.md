---
summary: "Accepted decision: read PDT through its public REST API with browser sign-in (main) or a pasted read-only token (fallback); retire the Claude CLI + PDT MCP path."
read_when:
  - Changing how PDTBar connects to or authenticates with PDT
  - Adding PDT REST requests, token storage, or sign-in/disconnect behavior
  - Writing setup, reconnect, or Data Health copy about PDT access
  - Removing or touching the Claude CLI + PDT MCP path
---

# ADR-0002: Adopt the PDT public REST API

- **Status:** Accepted
- **Date:** 2026-11-09
- **Deciders:** Bram
- **Supersedes:** the Claude-only connection model in `docs/claude-login-workflow.md`, `docs/product-brief.md`, and `docs/v1-scope.md`. ADR-0001 (native Swift, engine/bar separation) still holds.
- **Sign-off:** [#252 decisions](https://github.com/BramVR/pdtbar/issues/252#issuecomment-6733477391), [#245 long-lived connection](https://github.com/BramVR/pdtbar/issues/245#issuecomment-6733711618). Tracking: [#243](https://github.com/BramVR/pdtbar/issues/243).

## Context

PDTBar reads PDT by running the signed-in Claude CLI, which calls the PDT MCP server one tool at a time (`Sources/PDTBarAppSupport/ClaudeLocalConnection.swift`). Every read is a full Claude CLI run with an LLM round trip and stream-json parsing. Portfolio data passes through an Anthropic-hosted Claude session on its way to PDTBar.

PDT now publishes a REST API (`https://api.portfoliodividendtracker.com/v1`, docs v0.8.1) that serves the same data over HTTPS with a bearer token. `VISION.md` puts new data sources, token handling, and privacy-impacting behavior under **Needs Sign-Off**. Bram signed off on 2026-11-09.

## Decision

1. **Data source.** The PDT REST API replaces the Claude CLI + PDT MCP path as the product data source. PDTBar sends only `GET` requests to an explicit allowlist of read endpoints. It never calls a PDT write endpoint. OAuth registration and token requests are authentication operations, not portfolio writes.
2. **Main path: browser sign-in.** OAuth 2 Authorization Code with S256 PKCE, opened in the user's browser, with the redirect going to a loopback address on a free port (`http://127.0.0.1:<port>/callback`, RFC 8252 style). No custom URL scheme. PDTBar registers a public client once per install through dynamic registration and caches the `client_id`. It requests the `read` scope only, never `write` or `mcp:use`.
3. **Long-lived connection.** Access tokens last about one hour. PDTBar refreshes them in the background, about hourly while it runs, with one refresh in flight at a time. Each refresh returns a new token pair, which replaces the stored one. The user should not have to sign in again while PDTBar keeps running at least once inside PDT's refresh window.
4. **Fallback: pasted personal access token.** The user creates a read-only token in PDT under Integrations > API and pastes it once. Setup copy recommends the `read` scope and lets the user pick `1_year` or `never` expiry. These tokens cannot be refreshed. PDTBar can read their `scopes`, `status`, and `expiresAt` from `GET /v1/personal-access-tokens` by matching `tokenHint` (the last 8 characters).
5. **Read-only only.** Both paths are read-only. A `read` token makes PDT enforce it too: write endpoints answer `403 INSUFFICIENT_SCOPE`.
6. **Token storage.** One Keychain item scoped to PDTBar, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, so it never syncs through iCloud Keychain and never restores onto another Mac. Tokens never appear in Application Support files, snapshots, logs, diagnostics, Data Health copy, or proof artifacts. Tests and smokes use an in-memory store and never touch the Keychain.
7. **Disconnect.** `Disconnect` deletes the Keychain item. Its copy points to PDT Integrations (tokens) or connected apps (`/v1/authorizations`) for revoking on PDT's side.
8. **Expiry is never silent.** Data Health shows the token expiry date and warns on `expiring_soon` (within 14 days). `401 TOKEN_INVALID` (`details.reason` = `invalid`, `expired`, or `revoked`) moves the menu to a reconnect state and keeps the cached pulse visible. `403 API_ACCESS_PAUSED` (subscription ended) is its own state; the token stays valid.
9. **Claude/MCP path: deleted.** #250 removes it in one wave once the REST path reaches parity. No hidden fallback and no user toggle. Until then the Claude path stays the shipped behavior.
10. **Copy rules.** Visible menu copy may say "token" (setup and expiry need it). It still never says `codex`, `oauth`, `api key`, `fixture`, or `mcporter`, and never echoes a token value (`pdt_…`). Users see "Sign in with PDT", not "OAuth".

## Privacy

Portfolio data now flows PDT → PDTBar directly. No LLM sees the payload, which is a privacy improvement over the Claude path. PDTBar holds one more secret (the token), kept on this device only.

## Live findings (2026-11-09)

From [#243 tested answers](https://github.com/BramVR/pdtbar/issues/243#issuecomment-6733678312): public OAuth endpoints plus GET-only calls with Bram's read-only token. Only shapes and counts were recorded.

- **Redirect.** `pdtbar://oauth/callback` is rejected at registration (`400 invalid_redirect_uri`). `http://127.0.0.1:53682/callback` registers (`201`), and authorize accepts the same client on another port. An unregistered host gets `401 invalid_client`.
- **Scope.** `scope=read` passes authorize validation; an unknown scope gets `invalid_scope`. Registration reports `scope: mcp:use`. Bram's personal token lists `scopes: ["read"]`.
- **Registration.** Dynamic registration works without authentication. Its rate limit is undocumented.
- **`/portfolios`.** Fixed: every row has a non-zero `summary.currentWorth`. Rows carry only `date` and `summary`; historical holdings still come from `/portfolio/holdings?date=`.
- **Calendar.** All upcoming dividend events carry per-share `dividend.amount`; some are `isEstimated`.
- **Versioning.** No version header. Responses carry `X-RateLimit-Limit` (1000), `X-RateLimit-Remaining`, `X-RateLimit-Reset`, and `X-Request-Id`.
- **Envelopes.** Holdings return `{data: [...]}` with no `meta`. Paged lists return `{data, meta, links}` with camelCase `meta` (`currentPage`, `lastPage`, `perPage`, `total`). X-ray uses `limit`/`offset` and returns `{data: {items, hasMore, totalCount, …}}`. Errors use `{error: {code, message, details, traceId}}`.
- **Identity.** All holdings carry `symbolId`; nearly all carry `isin`. `/me` returns `portfolioCurrency`.

## Open risks

- **Refresh window reset.** Refresh tokens last 30 days. Unknown whether each refresh restarts that window. If it does not, the main path needs a fresh sign-in every 30 days. Needs PDT's answer or a 30-day wait.
- **Write-scope labels.** OpenAPI write-scope metadata looks inconsistent. Not blocking: the client is GET-only and never relies on those labels.
- **Redirect back and consent scope.** Unproven until one real browser sign-in completes: that PDT redirects back to the loopback listener after consent, that the consent screen shows read-only, and that the issued token carries only `read`.
- **Registration rate limit.** Undocumented; mitigated by registering once per install.
- **Leftover test client.** The redirect test left a public client named "PDTBar redirect test" registered on PDT. It has no grants and the API offers no delete.

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
