---
summary: "Reuse boundaries for CodexBar, RepoBar, mcporter, and other inspiration."
read_when:
  - Copying or adapting upstream code
  - Reviewing CodexBar/RepoBar patterns
  - Adding dependencies or borrowed infrastructure
---

# Reuse Notes

**Stance:** minimal and selective. Reuse a tool only where it clearly removes work; otherwise borrow the *idea* or the *code*. We do **not** adopt shared agent-script / workflow apparatus (no `agent-scripts`). Add infrastructure only when the product needs it.

## What We Reuse

- **CodexBar / RepoBar** (Swift menu-bar apps) — reuse the **menu-bar skeleton ideas**: status item, menu + submenus, refresh/coalescing, cached pulse while refreshing, and crisp empty/loading/error states. Do not copy browser OAuth, provider switching, or Keychain token storage into the Claude-first product path.
  - https://github.com/steipete/CodexBar · https://github.com/steipete/RepoBar
- **mcporter** (TS MCP runtime/CLI) — use it to **explore the PDT MCP during research** (list tools, inspect schemas, call ad-hoc) and for the optional live smoke. ADR-0001 chose native Swift, so mcporter is not a shipped runtime bridge.
  - https://github.com/steipete/mcporter
- **birdclaw** (local-first SQLite workspace) — **ideas only, as needed:** stable `--json` to stdout / logs to stderr for any CLI; a small local snapshot store for history (keep it tiny); a Git text backup if/when we want a data-ownership story. Don't build a full mirror.
  - https://birdclaw.sh/

## Copied Directly From CodexBar

- `Scripts/docs-list.mjs` — copied from CodexBar and lightly adjusted only in the final reminder text. This gives PDTBar the same docs inventory workflow: every docs page declares `summary` and `read_when`, and agents run `make docs-list` before relevant work.

Keep this script close to CodexBar's version unless PDTBar has a concrete docs-routing need.

## CodexBar Patterns To Adapt

- **Docs workflow:** frontmatter on docs pages, `make docs-list`, and `AGENTS.md` rules that require reading matching docs before code changes.
- **Status item lifecycle:** reuse one `NSStatusItem`, keep stable accessibility identifiers, and update icon/menu state in place where possible.
- **Cached pulse while refreshing:** preserve the last complete real pulse while a fresh fetch runs; publish replacement only after complete normalized data.
- **Refresh coalescing:** guard against duplicate readiness probes and portfolio fetches; retries should share or serialize active work.
- **Open-menu polish:** avoid blank intermediate menus; keep stale-but-valid content visible during refresh and update rows after data arrives.
- **State copy:** crisp setup/loading/empty/error rows, with retry actions in-menu.
- **Icon semantics:** a compact bar icon can encode status without becoming a tiny dashboard; stale/failure can dim the whole icon rather than adding extra badges.

## CodexBar Code To Consider Copying Later

- Small AppKit menu helpers for stable menu mutation, if PDTBar's menu becomes complex enough.
- Bounded refresh/join helpers, if future fetches fan out beyond the current coalesced PDT read path.
- Logging/redaction helpers, if live proof and support diagnostics expand.
- Menu card measurement/recycling patterns, only if PDTBar adopts hosted SwiftUI menu cards.

Do not copy provider registry, browser cookie import, OAuth/device flow, Keychain credential caches, Sparkle, WidgetKit, or multi-provider settings for v1. Homebrew release machinery is now a narrow distribution need; keep it limited to GitHub app archives and the tap cask.

## Deferred But Plausible Later

- **Tabbed source/provider surfaces:** likely useful once PDTBar supports multiple MCP access paths or richer source diagnostics. Keep v1 menu descriptors simple, but avoid naming/layout choices that make tabs impossible later.
- **Codex login for MCP access:** plausible future source path alongside Claude CLI. When this becomes active work, revisit CodexBar's Codex login/source-selection patterns and write an ADR before copying auth/storage code.
- **Provider/source registry:** likely useful only when Claude/PDT is no longer the sole product source. Introduce the smallest source abstraction when the second real source lands.
- **Existing Claude/Codex login reuse:** valid when narrow, read-only, prompt-safe, and explicit about storage ownership. Reuse host-app cookies/tokens only through a small source adapter; do not add broad browser-cookie import or generic credential storage until a product path requires it.
- **Credential storage:** only after a product path requires PDTBar-owned credentials. Until then, prefer existing signed-in host apps and scripted smoke fakes.

## Not now (deferred ecosystem)

oracle, claude-code-mcp, imsg, poltergeist, Sparkle, stats.store — all optional and out of the first build. Pull in only when a concrete product need appears.

## Decisions this affects

ADR-0001 resolved the native-Swift-vs-TS-core choice: native Swift, with mcporter as research/dev tooling only.

## Licensing

CodexBar, RepoBar, and mcporter are MIT-licensed; if we vendor or fork any code, keep the MIT notice and attribute. Review transitive licenses of anything the bar skeleton pulls in (e.g. Sparkle) before shipping. Add a project `LICENSE` of our own.
