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

PDTBar toont in de macOS-menubalk wat er nu toe doet in je Portfolio Dividend Tracker-portefeuille. De app leest je portefeuille rechtstreeks uit PDT, met alleen leesrechten, en verandert niets.

Je ziet in één oogopslag waar het zwaartepunt van je portefeuille ligt, welke inkomsten eraan komen, welke posities opvallend bewegen, hoe actueel je gegevens zijn en wanneer niets je aandacht vraagt.

## Wat je ziet

- Concentratie: welke posities het zwaarst wegen.
- Inkomsten: dividend- en cashflowmomenten die eraan komen.
- Grote bewegingen: posities met duidelijke koersbewegingen.
- Data: hoe actueel je PDT-gegevens zijn.
- Geen bijzonderheden: een rustige status als niets je aandacht vraagt.

## Zo werkt het

PDTBar gebruikt dezelfde gegevens als PDT, maar heeft een andere rol. PDT blijft je volledige dashboard. PDTBar staat in de menubalk en vat samen wat je anders zelf zou moeten opzoeken.

PDTBar maakt rechtstreeks verbinding met PDT:

```text
PDTBar openen
opgeslagen PDT-verbinding controleren
inloggen bij PDT, of een PDT-token met alleen leesrechten plakken
PDT-gegevens lezen zonder iets te wijzigen
samenvatting tonen
```

Als PDTBar niet verbonden is, toont het menu `Sign in with PDT` en `Use a PDT token…`. Voor dagelijks gebruik heb je de terminal niet nodig.

## Installeren

Homebrew wordt nog niet ondersteund. Er is ook nog geen publieke download van de app, dus testers gebruiken voorlopig een gedeelde `PDTBar.app.zip`-build.

1. Pak `PDTBar.app.zip` uit.
2. Sleep `PDTBar.app` naar Programma's.
3. Open PDTBar en gebruik het icoon in de menubalk.

Op de pagina [Installeren](install.nl.md) staan de eerste stappen en de meldingen die je bij het instellen kunt tegenkomen.

Op de pagina [Functionaliteiten](features.nl.md) lees je meer over Pulse, Allocation, Income, Big movers, Data en Actions.

## Privacy

PDTBar draait lokaal en verandert niets aan je portefeuille. Je PDT-verbinding staat alleen in de Sleutelhanger van deze Mac, en met `Disconnect from PDT` verwijder je die. De app plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde. Wat ze betekenen, bepaal jij.

## Status

PDTBar wordt actief ontwikkeld. Testgegevens zijn er alleen voor ontwikkeling en smoke-tests. Echte updates van je portefeuille komen uit de API van PDT, waar PDTBar alleen leesrechten heeft.

## Broncode

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
