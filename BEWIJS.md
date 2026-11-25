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
google/gemini-4-neon (andere familie dan de bouwer) — vonnis: "klaar na deze punten", drie blokkerende punten.
Alle drie nagerekend in de code en gerepareerd: (1) regellaag gaf nooit `safeToClean`, (2) batches werden
alfabetisch op domein gesorteerd en op 25 gekapt, (3) selectie in de cookielijst werd opgeslokt door een
eigen tap-handler.

## Uitkomst
- Opruimbare cookies: **3 → 378** van 2558 (gemeten in de draaiende app, niet uit de tests).
- Tijdens de scan blijft het dashboard staan; de AI-fase toont voortgang en is te stoppen.
- Venster opent weer bij elke start (state restoration uit).
- Whitelist: 22 domeinen, bandlab.com inbegrepen; tests bewijzen dat ze in geen enkele snelkeuze en niet in
  de automatische schoonmaak voorkomen.
- **Niet bewezen:** een volledige scan tot en met de laatste AI-batch (bewust gestopt), de widget, en
  auto-clean in het echt (staat uit tot T. hem test).
