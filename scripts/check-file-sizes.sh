#!/usr/bin/env bash
# Rapport soft des fichiers Swift > 500 lignes (dette God file).
# Sortie exit=0 même en cas de dépassement — juste un signal visuel.
# Pour bloquer la CI : passer STRICT=1 en variable d'env.

set -uo pipefail
cd "$(dirname "$0")/.."

THRESHOLD="${THRESHOLD:-500}"
STRICT="${STRICT:-0}"

echo "==> Fichiers Swift > $THRESHOLD lignes (God files candidats)"
echo

OVERSIZED=$(find LifeOS -type f -name "*.swift" -exec wc -l {} \; \
  | awk -v t="$THRESHOLD" '$1 > t' \
  | sort -rn)

if [ -z "$OVERSIZED" ]; then
  echo "OK — aucun fichier > $THRESHOLD lignes"
  exit 0
fi

echo "$OVERSIZED"
echo
COUNT=$(echo "$OVERSIZED" | wc -l | tr -d ' ')
echo "==> $COUNT fichier(s) au-dessus du seuil"

if [ "$STRICT" = "1" ]; then
  echo "STRICT=1 → exit 1"
  exit 1
fi
exit 0
