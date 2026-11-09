# Fixture menu and drill-downs

The status icon is the Concentration Stack. The center bar is always full height. The number of filled bars is the attention count, capped at 3. The menu shows the pulse, summary, allocation (portfolio, holdings, sectors, cash, concentration), income, Data/Prices, and Data health, with submenus.

Proof that it works: in fixture mode the app stays running and writes `latest-portfolio-snapshot.json` to the run's snapshot dir. With AX, the open menu contains the fixture's identifiers, such as `pdtbar.section.allocation`, `pdtbar.row.income.next`, and `pdtbar.row.actions.settings`.

## Sub-features

- Status icon fill and tooltip.
- Pulse (quiet or pressure).
- Summary, allocation, and income sections.
- Data/Prices and Data health drill-downs.
- Copy holding identifier (`copy-holding-identifier-action`, isolated pasteboard).

## How to get to it (user POV)

Click the menu bar icon. Hover a row with a chevron to open its submenu.

## Driving it with verify_pdtbar.sh and pdtbar-smoke

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/big-mover.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh doctor "$RUN"
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/big-mover.json > "$RUN/evidence/descriptor.json"
swift run pdtbar-smoke real-claude-flow-ax --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke fixture-proof --fixture docs/pdt/fixtures/big-mover.json --output "$RUN/evidence/fixture-proof.svg"
Scripts/verify_pdtbar.sh stop "$RUN"
```

`real-claude-flow-ax` opens the real menu through AX for setup, fetching, all-quiet, pressure, Data/Prices, Data health, and retryable-error surfaces. It does not capture the screen.

Opt-in pixel proof captures the screen, so ask the user first: `swift run pdtbar-smoke real-user-pulse --fixture <f> --snapshot-dir "$RUN/real-user-pulse" --artifacts "$RUN/evidence" --peekaboo /opt/homebrew/bin/peekaboo`.

## Gotchas

- Fixtures with a prior snapshot (`big-mover.json`) seed it only through `real-user-pulse`. A plain `verify_pdtbar.sh launch` has no prior, so big-mover deltas may not show.
- `fixture-proof` and `menu-polish-proof` render descriptors to SVG. They are not real menu pixels and must not stand as the only UI proof.
- A fixture launch without `--snapshot-dir` writes to a temp dir. Always go through `verify_pdtbar.sh`.
