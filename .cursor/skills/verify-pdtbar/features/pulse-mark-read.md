# Pulse mark-read

A pulse attention item (for example concentration pressure) has a `Mark as read` action. Marked items stay hidden across relaunches until the underlying data materially changes.

Proof that it works: after `Mark as read`, the local read fingerprint persists in the snapshot dir, the same fingerprint stays hidden after a cached reload, and changed material data resurfaces as unread.

## Sub-features

- `Mark as read` action payload.
- Read state that persists across a cached reload.
- Resurfacing after a material change.

## How to get to it (user POV)

Open the menu while an attention item shows, then pick `Mark as read` on that item.

## Driving it with pdtbar-smoke

```bash
RUN=$(Scripts/verify_pdtbar.sh launch | sed -n 's/^ready: //p')   # run dir; evidence lands in $RUN/evidence
swift run pdtbar-smoke scripted-pulse-mark-read --artifacts "$RUN/evidence"
Scripts/verify_pdtbar.sh stop "$RUN"
```

Read `$RUN/evidence/pdtbar-scripted-pulse-mark-read-proof.json`. `--artifacts` moves only that proof file. The smoke always writes its snapshot and read state to `.build/pdtbar-smoke-artifacts/scripted-pulse-mark-read-state-<uuid>/`, whatever `--artifacts` says. Look there for the persisted fingerprint. To look at the item by hand, run `Scripts/verify_pdtbar.sh launch docs/pdt/fixtures/concentration-pressure.json`.

## Gotchas

- The smoke drives the descriptor action payload and `PulseReadStore` without opening the menu. It proves the persistence contract but not the menu click. A real click needs AX plus a hand-driven or new AX scenario. No existing scenario clicks `Mark as read`.
- It needs the `concentration-pressure.json` fixture. The quiet fixture has no attention item, so the journey cannot run there.
