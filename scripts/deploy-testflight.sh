#!/bin/bash
# scripts/deploy-testflight.sh — Construit LifeOS en Release et l'envoie sur TestFlight
set -euo pipefail

echo "=================================================="
echo "  Déploiement LifeOS vers TestFlight"
echo "=================================================="

REPO_DIR="/Users/Shared/Claude/apps/lifeos"
cd "$REPO_DIR"

KEY_ID="A86WZYJNN8"
ISSUER_ID="b55a2f54-1bc5-475c-a591-e07b9b7cc790"
TEAM_ID="Z7M8K465B9"
KEY_PATH="/Users/Shared/Claude/.credentials/AuthKey_${KEY_ID}.p8"
P12_PATH="/Users/Shared/Claude/.credentials/chifbay-distribution.p12"
P12_PW_PATH="/Users/Shared/Claude/.credentials/chifbay-distribution.p12.password"
APP_PROFILE="/Users/Shared/Claude/.credentials/lifeos-app.mobileprovision"
WIDGETS_PROFILE="/Users/Shared/Claude/.credentials/lifeos/lifeos-widgets.mobileprovision"

# 1. Vérification des identifiants
for f in "$KEY_PATH" "$P12_PATH" "$P12_PW_PATH" "$APP_PROFILE" "$WIDGETS_PROFILE"; do
    if [ ! -f "$f" ]; then
        echo "❌ Fichier manquant: $f"
        exit 1
    fi
done

# Copie de la clé dans ~/private_keys pour xcodebuild
mkdir -p ~/private_keys
cp "$KEY_PATH" ~/private_keys/AuthKey_${KEY_ID}.p8

# 2. Installation des profils de provisioning
PROV_DIR=~/Library/MobileDevice/Provisioning\ Profiles
mkdir -p "$PROV_DIR"
cp "$APP_PROFILE" "$PROV_DIR/3ab63838-c590-42e7-a800-c9bf898cef93.mobileprovision"
cp "$WIDGETS_PROFILE" "$PROV_DIR/c80f2d3b-db81-425d-b14b-a0ab8abf4677.mobileprovision"
cp "$APP_PROFILE" "$PROV_DIR/lifeos-app.mobileprovision"
cp "$WIDGETS_PROFILE" "$PROV_DIR/lifeos-widgets.mobileprovision"
echo "✓ Profils de provisioning installés."

# 3. Préparation du trousseau (keychain)
KC="/tmp/lifeos-build.keychain-db"
KCPW="lifeos"
rm -f "$KC"
security create-keychain -p "$KCPW" "$KC"
security set-keychain-settings -lut 7200 "$KC"
security unlock-keychain -p "$KCPW" "$KC"

# Téléchargement du certificat racine intermédiaire Apple WWDR G3 si nécessaire
if [ ! -f "/tmp/AppleWWDRCAG3.cer" ]; then
    curl -s -f https://www.apple.com/certificateauthority/AppleWWDRCAG3.cer -o /tmp/AppleWWDRCAG3.cer
fi
security import /tmp/AppleWWDRCAG3.cer -k "$KC" >/dev/null 2>&1 || true

CERT_PW=$(cat "$P12_PW_PATH")
security import "$P12_PATH" -k "$KC" -P "$CERT_PW" -T /usr/bin/codesign -T /usr/bin/security
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KCPW" "$KC" >/dev/null 2>&1

CURRENT_KCS=$(security list-keychains -d user | tr -d '"')
security list-keychains -d user -s "$KC" $CURRENT_KCS
echo "✓ Certificat de distribution configuré."

# 4. Calcul du numéro de build (soit passé en argument, soit calculé depuis TestFlight API)
if [ -n "${1:-}" ]; then
    BUILD_NUMBER="$1"
else
    echo "Récupération du dernier numéro de build sur TestFlight..."
    LAST_BUILD=$(node --input-type=module -e "
import crypto from 'node:crypto';
import fs from 'node:fs';

const KEY_ID = '$KEY_ID';
const ISSUER = '$ISSUER_ID';
const key = fs.readFileSync('$KEY_PATH', 'utf8');
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

const now = Math.floor(Date.now() / 1000);
const head = b64({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' });
const body = b64({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key, dsaEncoding: 'ieee-p1363' });
const token = head + '.' + body + '.' + sig.toString('base64url');

try {
  const res = await fetch('https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6813532133&sort=-uploadedDate&limit=1', {
    headers: { Authorization: 'Bearer ' + token }
  });
  const data = await res.json();
  const v = data.data?.[0]?.attributes?.version;
  console.log(v || '10');
} catch(e) {
  console.log('10');
}
")
    BUILD_NUMBER=$((LAST_BUILD + 1))
fi

echo "→ Numéro de version du build pour TestFlight : $BUILD_NUMBER"

# 5. Création de l'Archive Xcode
ARCHIVE_PATH="/tmp/LifeOS.xcarchive"
rm -rf "$ARCHIVE_PATH"
echo "Compilation et archivage de LifeOS (Release)..."
xcodebuild archive \
    -project LifeOS.xcodeproj \
    -scheme LifeOS \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER_ID" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Apple Distribution"

echo "✓ Archive générée avec succès."

# 6. Export et Upload sur TestFlight
EXPORT_PLIST="/tmp/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>uploadSymbols</key><true/>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.chifandco.lifeos</key><string>LifeOS AppStore</string>
    <key>com.chifandco.lifeos.widgetsextension</key><string>LifeOS Widgets AppStore</string>
  </dict>
</dict>
</plist>
PLIST

EXPORT_DIR="/tmp/lifeos-export"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "Envoi de l'application vers TestFlight..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -exportPath "$EXPORT_DIR" \
    -authenticationKeyPath "$KEY_PATH" \
    -authenticationKeyID "$KEY_ID" \
    -authenticationKeyIssuerID "$ISSUER_ID"

echo "=================================================="
echo "🎉 Build $BUILD_NUMBER téléversé avec succès !"
echo "Traitement Apple et rattachement automatique à TestFlight..."
echo "=================================================="

node --input-type=module -e "
import crypto from 'node:crypto';
import fs from 'node:fs';

const KEY_ID = '$KEY_ID';
const ISSUER = '$ISSUER_ID';
const key = fs.readFileSync('$KEY_PATH', 'utf8');
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

function getToken() {
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' });
  const body = b64({ iss: ISSUER, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key, dsaEncoding: 'ieee-p1363' });
  return head + '.' + body + '.' + sig.toString('base64url');
}

async function run() {
  for (let attempt = 0; attempt < 25; attempt++) {
    await new Promise(r => setTimeout(r, 15000));
    try {
      const res = await fetch('https://api.appstoreconnect.apple.com/v1/builds?filter[app]=6813532133&filter[version]=$BUILD_NUMBER', {
        headers: { Authorization: 'Bearer ' + getToken() }
      });
      const data = await res.json();
      const b = data.data?.[0];
      if (!b) {
        console.log('Réception par Apple en cours...');
        continue;
      }
      const state = b.attributes?.processingState;
      console.log('Statut du build $BUILD_NUMBER:', state);
      if (state === 'VALID') {
        const buildId = b.id;
        await fetch('https://api.appstoreconnect.apple.com/v1/builds/' + buildId, {
          method: 'PATCH',
          headers: { Authorization: 'Bearer ' + getToken(), 'Content-Type': 'application/json' },
          body: JSON.stringify({ data: { type: 'builds', id: buildId, attributes: { usesNonExemptEncryption: false } } })
        });
        const grpRes = await fetch('https://api.appstoreconnect.apple.com/v1/apps/6813532133/betaGroups', {
          headers: { Authorization: 'Bearer ' + getToken() }
        });
        const grpData = await grpRes.json();
        for (const grp of (grpData.data || [])) {
          await fetch('https://api.appstoreconnect.apple.com/v1/betaGroups/' + grp.id + '/relationships/builds', {
            method: 'POST',
            headers: { Authorization: 'Bearer ' + getToken(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ data: [{ type: 'builds', id: buildId }] })
          });
          console.log('✓ Rattaché au groupe TestFlight:', grp.attributes.name);
        }
        console.log('✨ Build $BUILD_NUMBER officiellement en ligne sur ton téléphone !');
        return;
      }
    } catch (e) {
      console.error(e.message);
    }
run();
"

echo ""
echo "=================================================="
echo "  Mise à jour automatique de LifeOS sur Mac"
echo "=================================================="
"$REPO_DIR/scripts/run-mac.sh" || true
