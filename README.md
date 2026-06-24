# portfolio-pulse

> **Working name** — change it. An ambient, plug-and-play companion for your *whole* investment portfolio, built on the Portfolio Dividend Tracker (PDT) MCP.

It lives in the **macOS menu bar** and surfaces only the few things across your portfolio that actually need attention right now — quiet by default, no dashboard. The core is a **pressure engine** that turns the firehose of portfolio data into a short, ranked list of "look at this" items, which the bar renders.

## Status: Claude-first product path

No-argument launch is the product path. The app starts in the macOS menu bar, quietly probes the existing Claude Desktop/PDT MCP setup, skips setup UI when Claude is ready, fetches the required read-only PDT data, writes the first local snapshot, and publishes a pulse only after complete normalized data reaches the pressure engine.

If setup is missing, the menu stays Claude-only: `Log in with Claude`, `Check again`, and setup copy for missing Claude Desktop/login/PDT MCP. Fixture mode is explicit developer tooling behind `--fixture`; it must not be implied by no-argument launch or mutate real app state.

The menu-bar status item is the compact Concentration Stack icon. Bar heights represent concentration shape; filled bars represent attention count capped at three; there is no separate notification dot. Freshness/failure stays in tooltip/menu copy, with optional whole-icon dimming.

## Developer commands

```bash
swift run pdtbar-dev model --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/quiet-no-pressure.json
swift run pdtbar-checks
swift run pdtbar-smoke scripted-pdt-connector
swift run pdtbar-smoke scripted-login-handoff
swift run pdtbar-smoke scripted-setup-retry
swift run pdtbar-smoke scripted-first-fetch
swift run pdtbar-smoke scripted-returning-launch
swift run pdtbar-smoke manual-claude-pdt --model opus
swift run pdtbar-smoke live-pdt
swift build --product pdtbar
swift run pdtbar-smoke logged-out-launch
swift run pdtbar-smoke ready-launch
swift run pdtbar-smoke real-claude-flow-ax
swift run pdtbar-smoke packaged-app --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/manual-snapshot
swift run pdtbar-smoke real-user-pulse --fixture docs/pdt/fixtures/quiet-no-pressure.json --snapshot-dir .build/pdtbar-smoke-artifacts/real-user-pulse
```

Smoke gate details: [`docs/smoke-checks.md`](docs/smoke-checks.md).
Claude workflow details: [`docs/claude-login-workflow.md`](docs/claude-login-workflow.md).

## Historical planning kickoff

The original alignment prompt lives at [`docs/prompts/codex-kickoff.md`](docs/prompts/codex-kickoff.md), but it is historical pre-build context. Current agents should start from this README, [`docs/claude-login-workflow.md`](docs/claude-login-workflow.md), [`docs/smoke-checks.md`](docs/smoke-checks.md), and the Swift sources.

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
│   │   └── 0001-core-architecture-and-stack.md   # status: Accepted
│   ├── claude-login-workflow.md
│   └── prompts/
│       └── codex-kickoff.md  # paste this as the first message to your agent
└── src/                      # early architecture notes; Swift code lives in Sources/
    ├── engine/README.md      # the pressure engine (the IP)
    └── bar/README.md         # the menu-bar renderer (the "pulse")
```

## The two pieces

- **Engine** (`src/engine`) — the brain. Reads the portfolio from PDT + a small history snapshot, computes "pressure," and emits a **structured model** (ranked attention items + their supporting data + facet snapshots). Deterministic; no LLM needed.
- **Bar** (`src/bar`, `Sources/PDTBarApp`) — the "pulse." A thin renderer over the engine's model: the Concentration Stack status icon, a menu of attention items, and submenus to drill into everything without leaving the bar.

Keep this separation clean — it's the main architectural bet.

## Non-negotiables

See [`CONTEXT.md`](CONTEXT.md). In short: **informational, not financial advice**; **read-only** against PDT by default; **local-first / private**; **plug-and-play** (two clicks to value, quiet by default).

## Principle

Minimal, good basics, product first. Reuse a tool only where it clearly saves work; otherwise borrow the idea. We do **not** adopt shared agent-script/workflow apparatus.

## License & attribution

Add your own `LICENSE`. Note any reused MIT-licensed code (CodexBar/RepoBar/mcporter) per `docs/reuse-notes.md`.
