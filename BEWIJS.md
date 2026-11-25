# Bewijs — Crumb, slice "bruikbaar-1" + whitelist

## Pad
1. Open Crumb vanaf het programmaoverzicht. Het venster moet er staan (vroeger opende het niet).
2. Home: druk op "Scan nu". Binnen enkele seconden moeten de cijfers er staan (2558 cookies, 378 veilig op te ruimen).
3. Tijdens de AI-fase: er is een voortgangsteller ("x van y batches") en een knop **Stop scan**; stoppen laat de uitslag staan.
4. Cookies: klik een rij aan → de selectie telt en "Verwijderen…" wordt actief.
5. Instellingen → Whitelist: de 22 dagelijkse diensten staan er, bandlab.com inbegrepen.
6. Instellingen → Automatische schoonmaak → "Dry run" opent een venster met wat er weg zou gaan.

## Bewijs
- Schermafbeelding na de fix (dashboard zichtbaar tijdens de scan, 378 opruimbaar, Stop-knop):
  `~/hermes-bewijs/crumb-audit-25nov/screenshots/50-na-fix.png`
- Schermafbeelding whitelist (22 domeinen, bandlab.com erbij): `computer_use_04e445428cec4eeba0a4ea829c1a89e1.png`
- Audit van de reviewer: `~/hermes-bewijs/crumb-audit-25nov/gemini-audit.md` (8.785 tekens, finish_reason stop)
- Tests: `xcodebuild test` → **172 tests, 0 failures** (was 164; 3 batching-toetsen herschreven, 5 toegevoegd)
- Bewijs staat bewust NIET in deze repo: de schermafbeeldingen bevatten persoonlijke domeinen.

## Bouwer
Genius / KairOS (Claude-familie) bouwde de slices; Hermes (deepseek-flash) speelde na en repareerde.

## Nagespeeld
Hermes — 2026-11-25. Zelf gedaan op de Mac van T.: app gestart (venster verscheen zonder klik), scan gedraaid,
AI-fase met eigen ogen gezien, op **Stop scan** gedrukt (uitslag bleef, run werd weggeschreven), cookielijst
aangeklikt (selectie + Verwijderen werd actief), Instellingen → Whitelist gecontroleerd.

## Reviewer
google/gemini-4-neon — ontvangstbewijs: `bewijs/review-20261125-175500.json`
(OpenRouter-id `gen-1795625676-GPB5ccnY6Ppu1mltOBjy`, na te vragen bij OpenRouter: model, kosten, tijdstip).

Vonnisronde 1 (audit van de hele app): "klaar na deze punten" — drie blokkerende punten, alle drie gerepareerd:
(1) regellaag gaf nooit `safeToClean`, (2) batches werden alfabetisch op domein gesorteerd en op 25 gekapt,
(3) selectie in de cookielijst werd opgeslokt door een eigen tap-handler.

Vonnisronde 2 (na de fix, op `RuleEngine.swift`): vond één **echt** gat in mijn eigen reparatie — een
HttpOnly+Secure inlogcookie op een domein dat óók in de trackerlijst staat (sociaal/advertentieplatform)
zou alsnog "opschoonbaar" worden. Gerepareerd: de functioneel-check staat nu vóór de trackerlijst, met
test `testLoginCookieOnTrackerDomainIsNeverSafeToClean`. 173 tests groen.

## Uitkomst
- Opruimbare cookies: **3 → 279** van 2558 na de eerste reparatie (gemeten in de draaiende app,
  niet uit de tests). Na de tweede reviewerbevinding blijven er **210** automatisch opruimbaar:
  69 sessiegebonden of beveiligde cookies staan nu op "review" in plaats van automatisch weg,
  omdat ze een inlog kunnen zijn.
- Tijdens de scan blijft het dashboard staan; de AI-fase toont voortgang en is te stoppen.
- Venster opent weer bij elke start (state restoration uit).
- Whitelist: 22 domeinen, bandlab.com inbegrepen; tests bewijzen dat ze in geen enkele snelkeuze en niet in
  de automatische schoonmaak voorkomen.
- De klaar-poort (`~/bin/poort.py`, huis-regels §20) weigert een reviewer die alleen als naam in dit
  bestand staat; er moet een ontvangstbewijs met OpenRouter-id liggen. Tegenproef gedaan: zonder bewijs
  rood, met een reviewer uit dezelfde familie rood.
Vonnisronde 3 (tweelaags, 19:08): laag 1 (`qwen3.7-flash`, $0,0005) zag een **tweede** restroute —
een sessie-inlogcookie (geen "onthoud mij") op een tracker-domein ging nog langs de guard heen. Laag 2
(`gemini-4-neon`, $0,045) bevestigde dat met bestand:regel. Gerepareerd: sessiegebonden of beveiligde
cookies zijn op een tracker-domein nu review, nooit automatisch opschoonbaar (test
`testSessionLoginOnTrackerDomainIsReviewNotClean`, 174 tests groen). Daarna vonnisronde 4: laag 1
oordeelde `GEEN RISICO` (ernst laag, $0,0008) — geen opschaling nodig.

- **Niet bewezen:** een volledige scan tot en met de laatste AI-batch (bewust gestopt), de widget, en
  auto-clean in het echt (staat uit tot T. hem test).
