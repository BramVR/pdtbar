# Reuse Notes

**Stance:** minimal and selective. Reuse a tool only where it clearly removes work; otherwise borrow the *idea* or the *code*. We do **not** adopt shared agent-script / workflow apparatus (no `agent-scripts`). Add infrastructure only when the product needs it.

## What we reuse

- **CodexBar / RepoBar** (Swift menu-bar apps) — reuse the **menu-bar skeleton ideas**: status item, menu + submenus, refresh/coalescing, cached pulse while refreshing, and crisp empty/loading/error states. Do not copy browser OAuth, provider switching, or Keychain token storage into the Claude-first product path.
  - https://github.com/steipete/CodexBar · https://github.com/steipete/RepoBar
- **mcporter** (TS MCP runtime/CLI) — use it to **explore the PDT MCP during research** (list tools, inspect schemas, call ad-hoc) and for the optional live smoke. ADR-0001 chose native Swift, so mcporter is not a shipped runtime bridge.
  - https://github.com/steipete/mcporter
- **birdclaw** (local-first SQLite workspace) — **ideas only, as needed:** stable `--json` to stdout / logs to stderr for any CLI; a small local snapshot store for history (keep it tiny); a Git text backup if/when we want a data-ownership story. Don't build a full mirror.
  - https://birdclaw.sh/

## Not now (deferred ecosystem)

oracle, claude-code-mcp, imsg, poltergeist, Sparkle, Homebrew tap, stats.store — all optional and out of the first build. Pull in only when a concrete product need appears.

## Decisions this affects

ADR-0001 resolved the native-Swift-vs-TS-core choice: native Swift, with mcporter as research/dev tooling only.

## Licensing

CodexBar, RepoBar, and mcporter are MIT-licensed; if we vendor or fork any code, keep the MIT notice and attribute. Review transitive licenses of anything the bar skeleton pulls in (e.g. Sparkle) before shipping. Add a project `LICENSE` of our own.
