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

PDTBar toont in de macOS-menubalk wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille. De app leest je portefeuille rechtstreeks uit PDT, alleen-lezen, en verandert niets.

Je ziet in een oogopslag waar je portefeuille zwaar leunt, welke inkomsten eraan komen, welke posities opvallend bewegen, hoe recent je data is en wanneer er niets om aandacht vraagt.

## Wat je ziet

- Concentratie: welke posities het meeste gewicht hebben.
- Inkomsten: aankomende dividend- en cashflowmomenten.
- Grote bewegingen: posities die duidelijk veranderd zijn.
- Data: hoe recent je PDT-gegevens zijn.
- Geen bijzonderheden: wanneer er niets om aandacht vraagt.

## Zo werkt het

PDTBar gebruikt dezelfde gegevens als PDT, maar met een andere rol. PDT blijft je volledige dashboard. PDTBar blijft in de menubalk en vat samen wat je anders zelf zou moeten opzoeken.

PDTBar maakt rechtstreeks verbinding met PDT:

```text
PDTBar openen
opgeslagen PDT-verbinding controleren
inloggen bij PDT, of een alleen-lezen PDT-token plakken
PDT-data lezen zonder iets te wijzigen
samenvatting tonen
```

Als PDTBar niet verbonden is, toont het menu `Sign in with PDT` en `Use a PDT token…`. In normaal gebruik hoef je de terminal niet te openen.

## Installeren

Homebrew wordt nog niet ondersteund. Er is ook nog geen publieke appdownload, dus testers gebruiken voorlopig een gedeelde `PDTBar.app.zip` build.

1. Pak `PDTBar.app.zip` uit.
2. Sleep `PDTBar.app` naar Programma's.
3. Open PDTBar en gebruik het icoon in de menubalk.

Bekijk de [installatiegids](install.nl.md) voor de eerste stappen en setupmeldingen.

Bekijk de [functionaliteitengids](features.nl.md) voor meer detail over Pulse, Allocation, Income, Big movers, Data en Actions.

## Privacy

PDTBar draait lokaal en verandert niets aan je portefeuille. Je PDT-verbinding staat alleen in de Sleutelhanger van deze Mac, en `Disconnect from PDT` verwijdert haar. De app plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde; jij bepaalt wat belangrijk is.

## Status

PDTBar is in actieve ontwikkeling. Testgegevens zijn er alleen voor ontwikkeling en smoke-tests. Echte portefeuille-updates komen uit de alleen-lezen API van PDT.

## Broncode

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
