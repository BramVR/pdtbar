# PDTBar feature map

One file per user-facing feature. Each file names the observable end state that proves the feature works. Start with [`../SKILL.md`](../SKILL.md) for launch, doctor, and cleanup.

- [first-fetch-pulse.md](first-fetch-pulse.md) covers the connected launch, the first portfolio fetch, and the pulse menu. Prompt-free proof is available.
- [pdt-connection.md](pdt-connection.md) covers the not-connected menu, `Sign in with PDT`, the pasted token, reconnect, paused, and Keychain states, `Check again`, and `Disconnect from PDT`. Prompt-free proof is available.
- [pulse-mark-read.md](pulse-mark-read.md) covers attention items, `Mark as read`, and resurfacing on material change. Prompt-free proof is available.
- [fixture-menu-drilldowns.md](fixture-menu-drilldowns.md) covers the status icon, the summary figure, the pulse, allocation, income, Big movers, the Data section's Prices and Data health submenus, and the small-screen fit. Launch proof is prompt-free. Pixel proof is opt-in.
- [settings-portfolio-values.md](settings-portfolio-values.md) covers the Settings window and the `Show portfolio values` mask. The user path is opt-in only. The masking rules are prompt-free from the descriptor.

Each file ends with a `Visual proof` section: the opt-in `Scripts/verify_pdtbar.sh capture` command, its fixture, and what the image must show. See Visual capture in [`../SKILL.md`](../SKILL.md).

Proved on 2026-11-24 at `5fe4e88` (launch, doctor, drive, evidence, cleanup) on a host with Accessibility already granted and no capture: `first-fetch-pulse` via `scripted-first-fetch` with and without `--no-menu-checks`, `scripted-returning-launch --no-menu-checks`, the five `sync-failure-*` scripts, and `refresh-failure-503`; `pdt-connection` via `scripted-setup-retry`, `scripted-sign-in`, `logged-out-launch`, and `auth-measure`; `pulse-mark-read` via `scripted-pulse-mark-read`; `fixture-menu-drilldowns` via a fixture launch, descriptors, `copy-holding-identifier-action`, and `fixture-proof`; `settings-portfolio-values` via `descriptor --portfolio-values hidden` only. Not run: `ready-launch`, the settings smoke, and every pixel path.
