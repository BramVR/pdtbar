---
summary: "Publieke Nederlandstalige installatie- en eerste-gebruiksgids voor PDTBar."
read_when:
  - Updating public install or first-use copy
title: "PDTBar installeren"
lang: "nl"
permalink: "/install/"
description: "Installeer en gebruik PDTBar op macOS zonder Homebrew."
---

# PDTBar installeren

Homebrew wordt nog niet ondersteund. Er is nu dus geen `brew install`-commando voor PDTBar.

Er staat ook nog geen publieke appdownload bij GitHub releases. Gebruik voorlopig een gedeelde `PDTBar.app.zip` build van de projectmaintainer. Zodra publieke downloads klaar zijn, komen ze op de [PDTBar releases-pagina](https://github.com/BramVR/pdtbar/releases).

## Voor Je Begint

Je hebt nodig:

- Een Mac met macOS 14 of nieuwer.
- Je Portfolio Dividend Tracker-portefeuille.
- Je bestaande Claude CLI + PDT MCP-koppeling.

Als de Claude/PDT-koppeling nog niet klaar is, kan PDTBar wel openen, maar vraagt de app eerst om die verbinding af te maken voordat je portefeuillegegevens ziet. Vraag de persoon die je PDTBar gaf om te helpen met de PDT-koppeling.

## De App Installeren

1. Dubbelklik op `PDTBar.app.zip` als je Mac die niet automatisch uitpakt.
2. Sleep `PDTBar.app` naar Programma's.
3. Open PDTBar vanuit Programma's.

Als macOS zegt dat de app van het internet is gedownload, klik met rechts op `PDTBar.app`, kies `Open` en kies daarna nog een keer `Open`. Dit hoeft normaal maar een keer.

## Eerste Gebruik

Na het openen staat er een klein stapel-icoon in de macOS-menubalk.

- Zie je je portefeuilleoverzicht, dan ben je klaar.
- Zie je `Log in with Claude`, klik daarop, volg de browserstappen en klik daarna op `Check again`.
- Zie je `Add the PDT MCP server to Claude`, dan is PDTBar geinstalleerd, maar is de PDT-koppeling nog niet klaar.

## Dagelijks Gebruik

- Klik op het menubalkicoon om te zien wat aandacht vraagt.
- Gebruik `Refresh now` om nieuwe PDT-gegevens op te halen.
- Gebruik `Open PDT` als je het volledige Portfolio Dividend Tracker-dashboard wilt openen.

PDTBar is standaard alleen-lezen. De app plaatst geen orders, verplaatst geen geld, uploadt je portefeuille niet naar een eigen backend en geeft geen financieel advies.
