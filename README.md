# Crumb 🍪

Lokale, privacy-first cookie-manager voor macOS. Leest browser-cookies op het systeem, categoriseert ze via een regel-laag + lokaal Ollama-model, en adviseert welke veilig opschoonbaar zijn — **zonder ooit login/sessie-cookies te verwijderen**.

![CI](https://github.com/parvenuprompting/Crumb/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/swift-5.10-orange)
![Ollama](https://img.shields.io/badge/AI-lokaal%20via%20Ollama-8B5CF6)
![Privacy](https://img.shields.io/badge/privacy-100%25%20lokaal-success)
![License](https://img.shields.io/badge/license-MIT-blue)

## Kernprincipes

1. **Alleen lezen, tenzij expliciet goedgekeurd.** De app verwijdert nooit automatisch iets zonder dat de gebruiker dit per categorie heeft ingeschakeld en de veiligheidsregels het toestaan.
2. **Whitelist wint altijd.** Cookies die op de hard-safelist staan (auth-patronen, gebruikerswhitelist, recente actieve sessies) worden nooit ter beoordeling aan het LLM aangeboden en nooit verwijderd.
3. **Lokaal en privacy-first.** Geen cookie-inhoud verlaat het systeem. Classificatie gebeurt volledig via een lokale Ollama-instantie — en zelfs het LLM ziet alleen metadata (domein, naam, vlaggen), nooit cookie-waarden.
4. **Dubbele goedkeuring.** `safeToClean` ontstaat alleen bij overeenstemming tussen de regel-laag én het LLM. De safelist kan dit altijd blokkeren.

## Ondersteunde browsers

| Browser | Formaat | Toegang |
|---|---|---|
| Chrome / Brave | SQLite (metadata) | bestandstoegang; waarden worden niet ontsleuteld of gelezen |
| Safari | `Cookies.binarycookies` | Full Disk Access (TCC) vereist |
| Firefox | `cookies.sqlite` | Full Disk Access |

## Architectuur

```
Crumb.app (SwiftUI, Dock + menu bar, non-sandboxed)
├── Core/
│   ├── Scanner/          CookieSource-protocol: ChromiumSource, SafariSource, FirefoxSource
│   ├── Categorization/   RuleEngine + gebundelde tracker-domeinenlijst (±50k, EasyPrivacy)
│   ├── Safety/           SafelistEngine + ProtectedCookieStore + DomainRulesEngine
│   ├── Insights/         RecommendationEngine (impact-sorteerde aanbevelingen) + InsightsEngine (score, diff, cross-browser, churn)
│   ├── LLM/              OllamaClient — batched, deterministic, met nette fallback
│   ├── Cleanup/          DeletionEngine + AutoCleanEngine + QuickCleanEngine + CookieBackup + AuditLog
│   ├── Scheduling/       LaunchAgentManager (RunAtLoad + instelbare frequentie)
│   ├── Logging/          JSONRunLog per run
│   └── Model/            CookieRecord, ScanRun, SnapshotStore (churn)
├── Crumb/
│   ├── Views/            Dashboard + aanbevelingen / Cookies (split view + detailpaneel) / Trends (privacy-score) / Instellingen
│   └── Resources/        AppIcon.icns + tracker-domeinenlijst
└── CrumbAgent            CLI-binary in de app-bundle voor de launchd-agent
```

## Builden & Installeren

Project genereren en bouwen:

```bash
brew install xcodegen
xcodegen generate
open Crumb.xcodeproj   # of: xcodebuild -scheme Crumb build
```

Tests draaien:

```bash
xcodebuild -scheme Crumb test -destination 'platform=macOS'
```

Lokaal installeren in `/Applications`:

```bash
xcodebuild -project Crumb.xcodeproj -scheme Crumb -configuration Release -derivedDataPath build/DerivedData build
codesign --force --deep --sign "Apple Development" build/DerivedData/Build/Products/Release/Crumb.app
cp -R build/DerivedData/Build/Products/Release/Crumb.app /Applications/
rm -rf build/
```

## First run

1. Start Crumb — bij de eerste start doorloop je een korte **onboarding**: privacybelofte, browserdetectie, Volledige Schijftoegang (indien nodig voor Safari) en optionele lokale AI. Daarna start de eerste scan. De app verschijnt in het Dock én in de menubalk; sluit je het venster, dan blijft Crumb actief in de menubalk.
2. Safari vereist **Volledige Schijftoegang**: Systeeminstellingen → Privacy & Beveiliging → Volledige Schijftoegang → voeg Crumb toe → herstart Crumb. De app linkt hier naartoe in de onboarding en het Overzicht.
3. Voor AI-classificatie: installeer [Ollama](https://ollama.com) en trek een model, bijvoorbeeld `ollama pull llama3.1:8b`. Zonder Ollama draait alles op de regel-laag; het rapport vermeldt dan expliciet dat AI is overgeslagen.

## Interface

- **Home** is een dashboard: privacy-status, hoofdactie "Veilig opschonen", **aanbevelingen gesorteerd op impact** (veilig op te ruimen, ouder dan 90 dagen, terugkerende trackers, top-trackingdomeinen), snelkeuzes en **live scanvoortgang** met per-browserstatus.
- **Cookies** is een **split view**: compacte lijst links (filterchips, sorteren op ouderdom/churn, bulk-whitelist) en een **detailpaneel** rechts met volledige uitleg, metadata, churn en acties (verwijderen, whitelist, alleen deze cookie beschermen, vergelijkbare cookies bekijken).
- **Trends** toont een **privacy-score** met uitleg, veranderingen t.o.v. de vorige run (nieuw/verdwijnen, trackerdruk in %), cross-browser duplicaten, churn-top en hardnekkige tracking-domeinen.
- Elk advies verklaart zichzelf: "Beschermd: naam bevat 'session'", "Review vereist: secure + httpOnly + jonger dan 24 uur", "Niet verwijderd: AI en regellaag zijn het niet eens", "Verwijderbaar: tracker, ouder dan 30 dagen, geen bescherming".

## Snelkeuzes (1-klik opschonen)

Op de **Home**-pagina biedt Crumb 4 interactieve snelkeuzes waarmee specifieke cookie-groepen in 1 klik veilig opgeruimd kunnen worden:

1. **Tracking & Marketing**: verwijdert direct alle advertentie- en tracker-cookies.
2. **Oude Analytics (> 30d)**: ruimt analysecookies op die al meer dan een maand niet ververst zijn.
3. **Alles Opschoonbaar**: verwijdert alle cookies die unaniem als `safeToClean` zijn beoordeeld.
4. **Onbekend & verlopen**: ruimt ongeclassificeerde cookies op die verlopen of sessiegebonden zijn.

Elke snelkeuze toont een live teller, vraagt expliciete bevestiging via een preview-sheet, controleert of actieve browsers gesloten zijn, en logt elke actie naar `audit.jsonl`.

## Veiligheidslaag

- **Auth-patronen** (`session`, `token`, `sid`, `__Secure-`, `__Host-`, …) → altijd vergrendeld.
- **Gebruikerswhitelist** (bank, werk-SSO, e-mail) → altijd vergrendeld, los van elk advies. Invoer zoals `https://bank.nl/login` of `WWW.Bank.nl` wordt automatisch genormaliseerd naar `bank.nl`; import/export via Instellingen.
- **Recente actieve sessies** (secure + httpOnly + jonger dan 24 uur) → maximaal `reviewSuggested` en nooit in bulk-voorselekten (snelkeuzes en auto-clean nemen deze cookies nooit mee).
- **Back-up vóór verwijdering.** Elke verwijderingsactie schrijft eerst de volledige rijen weg naar een lokaal back-upbestand (alleen-lezen voor de eigenaar). Lukt de back-up niet, dan wordt er niet verwijderd. Herstellen kan via Instellingen → Back-ups (browser moet gesloten zijn); bewaartermijn instelbaar (7–365 dagen of voor altijd).
- **Domeinregels.** Fijnmaziger dan de whitelist: per domein altijd bewaren, altijd als tracking markeren, cookies ouder dan X dagen opschonen, of een specifieke cookienaam beschermen/opschonen — optioneel per browser. Beschermde cookies raken regels nooit.
- **Handmatige cookie-bescherming.** In het detailpaneel kan één specifieke cookie (domain|name|path) permanent beschermd worden.
- **Auto-clean** is opt-in per categorie met veiligheidskleppen: **dry-run preview**, limiet per run (standaard 100), optionele startdrempel ("pas opruimen bij minstens 20 veilige cookies") en instelbare agent-frequentie (1/3/6/12 uur). Elke verwijdering wordt geback-upt en gelogd; de agent-notificatie vermeldt ook het aantal geblokkeerde/mislukte cookies. Het **audit-log** is doorzoekbaar, filterbaar en exporteerbaar als CSV/JSON.

## Tracker-lijst

De gebundelde lijst (`tracker-domains.txt`, ±50.000 domeinen) combineert handmatige entries met domeinen uit [EasyPrivacy](https://easylist.to/easylist/easyprivacy.txt). Bekende infrastructuur-/SSO-domeinen (Google, Apple, Microsoft, Okta, sociale platformen, …) worden nooit als tracker opgenomen. Bijwerken:

```bash
./scripts/update-tracker-list.sh
```

## Logs

Elke run schrijft een JSON-rapport naar `~/Library/Application Support/Crumb/logs/`. Verwijderingen worden gelogd in `audit.jsonl` (wat, wanneer, welke regel/LLM-uitspraak). Rapporten en back-ups worden automatisch opgeruimd na 90 dagen; handmatig opruimen kan nog steeds via Instellingen.

## Distributie (Developer ID + notarization)

```bash
# eenmalig: notarytool-profiel aanmaken
xcrun notarytool store-credentials CrumbNotary \
  --apple-id "jij@example.com" --team-id VJ9D2C765N --password <app-specific password>

./scripts/build-release.sh
```

Het script bouwt Release, tekent met hardened runtime (inclusief de embedded `CrumbAgent`), dient in bij Apple-notarization en neemt het ticket op (staple). De app is **niet sandboxed** — distributie buiten de Mac App Store.

## Roadmap

- [x] Fase 1–3 — Scanner (Chrome, Brave, Safari, Firefox) + regel-laag + safelist
- [x] Fase 4 — Ollama-classificatie met consensus-regels
- [x] Fase 5 — Trends & run-geschiedenis
- [x] Fase 6 — LaunchAgent (RunAtLoad + elke 3 uur)
- [x] Fase 7 — Handmatige verwijdering + opt-in auto-clean + audit-log
- [x] Fase 8 — Developer ID-signing + notarization (`scripts/build-release.sh`)
- [x] Fase 9 — Verharding & beheer: dubbele goedkeuring afgedwongen, back-ups + herstellen, Safari-parser (canoniek binarycookies-formaat), trackerlijst via EasyPrivacy, whitelist-normalisatie, churn-detectie, log-/back-uprotatie, agent-notificaties, per-cookie acties, CI-releaseverificatie
- [x] Fase 10 — Vertrouwen & inzichten: onboarding, dashboard met impact-gesorteerde aanbevelingen, cookie-detailpaneel, verklarende adviezen, scanvoortgang, domeinregels, auto-clean dry-run/limiet/drempel, instelbare planning, audit-log filteren/exporteren, privacy-score, cross-browser duplicaten, nieuw/verdwijnen-diff, handmatige cookie-bescherming
- [x] Fase 9 — Homepage met interactieve snelkeuzes voor 1-klik opschonen

## Over de maker

Ik ben Tiëndo, vrachtwagenchauffeur. Ik bouw dit project in mijn eentje, in de avonden naast fulltime werk. Vragen? Open een issue.

## Licentie

Dit project is gelicentieerd onder de [MIT-licentie](LICENSE).
