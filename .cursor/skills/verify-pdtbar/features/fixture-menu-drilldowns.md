# Fixture menu and drill-downs

The status icon is the Concentration Stack. The center bar is always full height. The number of filled bars is the attention count, capped at 3. The menu shows, top to bottom: the summary figure (one row, no header), Pulse, Allocation (the chart row and its `Full allocation list` submenu of holdings, sectors, and asset types), Income, Big movers, Data (the `Prices` submenu, then a `Data health` row when it has something to report), and Actions. On a screen too short for the menu, rows fold into submenus step by step (#304).

Proof that it works: in fixture mode the app stays running and writes `latest-portfolio-snapshot.json` to the run's snapshot dir. With AX, the open menu contains the fixture's identifiers, such as `pdtbar.section.allocation`, `pdtbar.section.bigMovers`, `pdtbar.row.freshness.summary`, and `pdtbar.row.actions.settings`. `pdtbar.row.income.next` needs a fixture with an upcoming payment (`income-event.json`, `worst-case-height.json`).

## Sub-features

- Status icon fill and tooltip.
- Pulse (quiet or pressure).
- Summary figure, allocation, and income sections.
- Big movers, including the sign of each move (#302).
- Data: `Prices` lists each holding's last price with its own date (#307); `Data health` names why it needs attention (#298).
- Small-screen fit (#304): Big movers into a submenu, the income list folded, the chart into `Full allocation list`, then whole sections collapsed to one row. Actions never folds.
- Copy holding identifier (`copy-holding-identifier-action`, isolated pasteboard).

## How to get to it (user POV)

Click the menu bar icon. Hover a row with a chevron to open its submenu.

## Driving it with verify_pdtbar.sh and pdtbar-smoke

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/big-mover.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh doctor "$RUN"
swift run pdtbar-dev descriptor --fixture docs/pdt/fixtures/big-mover.json > "$RUN/evidence/descriptor.json"
swift run pdtbar-smoke ready-launch --artifacts "$RUN/evidence" --app-support-dir "$RUN/smoke-app-support"
swift run pdtbar-smoke fixture-proof --fixture docs/pdt/fixtures/big-mover.json --output "$RUN/evidence/fixture-proof.svg"
Scripts/verify_pdtbar.sh stop "$RUN"
```

`ready-launch` opens the real pulse menu through AX after a scripted PDT first fetch. Setup and retryable-error menus are covered by `logged-out-launch`, `scripted-setup-retry`, and `scripted-first-fetch`. No prompt-free smoke opens the Data/Prices or Data health submenus through AX; read their rows from the descriptor above, minus Data health (see Gotchas). None of these captures the screen. The opt-in `Scripts/verify_pdtbar.sh menu-smoke` opens the allocation overview submenu and captures it (see Visual proof).

Opt-in pixel proof captures the screen, so ask the user first: `swift run pdtbar-smoke real-user-pulse --fixture <f> --snapshot-dir "$RUN/real-user-pulse" --artifacts "$RUN/evidence" --peekaboo /opt/homebrew/bin/peekaboo`.

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. Use a screenshot for the status icon and the top-level menu. Use a recording when the change is about the menu opening, such as layout shifts or chart rendering.

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh capture screenshot "$RUN" menu-open
Scripts/verify_pdtbar.sh capture record "$RUN" menu-clip 4
Scripts/verify_pdtbar.sh stop "$RUN"
```

For a small-screen fit change, `Scripts/verify_pdtbar.sh menu-measure docs/pdt/fixtures/worst-case-height.json` writes the root rows to `measure.json` plus `menu.png`. It captures the screen, so it is opt-in.

For the whole cohesive menu plus the `Full allocation list` and `Prices` submenus in one run, use `Scripts/verify_pdtbar.sh menu-smoke`. It prints `menu-walk: ok` and the evidence dir holding `menu.png`, `allocation-overview.png`, and `prices.png`. The `Prices` submenu lists each holding's last price from PDT with its own date (`freshness.price.<quoteId>`).

The image must show the Concentration Stack icon in its highlighted state and the open menu with the summary figure, Pulse, Allocation with its chart, Income, Big movers, Data, and Actions. `capture` does not open submenus; `menu-smoke` does. Swap the fixture for the state under test, such as `quiet-no-pressure.json`.

## Gotchas

- Fixtures with a prior snapshot (`big-mover.json`) seed it only through `real-user-pulse`. A plain `verify_pdtbar.sh launch` has no prior, so big-mover deltas may not show.
- `fixture-proof` and `menu-polish-proof` render descriptors to SVG. They are not real menu pixels and must not stand as the only UI proof.
- A fixture launch without `--snapshot-dir` writes to a temp dir. Always go through `verify_pdtbar.sh`.
- Data health is a row in the Data section (`pdtbar.row.dataHealth`), not its own section. It is hidden while healthy and while stale or unknown price dates are its only cause, and shown for anything else, including while access is checking or details are filling. A fixture launch counts as fetched and connected, so `concentration-pressure.json`, whose prices are merely stale, shows no Data health row. When shown, its rows are Source, Access, Cache, Prices, Detail fill, Read state, and Diagnostics, and they describe PDT API access.
- `pdtbar-dev descriptor --fixture` renders the model without a fetch, so its Data health reads `Not fetched this session` and the row appears for every fixture. The app never shows that row for a fixture launch. Do not cite it as menu proof.
- The opt-in `pdtbar-capture walk --plan sync-failure-reconnect` (see [first-fetch-pulse.md](first-fetch-pulse.md)) is the one path that opens the Data health submenu through AX. To see the failure rows and the `Copy diagnostics` text without a launch, read `failedSyncs` in the proof `swift run pdtbar-smoke scripted-api-snapshot --artifacts "$RUN/evidence"` writes.
