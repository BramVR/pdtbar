---
summary: "Nederlandstalige startpagina voor de publieke PDTBar-site."
read_when:
  - Updating the public docs-site copy
title: "PDTBar"
lang: "nl"
permalink: "/"
description: "PDTBar toont in de macOS-menubalk wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille."
---

# PDTBar

PDTBar toont in de macOS-menubalk wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille. De app gebruikt je bestaande Claude CLI en PDT MCP-koppeling, leest lokaal mee en verandert niets.

Je ziet in een oogopslag waar je portefeuille zwaar leunt, welke inkomsten eraan komen, welke posities opvallend bewegen, hoe recent je data is en wanneer er niets om aandacht vraagt.

## Wat je ziet

- Concentratie: welke posities het meeste gewicht hebben.
- Inkomsten: aankomende dividend- en cashflowmomenten.
- Grote bewegingen: posities die duidelijk veranderd zijn.
- Data: hoe recent je PDT-gegevens zijn.
- Geen bijzonderheden: wanneer er niets om aandacht vraagt.

## Zo werkt het

PDTBar gebruikt dezelfde gegevens als PDT, maar met een andere rol. PDT blijft je volledige dashboard. PDTBar blijft in de menubalk en vat samen wat je anders zelf zou moeten opzoeken.

Op dit moment werkt PDTBar via Claude:

```text
PDTBar openen
Claude CLI-login controleren
PDT MCP-server controleren
PDT-data lezen zonder iets te wijzigen
samenvatting tonen
```

Als er iets ontbreekt, toont PDTBar `Log in with Claude` en `Check again`. In normaal gebruik hoef je de terminal niet te openen.

## Privacy

PDTBar draait lokaal en verandert niets aan je portefeuille. De app plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde; jij bepaalt wat belangrijk is.

## Status

PDTBar is in actieve ontwikkeling. Testgegevens zijn er alleen voor ontwikkeling en smoke-tests. Echte portefeuille-updates lopen via de lokale Claude CLI en PDT MCP-koppeling.

## Broncode

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
