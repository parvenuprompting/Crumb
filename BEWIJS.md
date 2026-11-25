# Bewijs — Crumb, slice "bruikbaar-1" + whitelist

## Pad
1. Open Crumb vanaf het programmaoverzicht. Het venster moet er staan (vroeger opende het niet).
2. Home: druk op "Scan nu". Binnen enkele seconden moeten de cijfers er staan (ongeveer 2.500 cookies;
   na de reparaties **210** automatisch opruimbaar, 69 op "review").
3. Tijdens de AI-fase: er is een voortgangsteller ("x van y batches") en een knop **Stop scan**; stoppen laat de uitslag staan.
4. Cookies: klik een rij aan → de selectie telt en "Verwijderen…" wordt actief.
5. Instellingen → Whitelist: de 22 dagelijkse diensten staan er, bandlab.com inbegrepen.
6. Instellingen → Automatische schoonmaak → "Dry run" opent een venster met wat er weg zou gaan.

## Bewijs
- Schermafbeelding tijdens de reparatie (dashboard zichtbaar tijdens de scan, **tussenstand 378**
  opruimbaar, Stop-knop): `~/hermes-bewijs/crumb-audit-25nov/screenshots/50-na-fix.png`.
  Dit is de stand van vóór de laatste twee reparaties, niet de eindstand.
- Run-log van de laatste echte app-run (25-11 12:49, `origin: app`): **279** automatisch opruimbaar,
  136 op review, 2.143 behouden — `~/hermes-bewijs/crumb-audit-25nov/run-20261125-124910-898.json`
- Testlog van 25-11 19:51: `xcodebuild test` → **174 tests, 0 failures, TEST SUCCEEDED** —
  `~/hermes-bewijs/crumb-audit-25nov/test-25nov-avond.log`
- Audit van de reviewer: `~/hermes-bewijs/crumb-audit-25nov/gemini-audit.md` (8.785 tekens, finish_reason stop)
- Tegenproeven op de klaar-poort, acht gevallen, zonder modelaanroepen:
  `~/hermes-bewijs/crumb-audit-25nov/poort-tegenproeven-25nov.log`
- Bewijs staat bewust NIET in deze repo: de schermafbeeldingen en run-logs bevatten persoonlijke domeinen.

## Bouwer
Genius / KairOS (Claude-familie) bouwde de slices; Hermes (deepseek-flash) speelde na en repareerde.

## Nagespeeld
Hermes — 2026-11-25. Zelf gedaan op de Mac van T.: app gestart (venster verscheen zonder klik), scan gedraaid,
AI-fase met eigen ogen gezien, op **Stop scan** gedrukt (uitslag bleef, run werd weggeschreven), cookielijst
aangeklikt (selectie + Verwijderen werd actief), Instellingen → Whitelist gecontroleerd.
**Let op:** deze naspeling is van vóór de reparaties van vonnisronde 2 en 3. Stap 6 is niet nagespeeld.

## Reviewer
Vier vonnisrondes. De rekeningen die er liggen, met het id dat bij OpenRouter na te vragen is:

| ronde | model | vonnis | rekening |
|---|---|---|---|
| 1 (hele app) | google/gemini-4-neon | "klaar na deze punten" — drie blokkerende punten | `bewijs/review-20261125-175500.json` (gen-1795625676-GPB5ccnY6Ppu1mltOBjy, $0,036) |
| 2 (na de fix, op `RuleEngine.swift`) | qwen/qwen3.7-flash | GEEN RISICO, ernst laag | `bewijs/review-20261125-191045-l1.json` (gen-1795630194-yGReJCcchZ4FiaMxlpSL) |
| 4 (controle na ronde 3) | qwen/qwen3.7-flash | GEEN RISICO, ernst laag | `bewijs/review-20261125-191230-l1.json` (gen-1795630318-uC9xEXBectmHc) |

Vonnisronde 1: drie blokkerende punten, alle drie gerepareerd — (1) regellaag gaf nooit `safeToClean`,
(2) batches werden alfabetisch op domein gesorteerd en op 25 gekapt, (3) selectie in de cookielijst werd
opgeslokt door een eigen tap-handler.

Vonnisronde 2: vond één **echt** gat in mijn eigen reparatie — een HttpOnly+Secure inlogcookie op een
domein dat óók in de trackerlijst staat (sociaal/advertentieplatform) zou alsnog "opschoonbaar" worden.
Gerepareerd: de functioneel-check staat nu vóór de trackerlijst, met test
`testLoginCookieOnTrackerDomainIsNeverSafeToClean`.

Vonnisronde 3 (tweelaags, 19:08): laag 1 zag een **tweede** restroute — een sessie-inlogcookie (geen
"onthoud mij") op een tracker-domein ging nog langs de guard heen; laag 2 bevestigde dat met
bestand:regel. Gerepareerd: sessiegebonden of beveiligde cookies zijn op een tracker-domein nu review,
nooit automatisch opschoonbaar (test `testSessionLoginOnTrackerDomainIsReviewNotClean`).
**Van ronde 3 ontbreekt de rekening:** die twee aanroepen zijn niet als bestand vastgelegd, dus hun id
is niet meer na te vragen. Dat gat is alleen te dichten door de aanroep te herhalen.

## Uitkomst
- Opruimbare cookies: **3 → 279** van 2.558 na de eerste reparatie — gemeten in de draaiende app
  (run-log 12:49, zie Bewijs), niet uit de tests.
- Na de reparaties van ronde 2 en 3 verwachten de tests **210** automatisch opruimbaar: 69
  sessiegebonden of beveiligde cookies staan nu op "review" in plaats van automatisch weg, omdat ze
  een inlog kunnen zijn. **Die 210 is nog niet in de draaiende app gemeten.**
- Tijdens de scan blijft het dashboard staan; de AI-fase toont voortgang en is te stoppen.
- Venster opent weer bij elke start (state restoration uit).
- Whitelist: 22 domeinen, bandlab.com inbegrepen; tests bewijzen dat ze in geen enkele snelkeuze en niet in
  de automatische schoonmaak voorkomen.
- De klaar-poort (`~/bin/poort.py`, huis-regels §20) weigert een reviewer die alleen als naam in dit
  bestand staat; er moet een ontvangstbewijs met OpenRouter-id liggen, en sinds 25-11 ook een vonnis
  zonder risico en hashes van de genoemde bewijsstukken. Tegenproeven gedaan: zonder bewijs rood, met
  een reviewer uit dezelfde familie rood, met een gewijzigd bewijsbestand rood.

## Niet bewezen
- Een volledige scan tot en met de laatste AI-batch (bewust gestopt).
- De widget.
- Auto-clean in het echt (staat uit tot T. hem zelf test).
- Stap 6, het "Dry run"-venster: niet nagespeeld.
- Een schermafbeelding van de huidige build; de bestaande toont de tussenstand van 378.
- De 210-stand in de draaiende app — die komt nu alleen uit de tests.
- Een naspeling door iemand die de reparaties van ronde 2 en 3 niet zelf bouwde.
- De rekening van vonnisronde 3 (id niet vastgelegd).
