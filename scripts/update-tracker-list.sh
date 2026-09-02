#!/bin/zsh
# Crumb — tracker-domeinenlijst bijwerken
#
# Voegt de domeinen uit EasyPrivacy (cookie-/trackingregels) samen met de
# bestaande handmatige lijst, dedupliceert en sorteert. De laag in
# Core/Categorization/TrackerList.swift matcht alleen exacte domeinen en hun
# suffixen, dus regels met wildcards/paden worden weggefilterd.
#
# Gebruik: ./scripts/update-tracker-list.sh
#
# Bron: https://easylist.to/easylist/easyprivacy.txt (EasyPrivacy, GPLv3).

set -euo pipefail

cd "$(dirname "$0")/.."

LIST="Crumb/Resources/tracker-domains.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> EasyPrivacy ophalen"
curl -fsSL "https://easylist.to/easylist/easyprivacy.txt" -o "$TMP/easyprivacy.txt"

echo "==> Bestaande handmatige lijst behouden"
grep -v '^#' "$LIST" | grep -v '^$' > "$TMP/manual.txt" || true

echo "==> Domeinen extraheren uit EasyPrivacy"
# Regels als '||domein.tld^$third-party' of '||domein.tld/path^' → domein.tld
sed -nE 's/^\|\|([A-Za-z0-9.-]+)([$^/].*)?$/\1/p' "$TMP/easyprivacy.txt" \
  | tr '[:upper:]' '[:lower:]' \
  | grep -E '^[a-z0-9-]+(\.[a-z0-9-]+)+$' \
  | grep -vE '^[0-9.]+$' \
  | sort -u > "$TMP/extracted.txt"

echo "==> Beschermdomeinen eruit filteren (infrastructuur, SSO, betalen)"
# EasyPrivacy bevat kale entries als 'google.com' (script-regels, geen cookies).
# Een kandidaat valt weg als hij zelf beschermd is óf eindigt op een beschermd
# suffix: cookies op deze platforms zijn vrijwel altijd functioneel/auth.
PROTECTED='google\.com|apple\.com|icloud\.com|microsoft\.com|live\.com|office\.com|office365\.com|microsoftonline\.com|bing\.com|msn\.com|windows\.net|googleapis\.com|googleusercontent\.com|gstatic\.com|amazon\.com|amazonaws\.com|github\.com|githubusercontent\.com|gitlab\.com|mozilla\.org|firefox\.com|ubuntu\.com|debian\.org|cloudflare\.com|stripe\.com|paypal\.com|shopify\.com|squarespace\.com|wix\.com|wikipedia\.org|wikimedia\.org|stackoverflow\.com|stackexchange\.com|discord\.com|spotify\.com|netflix\.com|dropbox\.com|box\.com|zoom\.us|slack\.com|adobe\.com|oracle\.com|ibm\.com|sap\.com|salesforce\.com|workday\.com|okta\.com|auth0\.com|onelogin\.com|duo\.com|1password\.com|bitwarden\.com|lastpass\.com|facebook\.com|instagram\.com|whatsapp\.com|messenger\.com|twitter\.com|x\.com|linkedin\.com|youtube\.com|reddit\.com|pinterest\.com|tiktok\.com'

echo "==> Samenvoegen en beschermde domeinen eruit filteren"
# Filter over de samengevoegde lijst, zodat eerder binnengeslopen
# beschermde domeinen ook weer verdwijnen.
cat "$TMP/manual.txt" "$TMP/extracted.txt" \
  | grep -vE "(^|\.)(${PROTECTED})$" \
  | sort -u > "$TMP/merged.txt"

BEFORE=$(grep -vc '^#' "$LIST" | tr -d ' ')

{
  echo "# Crumb tracker-domeinen"
  echo "# Gegenereerd door scripts/update-tracker-list.sh (EasyPrivacy + handmatige aanvullingen)."
  echo "# Gegenereerd: $(date -u +%Y-%m-%d)"
  echo "# Beschermd: bekende infrastructuur-/SSO-domeinen worden nooit als tracker opgenomen."
  echo "#"
  cat "$TMP/merged.txt"
} > "$LIST"
AFTER=$(grep -vc '^#' "$LIST" | tr -d ' ')
echo "==> Klaar: $BEFORE → $AFTER domeinen in $LIST"
