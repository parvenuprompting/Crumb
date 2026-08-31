#!/bin/zsh
# Crumb — release-build: Developer ID-signing + notarization (fase 8)
#
# Vereist:
#   - XcodeGen (brew install xcodegen)
#   - Developer ID Application-certificaat in de keychain
#   - Een notarytool keychain-profiel (eenmalig aanmaken):
#       xcrun notarytool store-credentials CrumbNotary \
#         --apple-id "jij@example.com" --team-id VJ9D2C765N --password <app-specific password>
#
# Gebruik:
#   ./scripts/build-release.sh
#
# Omgevingsvariabelen (optioneel):
#   SIGNING_IDENTITY   standaard: "Developer ID Application"
#   NOTARY_PROFILE     standaard: "CrumbNotary"
#   TEAM_ID            standaard: VJ9D2C765N

set -euo pipefail

cd "$(dirname "$0")/.."

SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-CrumbNotary}"
TEAM_ID="${TEAM_ID:-VJ9D2C765N}"
BUNDLE_ID="nl.tiendo.crumb"

echo "==> Project genereren"
xcodegen generate

echo "==> Release-build"
xcodebuild -project Crumb.xcodeproj -scheme Crumb -configuration Release \
  -derivedDataPath build/DerivedData \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  build

APP="build/DerivedData/Build/Products/Release/Crumb.app"

echo "==> Handmatige handtekening (hardened runtime, embedded agent meegetekend)"
codesign --force --deep --sign "$SIGNING_IDENTITY" \
  --options runtime \
  --identifier "$BUNDLE_ID" \
  "$APP"

echo "==> Verificatie handtekening"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute "$APP" || true

echo "==> Notarization (dit kan enkele minuten duren)"
ZIP="build/Crumb.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Ticket vastnemen (staple)"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Klaar: $APP"
echo "    Distributie: zip de .app met 'ditto -c -k --keepParent' en deel die."
