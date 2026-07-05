---
summary: "Publieke Nederlandstalige functionaliteitengids voor PDTBar."
read_when:
  - Updating public functionality or feature copy
title: "Functionaliteiten"
lang: "nl"
permalink: "/functionaliteiten/"
description: "Uitgebreide gids voor de menubalksamenvatting, portefeuilleonderdelen, verversstatus en privacy van PDTBar."
---

# Functionaliteiten

PDTBar draait om een kleine vraag: wat is nu de moeite waard om op te merken in je Portfolio Dividend Tracker-portefeuille?

De app laat het volledige dashboard in PDT en gebruikt de macOS-menubalk voor een kortere laag: een statusicoon, een gerangschikte Pulse en onderdelen met de feiten erachter.

## Menubalksamenvatting

Het menubalkicoon is een compacte Concentration Stack. Het blijft zichtbaar zolang PDTBar draait.

- De hoogte van de balken toont de concentratievorm.
- Gevulde balken tonen hoeveel ongelezen aandachtspunten er zijn, tot maximaal drie.
- De tooltip en toegankelijkheidslabel bevatten de huidige status in tekst.
- Als niets aandacht vraagt, blijft het icoon rustig in plaats van een lege waarschuwing te tonen.

Klik op het icoon om het menu te openen. Het eerste onderdeel is `Pulse`, met de portefeuillewaarde en daarna de belangrijkste aandachtspunten of `All quiet`.

## Aandachtspunten

Aandachtspunten zijn feiten die over een vaste lijn gaan. Het zijn geen aanbevelingen.

PDTBar kan op dit moment tonen:

- Positieconcentratie vanaf 20%.
- Sectorconcentratie vanaf 30%.
- Cashallocatie vanaf 10%.
- Drift in topconcentratie vanaf 5% wanneer er een eerdere snapshot is.
- Grote koersbewegingen vanaf 10% in het recente venster.
- Bevestigde ex-dividenddatums binnen de komende 30 dagen.

Elk aandachtspunt kan openklappen met de trigger, ernst, grenswaarde, huidige waarde, eerdere waarde wanneer beschikbaar en de brongegevens die PDTBar gebruikte.

## Allocatie

Het onderdeel `Allocation` toont de vorm van de portefeuille zonder PDT te openen.

- `Portfolio` toont een compacte allocatiegrafiek.
- `Detailed info` opent de lijst met posities.
- Posities tonen hun portefeuillegewicht en waarde wanneer beschikbaar.
- Positiedetails kunnen recente beweging, volgende inkomstengebeurtenis, gemiddelde aankoopprijs, winst/verlies en een kopieerbare identifier bevatten wanneer PDT die gegevens levert.
- Sector- en assettype-samenvattingen staan onder de positielijst wanneer PDT die gegevens levert.

Allocatiedruk kan in `Pulse` verschijnen, maar de onderliggende allocatiefeiten blijven beschikbaar nadat je het aandachtspunt als gelezen markeert.

## Inkomsten

Het onderdeel `Income` is een doorbladerbare kalenderweergave, niet alleen een lijst met waarschuwingen.

- `Income window` vat aankomende gebeurtenissen samen.
- `Next income` toont het eerstvolgende dividend- of cashflowmoment.
- Latere gebeurtenissen worden gegroepeerd in korte groepen zoals `This week` en `Later`.
- Gebeurtenisrijen tonen datum, soort, bevestigd/geschat, bedrag en verandering wanneer die informatie beschikbaar is.

Alleen bevestigde ex-dividenddatums binnen het huidige venster van 30 dagen worden aandachtspunten in Pulse. Andere inkomstengebeurtenissen blijven beschikbaar in Income.

## Grote Bewegingen

Het onderdeel `Big movers` vat recente koersbeweging samen.

Wanneer een positie over de 10%-grens gaat, kan PDTBar die in Pulse tonen met de koers ervoor en erna, de grootte van de beweging en het bronvenster. Als geen positie over de grens gaat, toont het onderdeel nog steeds hoeveel prijsrijen zijn gecontroleerd.

Wanneer er een eerdere snapshot is, vergelijkt PDTBar eerst met die snapshot. Als eerdere data ontbreekt, gebruikt de app PDT-prijsgeschiedenis.

## Data En Prijzen

Het onderdeel `Data` legt uit of de cijfers actueel genoeg zijn voor een snelle blik.

- `Prices` toont of prijsdata actueel, verouderd, gedeeltelijk of onbekend is.
- Verouderde data kan de oudste prijsdatum en betrokken posities tonen.
- Gedeeltelijke data kan tonen wanneer de laatste detailaanvulling klaar was.
- `Data health` verschijnt wanneer de bronstatus verminderd is.
- Diagnostiek kan worden gekopieerd wanneer een verversfout onderzocht moet worden.

Gecachte data kan het menu bruikbaar houden terwijl PDTBar op de achtergrond ververst, maar het onderdeel Data vertelt je wanneer dat gebeurt.

## Acties

Het onderdeel `Actions` houdt dagelijks gebruik kort.

- `Refresh now` vraagt PDTBar om verse PDT-data op te halen en details aan te vullen.
- `Open PDT` opent het volledige Portfolio Dividend Tracker-dashboard.
- `Log in with Claude` verschijnt alleen wanneer Claude-login ontbreekt.
- `Check again` controleert de setup opnieuw na login of wijzigingen aan de PDT MCP-koppeling.

## Gelezen Status

Ongelezen aandachtspunten vullen het statusicoon en verschijnen in Pulse. Nadat je een item als gelezen markeert, verdwijnt het uit de Pulse-telling, maar de onderliggende feiten blijven staan in Allocation, Income, Big movers of Data.

Als het feit later inhoudelijk verandert, kan het opnieuw verschijnen. Een concentratie-item dat opnieuw met andere waarden over de lijn gaat, wordt bijvoorbeeld als nieuw behandeld.

## Privacy En Grenzen

PDTBar leest via je lokale Claude CLI + PDT MCP-koppeling. De app draait lokaal en is standaard alleen-lezen.

PDTBar plaatst geen orders, verplaatst geen geld, uploadt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde; jij bepaalt wat belangrijk is.

Bekijk de [installatiegids](install.nl.md) voor setup en eerste gebruik.
