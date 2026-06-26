---
summary: "Publieke PDTBar startpagina."
read_when:
  - Changing the public docs-site home page
title: "PDTBar"
description: "PDTBar is een rustige macOS menubalk-companion voor Portfolio Dividend Tracker-portefeuilles."
lang: "nl"
alternate: "en/index.md"
---

# PDTBar

PDTBar is een rustige macOS menubalk-companion voor je Portfolio Dividend Tracker-portefeuille.

De app gebruikt je bestaande Claude CLI + PDT MCP setup, haalt alleen-lezen portefeuillegegevens op, en toont alleen wat nu aandacht verdient: concentratie, inkomstenmomenten, grote bewegingen, versheid, of gewoon dat alles rustig is.

![PDTBar menu states](assets/pdtbar-menu.png)

## Wat Het Doet

- Toont een compacte Concentration Stack in de macOS menubalk.
- Vult maximaal drie balkjes wanneer er aandachtspunten zijn.
- Opent naar een gerangschikte pulse in plaats van een dashboardraster.
- Houdt portefeuillegegevens lokaal en alleen-lezen.
- Gebruikt deterministische drukregels, geen financieel advies.

## Hoe Het Werkt

1. Start PDTBar.
2. PDTBar controleert Claude CLI login en de geconfigureerde PDT MCP server.
3. Als alles klaarstaat, haalt PDTBar alleen-lezen PDT data op.
4. Als setup ontbreekt, toont het menu `Log in with Claude` en `Check again`.

Fixture mode bestaat alleen voor ontwikkeling en wordt niet automatisch gestart.

## Waarom Menubalk

PDT is een plek waar je naartoe gaat om je portefeuille te bekijken. PDTBar draait dat om: het kijkt rustig mee en brengt alleen de twee of drie dingen naar voren die vandaag nuttig zijn.

Op stille dagen is stilte ook een echte staat. Je ziet context, maar geen onnodige druk.

## Privacy En Vertrouwen

- Geen transacties.
- Geen koop- of verkoopadvies.
- Geen generieke OAuth flow of token-plakveld.
- Geen gedeeltelijke pulse als data ophalen mislukt.
- Lokale, alleen-lezen route via Claude CLI en PDT MCP.

## Broncode

PDTBar is open source bij [BramVR/pdtbar](https://github.com/BramVR/pdtbar).

```sh
git clone https://github.com/BramVR/pdtbar.git
cd pdtbar
make start
```
