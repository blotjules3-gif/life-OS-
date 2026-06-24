#!/bin/bash
# sync-pote.sh — Push tes changements + récupère ceux de Jules toutes les 15 min.
# Lance dans un Terminal ouvert : bash sync-pote.sh

REPO_DIR=$(dirname "$0")
MA_BRANCHE="pote"
BRANCHE_JULES="jules"

echo "======================================"
echo "  Sync LifeOS — branche : $MA_BRANCHE"
echo "  Ctrl+C pour arrêter"
echo "======================================"
echo ""

cd "$REPO_DIR"

while true; do
    HEURE=$(date '+%H:%M')

    # ── 1. PUSH tes changements ──────────────────────────────────
    CHANGES=$(git status --porcelain | wc -l | tr -d ' ')
    if [ "$CHANGES" -gt "0" ]; then
        git add -A
        git commit -m "sync $HEURE" --quiet
        git push origin "$MA_BRANCHE" --quiet
        echo "[$HEURE] ✓ Tes changements pushés ($CHANGES fichier(s))"
    else
        git push origin "$MA_BRANCHE" --quiet 2>/dev/null
    fi

    # ── 2. RÉCUPÈRE les changements de Jules ────────────────────
    git fetch origin "$BRANCHE_JULES" --quiet

    NOUVEAUX=$(git log HEAD..origin/"$BRANCHE_JULES" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$NOUVEAUX" -gt "0" ]; then
        echo "[$HEURE] Jules a pushé $NOUVEAUX commit(s) — récupération..."
        git merge origin/"$BRANCHE_JULES" --ff-only --no-edit --quiet 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "[$HEURE] ✓ Code de Jules intégré automatiquement"
        else
            echo "[$HEURE] ⚠ Merge manuel nécessaire : git merge origin/$BRANCHE_JULES"
        fi
    fi

    echo "[$HEURE] Prochaine sync dans 15 min..."
    echo ""
    sleep 900
done
