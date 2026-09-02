# Crumb 🍪

Lokale, privacy-first cookie-manager voor macOS. Leest browser-cookies op het systeem, categoriseert ze via een regel-laag + lokaal Ollama-model, en adviseert welke veilig opschoonbaar zijn — **zonder ooit login/sessie-cookies te verwijderen**.

![CI](https://github.com/parvenuprompting/Crumb/actions/workflows/ci.yml/badge.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black)
![Swift](https://img.shields.io/badge/swift-5.10-orange)
![Ollama](https://img.shields.io/badge/AI-lokaal%20via%20Ollama-8B5CF6)
![Privacy](https://img.shields.io/badge/privacy-100%25%20lokaal-success)
![License](https://img.shields.io/badge/license-TBD-lightgrey)

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
│   ├── Categorization/   RuleEngine + gebundelde tracker-domeinenlijst
│   ├── Safety/           SafelistEngine — hard-block vóór alles
│   ├── LLM/              OllamaClient — batched, async, met nette fallback
│   ├── Cleanup/          DeletionEngine + AutoCleanEngine + AuditLog
│   ├── Scheduling/       LaunchAgentManager (RunAtLoad + 3-uurlijkse StartInterval)
│   ├── Logging/          JSONRunLog per run
│   └── Model/            CookieRecord, ScanRun, SnapshotStore
├── Crumb/
│   ├── Views/            Overzicht / Cookies / Trends / Instellingen (monochroom)
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

1. Start Crumb — het hoofdvenster opent direct, de app verschijnt in het Dock en het menu-barpictogram (gestippelde cirkel) verschijnt rechtsboven terwijl de eerste scan direct begint. Sluit je het venster, dan blijft Crumb actief in de menubalk.
2. Safari vereist **Volledige Schijftoegang**: Systeeminstellingen → Privacy & Beveiliging → Volledige Schijftoegang → voeg Crumb toe → herstart Crumb. De app linkt hier naartoe in het Overzicht.
3. Voor AI-classificatie: installeer [Ollama](https://ollama.com) en trek een model, bijvoorbeeld `ollama pull llama3.1:8b`. Zonder Ollama draait alles op de regel-laag; het rapport vermeldt dan expliciet dat AI is overgeslagen.

## Veiligheidslaag

- **Auth-patronen** (`session`, `token`, `sid`, `__Secure-`, `__Host-`, …) → altijd vergrendeld.
- **Gebruikerswhitelist** (bank, werk-SSO, e-mail) → altijd vergrendeld, los van elk advies.
- **Recente actieve sessies** (secure + httpOnly + jonger dan 24 uur) → maximaal `reviewSuggested`.
- **Auto-clean** is opt-in per categorie (aanbevolen: alleen marketing/tracking, ouder dan X dagen, unanieme goedkeuring) en schrijft een audit-logregel per verwijdering.

## Logs

Elke run schrijft een JSON-rapport naar `~/Library/Application Support/Crumb/logs/`. Verwijderingen worden gelogd in `audit.jsonl` (wat, wanneer, welke regel/LLM-uitspraak). Opruimen van oude logs is een expliciete handmatige actie in Instellingen.

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
