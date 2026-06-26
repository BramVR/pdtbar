---
summary: "Publieke Nederlandse startpagina voor de PDTBar docs-site."
read_when:
  - Updating the public docs-site copy
title: "PDTBar"
lang: "nl"
permalink: "/"
description: "PDTBar is een rustige macOS-menubalk voor Portfolio Dividend Tracker-portefeuilles."
---

# PDTBar

PDTBar is een rustige macOS-menubalk voor je Portfolio Dividend Tracker-portefeuille. De app kijkt mee via je bestaande Claude CLI + PDT MCP-installatie en laat alleen zien wat nu aandacht verdient.

De pulse draait om concentratie, inkomensmomenten, grote bewegingen, versheid en alles rustig-dagen.

## Wat je ziet

- Concentratie: welke posities het meeste gewicht krijgen.
- Inkomensmomenten: dividend- en kasstroommomenten die eraan komen.
- Grote bewegingen: holdings die duidelijk afwijken.
- Versheid: hoe recent de PDT-gegevens zijn.
- Alles rustig: een kalme status wanneer er niets belangrijks speelt.

## Hoe het werkt

PDTBar gebruikt dezelfde gegevens als PDT, maar met een ander ritme. PDT blijft de plek voor het volledige dashboard. PDTBar woont in de menubalk en geeft een korte pulse: de twee of drie feiten die je anders zelf zou moeten zoeken.

De huidige productlijn is Claude-first:

```text
open PDTBar
check Claude CLI login
check PDT MCP server
fetch read-only PDT data
show the portfolio pulse
```

Als de setup ontbreekt, biedt PDTBar `Log in with Claude` en `Check again`. Dagelijks gebruik vraagt geen terminalcommando's.

## Vertrouwen en privacy

PDTBar is lokaal en standaard alleen-lezen. De app plaatst geen orders, verplaatst geen geld, uploadt geen portefeuille naar een eigen backend, en geeft geen financieel advies. De pressure engine rangschikt feiten en veranderingen; jij beslist wat ze betekenen.

## Status

PDTBar is in actieve ontwikkeling. Fixturemodus bestaat voor ontwikkeling en smoke-tests, maar echte portfolio-updates lopen via de lokale Claude CLI + PDT MCP-route.

## Bron

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
