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

Klik op het icoon om het menu te openen. Bovenaan staat een overzichtskaart: `Total portfolio value`, met `CAGR` en `Total increase` als PDT die cijfers heeft. Zonder open posities staat er `No open holdings`.

Het eerste onderdeel is `Pulse`, met de belangrijkste aandachtspunten of `All quiet`. Bij `All quiet` staat `No attention items right now.`, en als je het openklapt zie je `Open holdings`, het gewicht van je grootste posities en hoe actueel je `Prices` zijn.

## Aandachtspunten

Aandachtspunten zijn feiten die een vaste grens zijn gepasseerd. Het zijn geen aanbevelingen.

PDTBar kan op dit moment tonen:

- Positieconcentratie vanaf 20%.
- Sectorconcentratie vanaf 30%.
- Cashallocatie vanaf 10%.
- Een verschuiving van 5% of meer in de topconcentratie, als er een eerdere snapshot is.
- Grote koersbewegingen van een positie, vanaf 10% in de recente periode.
- Bevestigde ex-dividenddatums binnen de komende 30 dagen.

Elk aandachtspunt kun je openklappen. Je ziet dan:

- `Trigger`: de grens die is gepasseerd, zoals `Concentration line crossed`, `Sector concentration line crossed`, `Price move crossed recent-window line` of `Ex-dividend date in income window`.
- `Severity`, `Threshold` en `Current`, en `Prior` als er een eerdere waarde is.
- `Sources`: de PDT-gegevens die PDTBar heeft gebruikt, zoals `Open holdings`, `Sector breakdown`, `Calendar events` of `Price rows`.
- `Mark as read`, waarmee het aandachtspunt niet meer meetelt in Pulse.

## Allocatie

Het onderdeel `Allocation` laat zien hoe je portefeuille is opgebouwd, zonder dat je PDT hoeft te openen.

- `Portfolio` toont een compacte allocatiegrafiek.
- `Full allocation list` opent de lijst met posities. Bij elke positie staat het gewicht in de portefeuille.
- Open je een positie, dan zie je `Worth`, `Price`, `ISIN`, `Recent move`, `Next income`, `Average buy price`, `Gain/loss`, `Gain/loss %` en `Copy identifier`, telkens als PDT die gegevens levert.
- Onder de lijst met posities staan de samenvattingen `Sectors` en `Asset types`, als PDT die gegevens levert.
- Zonder posities staat er `No holdings to show`.

Een aandachtspunt over je allocatie kan in `Pulse` verschijnen. De feiten erachter blijven beschikbaar, ook nadat je het aandachtspunt als gelezen hebt gemarkeerd.

## Inkomsten

Het onderdeel `Income` is een kalenderweergave waar je doorheen kunt bladeren. Er staan ook gebeurtenissen in die geen waarschuwing zijn.

- `Income window` vat samen wat eraan komt.
- `Next income` toont het eerstvolgende dividend- of cashflowmoment.
- PDTBar groepeert latere gebeurtenissen in korte perioden, zoals `This week` en `Later`.
- Open je een gebeurtenis, dan zie je `Date`, `Kind` (zoals `Ex-dividend date` of `Dividend payment date`), `State` (`Confirmed` of `Estimated`), `Amount` en `Change`, als die informatie beschikbaar is.
- Komt er niets aan, dan staat er `No income events in the next window`.

Alleen bevestigde ex-dividenddatums binnen de huidige periode van 30 dagen worden aandachtspunten in Pulse. Andere inkomstenmomenten blijven in Income staan.

## Grote bewegingen

Het onderdeel `Big movers` vat recente koersbewegingen samen.

Als een positie de grens van 10% passeert, kan PDTBar die in Pulse tonen met de koers ervoor en erna, de grootte van de beweging en de periode van de brongegevens. Passeert geen enkele positie de grens, dan staat er nog wel hoeveel prijsregels PDTBar heeft gecontroleerd. Is er nog geen koershistorie, dan staat er `No price history to compare yet`.

Is er een eerdere snapshot, dan vergelijkt PDTBar de huidige positie eerst daarmee. Ontbreken eerdere gegevens, dan gebruikt de app de koershistorie uit PDT.

## Data en prijzen

Het onderdeel `Data` laat zien of de cijfers actueel genoeg zijn voor een snelle blik.

- `Prices` toont of de prijsgegevens actueel, verouderd, onvolledig of onbekend zijn. Zonder posities staat er `No holdings to price`.
- Het submenu van `Prices` toont per positie de laatste prijs uit PDT met de dag waarvoor die geldt, zoals `EUR 1,376.80 on 2026-11-12`. Die dag kan een dag of meer achterlopen op vandaag. Heeft PDT nog geen prijs voor een positie, dan staat er `No price from PDT`. Staat `Show portfolio values` uit, dan is de prijs verborgen maar blijft de datum staan.
- Bij verouderde gegevens staan `Stale holdings` en de datum van `Oldest price`.
- Bij onvolledige gegevens kan `Latest complete detail fill` staan.
- `Data health` verschijnt als de bron niet goed werkt, bijvoorbeeld `Not fetched this session` voordat PDTBar gegevens uit PDT heeft opgehaald. Open je het, dan zie je:
  - `Source`, zoals `PDT, read-only; not fetched this session`.
  - `Access`, zoals `Not checked this session`.
  - `Cache`, met de dag van de laatste synchronisatie.
  - `Prices`, met hoe actueel de prijzen zijn.
  - `Detail fill`, zoals `Not started`.
  - `Read state`, met hoeveel aandachtspunten je als gelezen hebt gemarkeerd.
  - `Diagnostics`, waar `None recorded` staat tot een verversing mislukt. Daarna kopieer je met `Copy diagnostics` de gegevens om de oorzaak te zoeken.

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
