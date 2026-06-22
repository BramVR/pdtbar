# Reuse Notes

**Stance:** minimal and selective. Reuse a tool only where it clearly removes work; otherwise borrow the *idea* or the *code*. We do **not** adopt shared agent-script / workflow apparatus (no `agent-scripts`). Add infrastructure only when the product needs it.

## What we reuse

- **CodexBar / RepoBar** (Swift menu-bar apps) — reuse the **menu-bar skeleton**: status item, menu + submenus, refresh loop, browser OAuth, Keychain token storage. This is what keeps a bar-first product from being expensive; don't hand-build menu-bar plumbing.
  - https://github.com/steipete/CodexBar · https://github.com/steipete/RepoBar
- **mcporter** (TS MCP runtime/CLI) — use it to **explore the PDT MCP during research** (list tools, inspect schemas, call ad-hoc). If we choose a TS core, it can stay as the runtime bridge; if we go native Swift, it's a dev/prototyping tool only and we talk to PDT directly from the app.
  - https://github.com/steipete/mcporter
- **birdclaw** (local-first SQLite workspace) — **ideas only, as needed:** stable `--json` to stdout / logs to stderr for any CLI; a small local snapshot store for history (keep it tiny); a Git text backup if/when we want a data-ownership story. Don't build a full mirror.
  - https://birdclaw.sh/

## Not now (deferred ecosystem)

oracle, claude-code-mcp, imsg, poltergeist, Sparkle, Homebrew tap, stats.store — all optional and out of the first build. Pull in only when a concrete product need appears.

## Decisions this affects

The native-Swift-vs-TS-core choice (ADR-0001) determines whether mcporter is a shipped dependency or just a research tool. Resolve it early — it shapes the repo.

## Licensing

CodexBar, RepoBar, and mcporter are MIT-licensed; if we vendor or fork any code, keep the MIT notice and attribute. Review transitive licenses of anything the bar skeleton pulls in (e.g. Sparkle) before shipping. Add a project `LICENSE` of our own.
