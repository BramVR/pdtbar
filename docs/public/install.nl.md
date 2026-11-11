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

Homebrew wordt nog niet ondersteund. Er is op dit moment geen `brew install`-commando voor PDTBar.

Bij de GitHub-releases staat ook nog geen publieke download van de app. Gebruik voorlopig een gedeelde `PDTBar.app.zip`-build van de beheerder van het project. Zodra er publieke downloads zijn, staan ze op de [releasepagina van PDTBar](https://github.com/BramVR/pdtbar/releases).

## Voor je begint

Dit heb je nodig:

- Een Mac met macOS 14 of nieuwer.
- Je Portfolio Dividend Tracker-portefeuille.
- Een PDT-account om PDTBar mee te verbinden.

PDTBar start zonder verbinding en vraagt je om verbinding te maken met PDT. Pas daarna zie je portefeuillegegevens.

## De app installeren

1. Dubbelklik op `PDTBar.app.zip` als je Mac het bestand niet automatisch uitpakt.
2. Sleep `PDTBar.app` naar Programma's.
3. Open PDTBar vanuit Programma's.

Zegt macOS dat de app van het internet is gedownload? Klik dan met de rechtermuisknop op `PDTBar.app`, kies `Open` en kies daarna nog een keer `Open`. Dat hoeft normaal maar één keer.

## Eerste gebruik

Na het openen staat er een klein stapelicoon in de macOS-menubalk.

- Zie je je portefeuilleoverzicht, dan ben je klaar.
- Zie je `Sign in with PDT`, klik er dan op en geef PDTBar toestemming op de pagina van PDT in je browser.
- Gebruik je liever een token, kies dan `Use a PDT token…` en plak een token met alleen leesrechten van de pagina Integrations > API in PDT.
- Zie je `Reconnect to PDT`, dan accepteert PDT de verbinding niet meer. Log opnieuw in of plak een nieuw token. Je laatste overzicht blijft zichtbaar.
- Zie je `PDT access paused`, dan is je PDT-abonnement afgelopen. Verleng het en klik daarna op `Check again`.
- Zie je `Keychain unavailable`, dan is deze kopie van PDTBar niet ondertekend voor de Sleutelhanger. Installeer dan de ondertekende release.

## Dagelijks gebruik

- Klik op het icoon in de menubalk om te zien wat je aandacht vraagt.
- Met `Refresh now` haal je nieuwe PDT-gegevens op.
- Met `Open PDT` open je het volledige dashboard van Portfolio Dividend Tracker.
- Met `Disconnect from PDT` verwijder je de opgeslagen verbinding.

PDTBar is standaard alleen-lezen. De app plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies.

Op de pagina [Functionaliteiten](features.nl.md) lees je wat elk onderdeel van het menu doet.
