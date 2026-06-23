# portfolio-pulse

> **Working name** — change it. An ambient, plug-and-play companion for your *whole* investment portfolio, built on the Portfolio Dividend Tracker (PDT) MCP.

It lives in the **macOS menu bar** and surfaces only the few things across your portfolio that actually need attention right now — quiet by default, no dashboard. The core is a **pressure engine** that turns the firehose of portfolio data into a short, ranked list of "look at this" items, which the bar renders.

## Status: Claude setup + fixture path

This repo now has the first Swift launch paths: no-argument app launch probes Claude/PDT readiness before setup UI, scripted-ready launches complete the first PDT MCP fetch before publishing a pulse, and explicit fixture mode loads sanitized PDT fixtures into the engine, descriptor, and native macOS menu-bar app. Pressure rules are still intentionally quiet-first.

## Developer commands

```bash
swift run pdtbar-dev model --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-checks
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
swift run pdtbar-smoke live-pdt
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
swift build --product pdtbar
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse
```

Smoke gate details: [`docs/smoke-checks.md`](docs/smoke-checks.md).

## How to start

1. **Install the skills.** Make Matt Pocock's [`mattpocock/skills`](https://github.com/mattpocock/skills) available to your agent (Codex CLI or Claude Code), and run `/setup-matt-pocock-skills` once so `CONTEXT.md`/ADR scaffolding is configured.
2. **Open your agent and paste the kickoff prompt** — [`docs/prompts/codex-kickoff.md`](docs/prompts/codex-kickoff.md) — as the first message. (Attach [`docs/product-brief.md`](docs/product-brief.md) for fuller context.)
3. The agent runs **`grill-with-docs`**: it refuses to write code and interviews you branch by branch, filling in [`CONTEXT.md`](CONTEXT.md) and the ADRs in [`docs/adr/`](docs/adr/).
4. **First, exercise the PDT MCP** to learn what data actually exists — the whole design depends on it.
5. Then continue Matt's loop: `/to-prd` → `/to-issues` (vertical slices) → `/prototype` → `/tdd` the first slice.

## Repo map

```
portfolio-pulse/
├── README.md                 # you are here
├── CONTEXT.md                # domain model, shared language, hard constraints (living; grilling fills it)
├── .gitignore
├── docs/
│   ├── product-brief.md      # the why / what / who / the surface
│   ├── mvp-scope.md          # the first slice, sequencing, facet scope, cold-start spec
│   ├── reuse-notes.md        # what we reuse from steipete's tools (selective) + licensing
│   ├── adr/                  # architecture decision records
│   │   ├── README.md
│   │   ├── 0000-template.md
│   │   └── 0001-core-architecture-and-stack.md   # status: Proposed (resolve in grilling)
│   └── prompts/
│       └── codex-kickoff.md  # paste this as the first message to your agent
└── src/                      # placeholders — no code yet; shape settles after the stack ADR
    ├── engine/README.md      # the pressure engine (the IP)
    └── bar/README.md         # the menu-bar renderer (the "pulse")
```

## The two pieces

- **Engine** (`src/engine`) — the brain. Reads the portfolio from PDT + a small history snapshot, computes "pressure," and emits a **structured model** (ranked attention items + their supporting data + facet snapshots). Deterministic; no LLM needed.
- **Bar** (`src/bar`) — the "pulse." A thin renderer over the engine's model: a glanceable status item, a menu of attention items, and submenus to drill into everything without leaving the bar.

Keep this separation clean — it's the main architectural bet.

## Non-negotiables

See [`CONTEXT.md`](CONTEXT.md). In short: **informational, not financial advice**; **read-only** against PDT by default; **local-first / private**; **plug-and-play** (two clicks to value, quiet by default).

## Principle

Minimal, good basics, product first. Reuse a tool only where it clearly saves work; otherwise borrow the idea. We do **not** adopt shared agent-script/workflow apparatus.

## License & attribution

Add your own `LICENSE`. Note any reused MIT-licensed code (CodexBar/RepoBar/mcporter) per `docs/reuse-notes.md`.
