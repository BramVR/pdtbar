# Pulse mark-read

A pulse attention item (for example concentration pressure) has a `Mark as read` action. Marked items stay hidden across relaunches until the underlying data materially changes.

Proof that it works: after `Mark as read`, the local read fingerprint persists in the snapshot dir, the same fingerprint stays hidden after a cached reload, and changed material data resurfaces as unread.

## Sub-features

- `Mark as read` action payload (`pdtbar.row.<item-id>.markRead`, the last row of each attention item's submenu), on concentration, income, and Big movers items.
- Read state that persists across a cached reload.
- Resurfacing after a material change. A concentration item that drops below the threshold and crosses it again also comes back unread.
- With every item read, the status reads `All caught up` / `No unread items.` and Data health's `Read state` row counts them.

## How to get to it (user POV)

Open the menu while an attention item shows, then pick `Mark as read` on that item.

## Driving it with pdtbar-smoke

```bash
OUT=.build/verify-pdtbar/mark-read-$(date +%Y%m%d-%H%M%S)
swift run pdtbar-smoke scripted-pulse-mark-read --artifacts "$OUT/evidence"
```

Read `$OUT/evidence/pdtbar-scripted-pulse-mark-read-proof.json`. Pass requires `actionTitle: "Mark as read"` and `true` for `actionPayloadMatchedFirstAttentionFingerprint`, `afterClickHidden`, `persistedRelaunchHidden`, `changedDataResurfaced`, and `rawPortfolioPayloadsRedacted`. `caughtUpStatusTitle` is the status after the click. On `concentration-pressure.json` that is the next item, `Information Technology sector concentration`, not `All caught up`, and `changedStatusBadge` is `"2"`. `--artifacts` moves only that proof file. The smoke always writes its snapshot and read state to `stateDirectory`, `.build/pdtbar-smoke-artifacts/scripted-pulse-mark-read-state-<uuid>/`, whatever `--artifacts` says. The persisted fingerprint is in `pulse-read-state.json` there. To look at the item by hand, run `Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json`.

## Visual proof

For PR proof, run `Scripts/verify_pdtbar.sh can-capture` first and skip on exit 3. Take a screenshot of the item before marking. A recording adds nothing, because nothing clicks `Mark as read`.

```bash
RUN=$(Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json | sed -n 's/^ready: //p')
Scripts/verify_pdtbar.sh capture screenshot "$RUN" pulse-unread
Scripts/verify_pdtbar.sh stop "$RUN"
```

The image must show the status item and the open menu with the concentration attention items under `Pulse`. It proves the item is visible, not that `Mark as read` hides it.

## Gotchas

- The smoke drives the descriptor action payload and `PulseReadStore` without opening the menu. Its relaunch is a fresh `PulseReadStore` over the same dir, not a new process. It proves the persistence contract but not the menu click. A real click needs AX plus a hand-driven or new AX scenario. No existing scenario clicks `Mark as read`.
- It needs the `concentration-pressure.json` fixture. The quiet fixture has no attention item, so the journey cannot run there.
