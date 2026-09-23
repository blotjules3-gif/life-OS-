#!/bin/bash
# scripts/run-mac.sh — Compile et lance LifeOS en natif sur macOS
set -euo pipefail
cd "/Users/Shared/Claude/apps/lifeos"

echo "=================================================="
echo "  Lancement de LifeOS sur Mac"
echo "=================================================="

# 1. Compilation Mac Catalyst
xcodebuild build \
    -project LifeOS.xcodeproj \
    -scheme LifeOS \
    -destination "platform=macOS,arch=arm64,variant=Mac Catalyst" \
    -derivedDataPath /tmp/lifeos-catalyst \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_ALLOWED=NO || true

# 2. Nettoyage de l'extension widget iOS et signature locale
rm -rf /tmp/lifeos-catalyst/Build/Products/Debug-maccatalyst/LifeOS.app/Contents/PlugIns
codesign --force --deep --sign - /tmp/lifeos-catalyst/Build/Products/Debug-maccatalyst/LifeOS.app

# 3. Installation dans ~/Applications
mkdir -p ~/Applications
rm -rf ~/Applications/LifeOS.app
cp -R /tmp/lifeos-catalyst/Build/Products/Debug-maccatalyst/LifeOS.app ~/Applications/LifeOS.app

# 4. Lancement et mise au premier plan
killall LifeOS 2>/dev/null || true
open ~/Applications/LifeOS.app
sleep 0.5
osascript -e 'tell application "LifeOS" to activate' 2>/dev/null || true

echo "✓ LifeOS est ouvert et disponible dans ~/Applications/LifeOS.app !"
