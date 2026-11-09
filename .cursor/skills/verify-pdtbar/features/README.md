# PDTBar feature map

One file per user-facing feature. Each file names the observable end state that proves the feature works. Start with [`../SKILL.md`](../SKILL.md) for launch, doctor, and cleanup.

- [first-fetch-pulse.md](first-fetch-pulse.md) covers the Claude-ready launch, the first portfolio fetch, and the pulse menu. Prompt-free proof is available.
- [claude-setup-login.md](claude-setup-login.md) covers the signed-out setup menu, `Log in with Claude`, and `Check again`. Prompt-free proof is available.
- [pulse-mark-read.md](pulse-mark-read.md) covers attention items, `Mark as read`, and resurfacing on material change. Prompt-free proof is available.
- [fixture-menu-drilldowns.md](fixture-menu-drilldowns.md) covers the status icon, the pulse, and the allocation, income, Data/Prices, and Data health submenus. Launch proof is prompt-free. Pixel proof is opt-in.
- [settings-portfolio-values.md](settings-portfolio-values.md) covers the Settings window and the `Show portfolio values` mask. It is opt-in only.

Proved end to end (launch, doctor, drive, evidence, cleanup): `first-fetch-pulse` via `scripted-first-fetch`.
