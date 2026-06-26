---
summary: "Publieke Nederlandstalige startpagina voor de PDTBar docs-site."
read_when:
  - Updating the public docs-site copy
title: "PDTBar"
lang: "nl"
permalink: "/"
description: "PDTBar houdt je Portfolio Dividend Tracker-portefeuille rustig in beeld via de macOS-menubalk."
---

# PDTBar

PDTBar houdt je Portfolio Dividend Tracker-portefeuille rustig in beeld via de macOS-menubalk. De app gebruikt je bestaande Claude CLI en PDT MCP-koppeling, leest lokaal mee en toont alleen wat nu aandacht verdient.

Het korte overzicht draait om concentratie, inkomensmomenten, opvallende bewegingen, de actualiteit van je gegevens en dagen waarop er gewoon niets bijzonders speelt.

## In een oogopslag

- Concentratie: welke posities zwaar meetellen in je portefeuille.
- Inkomensmomenten: dividend- en kasstroommomenten die eraan komen.
- Opvallende bewegingen: holdings die duidelijk anders bewegen dan de rest.
- Actualiteit: of de PDT-gegevens nog recent genoeg zijn.
- Rust: een kalme melding wanneer er niets belangrijks speelt.

## Hoe het werkt

PDTBar gebruikt dezelfde gegevens als PDT, maar met een andere rol. PDT blijft de plek voor het volledige dashboard. PDTBar zit in de menubalk en geeft je een korte stand van zaken: de twee of drie feiten die je anders zelf uit het dashboard zou halen.

Op dit moment werkt PDTBar via Claude:

```text
PDTBar starten
Claude CLI-login controleren
PDT MCP-server controleren
PDT-gegevens alleen-lezen ophalen
kort portefeuilleoverzicht tonen
```

Als er nog iets ontbreekt, toont PDTBar `Log in with Claude` en `Check again`. Voor dagelijks gebruik hoef je geen terminalcommando's te draaien.

## Vertrouwen en privacy

PDTBar werkt lokaal en is standaard alleen-lezen. De app plaatst geen orders, verplaatst geen geld, uploadt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde; jij bepaalt wat je ermee doet.

## Status

PDTBar is in actieve ontwikkeling. De fixturemodus is alleen bedoeld voor ontwikkeling en smoke-tests; echte portefeuille-updates lopen via de lokale Claude CLI en PDT MCP-koppeling.

## Broncode

De broncode staat op [GitHub](https://github.com/BramVR/pdtbar).
