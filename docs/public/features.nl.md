---
summary: "Publieke Nederlandstalige functionaliteitengids voor PDTBar."
read_when:
  - Updating public functionality or feature copy
title: "Functionaliteiten"
lang: "nl"
permalink: "/functionaliteiten/"
description: "Uitleg over de samenvatting in de menubalk, de onderdelen van het menu, het verversen en de privacy van PDTBar."
---

# Functionaliteiten

PDTBar laat zien wat nu je aandacht verdient in je Portfolio Dividend Tracker-portefeuille.

Het volledige dashboard blijft in PDT. In de macOS-menubalk staat een kortere weergave: een statusicoon, Pulse met aandachtspunten op volgorde en onderdelen met de feiten erachter.

## Menubalksamenvatting

Het menubalkicoon is een compacte Concentration Stack. Het blijft zichtbaar zolang PDTBar draait.

- De balkhoogtes laten het huidige concentratiepatroon zien.
- Gevulde balken tonen hoeveel ongelezen aandachtspunten er zijn, met een maximum van drie.
- De tooltip en het toegankelijkheidslabel beschrijven de huidige status in woorden.
- Als niets je aandacht vraagt, toont het icoon geen waarschuwing.

Klik op het icoon om het menu te openen. Het eerste onderdeel is `Pulse`, met de portefeuillewaarde en daaronder de belangrijkste aandachtspunten of `All quiet`.

## Aandachtspunten

Aandachtspunten zijn feiten die een vaste grens zijn gepasseerd. Het zijn geen aanbevelingen.

PDTBar kan op dit moment tonen:

- Positieconcentratie vanaf 20%.
- Sectorconcentratie vanaf 30%.
- Cashallocatie vanaf 10%.
- Een verschuiving van 5% of meer in de topconcentratie, als er een eerdere snapshot is.
- Grote koersbewegingen van een positie, vanaf 10% in de recente periode.
- Bevestigde ex-dividenddatums binnen de komende 30 dagen.

Elk aandachtspunt kun je openklappen. Je ziet dan de aanleiding, de ernst, de grenswaarde, de huidige waarde, de eerdere waarde als die er is, en de brongegevens die PDTBar heeft gebruikt.

## Allocatie

Het onderdeel `Allocation` laat zien hoe je portefeuille is opgebouwd, zonder dat je PDT hoeft te openen.

- `Portfolio` toont een compacte allocatiegrafiek.
- `Detailed info` opent de lijst met posities.
- Bij elke positie staan het gewicht in de portefeuille en de waarde, als die beschikbaar zijn.
- In de details van een positie kunnen de recente beweging, het volgende inkomstenmoment, de gemiddelde aankoopprijs, winst of verlies en een kopieerbare identificatiecode staan, als PDT die gegevens levert.
- Onder de lijst met posities staan samenvattingen per sector en per type belegging, als PDT die gegevens levert.

Een aandachtspunt over je allocatie kan in `Pulse` verschijnen. De feiten erachter blijven beschikbaar, ook nadat je het aandachtspunt als gelezen hebt gemarkeerd.

## Inkomsten

Het onderdeel `Income` is een kalenderweergave waar je doorheen kunt bladeren. Er staan ook gebeurtenissen in die geen waarschuwing zijn.

- `Income window` vat samen wat eraan komt.
- `Next income` toont het eerstvolgende dividend- of cashflowmoment.
- PDTBar groepeert latere gebeurtenissen in korte perioden, zoals `This week` en `Later`.
- Per gebeurtenis zie je de datum, de soort, of die bevestigd of geschat is, het bedrag en de verandering, als die informatie beschikbaar is.

Alleen bevestigde ex-dividenddatums binnen de huidige periode van 30 dagen worden aandachtspunten in Pulse. Andere inkomstenmomenten blijven in Income staan.

## Grote bewegingen

Het onderdeel `Big movers` vat recente koersbewegingen samen.

Als een positie de grens van 10% passeert, kan PDTBar die in Pulse tonen met de koers ervoor en erna, de grootte van de beweging en de periode van de brongegevens. Passeert geen enkele positie de grens, dan staat er nog wel hoeveel prijsregels PDTBar heeft gecontroleerd.

Is er een eerdere snapshot, dan vergelijkt PDTBar de huidige positie eerst daarmee. Ontbreken eerdere gegevens, dan gebruikt de app de koershistorie uit PDT.

## Data en prijzen

Het onderdeel `Data` laat zien of de cijfers actueel genoeg zijn voor een snelle blik.

- `Prices` toont of de prijsgegevens actueel, verouderd, onvolledig of onbekend zijn.
- Bij verouderde gegevens kunnen de oudste prijsdatum en de betrokken posities staan.
- Bij onvolledige gegevens kan staan wanneer de laatste aanvulling van de details is afgerond.
- `Data health` verschijnt als de bron niet goed werkt.
- Mislukt het verversen en wil je de oorzaak zoeken, dan kun je de diagnostische gegevens kopiëren.

Gegevens uit de cache kunnen het menu bruikbaar houden terwijl PDTBar op de achtergrond ververst. In het onderdeel Data zie je wanneer dat gebeurt.

## Acties

Met het onderdeel `Actions` blijft dagelijks gebruik kort.

- Met `Refresh now` vraag je PDTBar nieuwe PDT-gegevens op te halen en de laatste details aan te vullen.
- `Open PDT` opent het volledige dashboard van Portfolio Dividend Tracker.
- `Settings...` opent het native instellingenvenster. Daar kun je met `Show portfolio values` de getoonde bedragen van je portefeuille verbergen of weer tonen.
- `Disconnect from PDT` verwijdert de opgeslagen PDT-verbinding.
- `Sign in with PDT` en `Use a PDT token…` verschijnen als PDTBar niet verbonden is of als PDT je vraagt opnieuw verbinding te maken.
- `Check again` controleert de PDT-verbinding opnieuw, bijvoorbeeld nadat je een gepauzeerd PDT-abonnement hebt verlengd.

## Gelezen status

Ongelezen aandachtspunten vullen het statusicoon en staan in Pulse. Markeer je een aandachtspunt als gelezen, dan telt het niet meer mee in Pulse. De feiten erachter blijven staan in Allocation, Income, Big movers of Data.

Verandert het feit later wezenlijk, dan kan het opnieuw verschijnen. Passeert een concentratie bijvoorbeeld opnieuw de grens met wezenlijk andere waarden, dan behandelt PDTBar dat als een nieuw aandachtspunt.

## Privacy en grenzen

PDTBar leest PDT via de API, over een verbinding met alleen leesrechten. Die verbinding staat in de Sleutelhanger van deze Mac. De app draait lokaal en is standaard alleen-lezen.

De instelling `Show portfolio values` verbergt bedragen in het menu, de statustekst, tooltips, toegankelijkheidslabels, grafiekdetails en submenu's. De instelling verwijdert geen opgehaalde snapshots en geen portefeuillegegevens uit de lokale cache. Zet je de instelling weer aan, dan toont PDTBar de bedragen opnieuw vanuit de Pulse die op dat moment in het geheugen staat.

PDTBar plaatst geen orders, verplaatst geen geld, stuurt je portefeuille niet naar een eigen backend en geeft geen financieel advies. De app zet feiten en veranderingen op volgorde. Wat ze betekenen, bepaal jij.

Op de pagina [Installeren](install.nl.md) lees je hoe je PDTBar instelt en voor het eerst gebruikt.
