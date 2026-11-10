# PDTBar feature map

One file per user-facing feature. Each file names the observable end state that proves the feature works. Start with [`../SKILL.md`](../SKILL.md) for launch, doctor, and cleanup.

- [first-fetch-pulse.md](first-fetch-pulse.md) covers the connected launch, the first portfolio fetch, and the pulse menu. Prompt-free proof is available.
- [pdt-connection.md](pdt-connection.md) covers the not-connected menu, `Sign in with PDT`, the pasted token, reconnect, paused, and Keychain states, `Check again`, and `Disconnect from PDT`. Prompt-free proof is available.
- [pulse-mark-read.md](pulse-mark-read.md) covers attention items, `Mark as read`, and resurfacing on material change. Prompt-free proof is available.
- [fixture-menu-drilldowns.md](fixture-menu-drilldowns.md) covers the status icon, the pulse, and the allocation, income, Data/Prices, and Data health submenus. Launch proof is prompt-free. Pixel proof is opt-in.
- [settings-portfolio-values.md](settings-portfolio-values.md) covers the Settings window and the `Show portfolio values` mask. It is opt-in only.

Each file ends with a `Visual proof` section: the opt-in `Scripts/verify_pdtbar.sh capture` command, its fixture, and what the image must show. See Visual capture in [`../SKILL.md`](../SKILL.md).

Proved end to end (launch, doctor, drive, evidence, cleanup): `first-fetch-pulse` via `scripted-first-fetch`.
