---
summary: "Publieke Nederlandstalige installatie- en eerste-gebruiksgids voor PDTBar."
read_when:
  - Updating public install or first-use copy
title: "Installeren"
lang: "nl"
permalink: "/install/"
description: "Installeer en gebruik PDTBar op macOS zonder Homebrew."
---

# Installeren

Homebrew wordt nog niet ondersteund. Er is nu dus geen `brew install`-commando voor PDTBar.

Er staat ook nog geen publieke appdownload bij GitHub releases. Gebruik voorlopig een gedeelde `PDTBar.app.zip` build van de projectmaintainer. Zodra publieke downloads klaar zijn, komen ze op de [PDTBar releases-pagina](https://github.com/BramVR/pdtbar/releases).

## Voor Je Begint

Je hebt nodig:

- Een Mac met macOS 14 of nieuwer.
- Je Portfolio Dividend Tracker-portefeuille.
- Een PDT-account om PDTBar mee te verbinden.

PDTBar opent zonder verbinding en vraagt je eerst verbinding te maken met PDT voordat je portefeuillegegevens ziet.

## De App Installeren

1. Dubbelklik op `PDTBar.app.zip` als je Mac die niet automatisch uitpakt.
2. Sleep `PDTBar.app` naar Programma's.
3. Open PDTBar vanuit Programma's.

Als macOS zegt dat de app van het internet is gedownload, klik met rechts op `PDTBar.app`, kies `Open` en kies daarna nog een keer `Open`. Dit hoeft normaal maar een keer.

## Eerste Gebruik

Na het openen staat er een klein stapel-icoon in de macOS-menubalk.

- Zie je je portefeuilleoverzicht, dan ben je klaar.
- Zie je `Sign in with PDT`, klik daarop en keur PDTBar goed op de pagina van PDT in je browser.
- Wil je liever een token gebruiken, kies dan `Use a PDT token…` en plak een alleen-lezen token van de pagina Integrations > API in PDT.
- Zie je `Reconnect to PDT`, dan accepteert PDT de verbinding niet meer. Log opnieuw in of plak een nieuw token; je laatste overzicht blijft zichtbaar.
- Zie je `PDT access paused`, dan is je PDT-abonnement afgelopen. Verleng het en klik daarna op `Check again`.
- Zie je `Keychain unavailable`, dan is deze kopie van PDTBar niet ondertekend voor de Sleutelhanger. Installeer in plaats daarvan de ondertekende release.

## Dagelijks Gebruik

- Klik op het menubalkicoon om te zien wat aandacht vraagt.
- Gebruik `Refresh now` om nieuwe PDT-gegevens op te halen.
- Gebruik `Open PDT` als je het volledige Portfolio Dividend Tracker-dashboard wilt openen.
- Gebruik `Disconnect from PDT` om de opgeslagen verbinding te verwijderen.

PDTBar is standaard alleen-lezen. De app plaatst geen orders, verplaatst geen geld, uploadt je portefeuille niet naar een eigen backend en geeft geen financieel advies.

Bekijk de [functionaliteitengids](features.nl.md) voor wat elk menuonderdeel doet.
