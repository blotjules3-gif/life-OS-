#!/bin/bash
# Controle de syntaxe de tout le code Swift, sans Xcode.
#
# Ce Mac n'a que les Command Line Tools, donc on ne peut pas construire l'app
# iOS ici. Mais `swiftc -parse` n'a besoin d'aucun SDK ni d'aucun import
# resolu: il lit la grammaire. Ca attrape exactement la categorie d'erreur
# qu'un remplacement de texte introduit (accolade en trop, structure coupee),
# sans attendre quatre minutes de CI.
#
# Ce que ca ne remplace PAS: la verification des types. Une vue SwiftUI mal
# typee passe ce controle. C'est un filtre rapide, pas un build.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0
count=0
while IFS= read -r f; do
    count=$((count + 1))
    if ! out=$(swiftc -parse -suppress-warnings "$f" 2>&1); then
        echo "$out" | grep -E "error:" | head -5
        fail=$((fail + 1))
    fi
done < <(find LifeOS LifeOSTests LifeOSWidgets -name '*.swift' 2>/dev/null)

echo "syntaxe: $count fichiers lus, $fail en echec"
[ "$fail" -eq 0 ]
