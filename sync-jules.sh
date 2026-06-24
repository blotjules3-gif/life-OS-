#!/bin/bash
# sync-jules.sh — Lance ce script une fois, il push tes changements toutes les 15 min
# et récupère ceux de ton pote automatiquement.

REPO="/Users/blotjules/LifeOS-associe"
MA_BRANCHE="jules"
BRANCHE_POTE="pote"

echo "Sync LifeOS démarré — push toutes les 15 min (Ctrl+C pour arrêter)"
echo ""

while true; do
    cd "$REPO"

    # Récupère les derniers changements du pote sans écraser ton travail
    git fetch origin "$BRANCHE_POTE" --quiet

    NOUVEAUX=$(git log HEAD..origin/"$BRANCHE_POTE" --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [ "$NOUVEAUX" -gt "0" ]; then
        echo "[$(date '+%H:%M')] Ton pote a pushé $NOUVEAUX nouveau(x) commit(s) :"
        git log HEAD..origin/"$BRANCHE_POTE" --oneline
        echo ""
    fi

    # Commit et push tes changements locaux si tu as modifié des fichiers
    CHANGES=$(git status --porcelain | wc -l | tr -d ' ')
    if [ "$CHANGES" -gt "0" ]; then
        git add -A
        git commit -m "sync auto $(date '+%H:%M')" --quiet
        git push origin "$MA_BRANCHE" --quiet
        echo "[$(date '+%H:%M')] Tes changements pushés ($CHANGES fichier(s))"
    fi

    sleep 900  # 15 minutes
done
