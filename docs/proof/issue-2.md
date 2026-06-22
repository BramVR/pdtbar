# Issue 2 proof

Native menu-bar process launch: passed with `PortfolioPulse --fixture pressure`; process stayed running until terminated by the proof harness.

Native screenshot capture: blocked by local macOS TCC. `peekaboo permissions status --json` reports Screen Recording and Accessibility not granted.

Built artifact render proof:

```text
PortfolioPulse --fixture quiet --render-once
status.title=Pulse
status.badge=none
card.title=All quiet
rows.count=0
```

```text
PortfolioPulse --fixture pressure --render-once
status.title=Pulse
status.badge=• 1
card.title=1 pressure item
rows.count=1
row.0.title=NVDA concentration climbing
row.0.detail=22% of portfolio; up from 18%
row.0.facet=allocation
```
