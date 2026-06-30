---
summary: "Nederlandstalige startpagina voor de publieke PDTBar-site."
read_when:
  - Updating the public docs-site copy
title: "PDTBar"
lang: "nl"
permalink: "/"
description: "PDTBar toont de belangrijkste signalen uit je Portfolio Dividend Tracker-portefeuille in de macOS-menubalk."
---

# PDTBar

PDTBar laat de belangrijkste signalen uit je Portfolio Dividend Tracker-portefeuille zien in de macOS-menubalk. De app gebruikt je bestaande Claude CLI en PDT MCP-koppeling, leest de data lokaal en toont alleen wat nu aandacht verdient.

Je ziet snel waar de portefeuille zwaar leunt, welke inkomsten eraan komen, welke posities opvallend bewegen, of je data nog vers is en wanneer er niets bijzonders speelt.

## Wat je ziet

- Concentratie: welke posities veel gewicht hebben.
- Inkomsten: aankomende dividend- en cashflowmomenten.
- Grote bewegingen: posities die duidelijk zijn veranderd.
- Data: hoe vers je PDT-gegevens zijn.
- Alles rustig: een kalme status wanneer er niets speelt.

## Zo werkt het

PDTBar gebruikt dezelfde gegevens als PDT, maar met een ander doel. PDT blijft je volledige dashboard. PDTBar blijft in de menubalk en geeft een korte stand van zaken: de paar dingen die je normaal zelf zou moeten opzoeken.

Op dit moment werkt PDTBar via Claude:

```text
PDTBar openen
Claude CLI-login controleren
PDT MCP-server controleren
PDT-data ophalen zonder te wijzigen
korte stand tonen
```

Ontbreekt er iets, dan toont PDTBar `Log in with Claude` en `Check again`. In normaal gebruik hoef je geen terminal te openen.

## Privacy

PDTBar draait lokaal en wijzigt niets. De app plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde; jij bepaalt wat belangrijk is.

## Status

PDTBar is in actieve ontwikkeling. Testgegevens zijn er voor ontwikkeling en smoke-tests. Echte portefeuille-updates lopen via de lokale Claude CLI en PDT MCP-koppeling.

## Broncode

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
