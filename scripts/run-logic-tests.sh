#!/bin/bash
# Execute VRAIMENT les suites de logique pure, sans Xcode et sans CI.
#
# Pourquoi: ce Mac n'a que les Command Line Tools, donc l'app iOS ne se
# construit qu'a distance. Quand la CI est bloquee, relire son code n'est pas
# une verification. Les regles qui calculent des chiffres (lecture d'annonce,
# duree de cycle, heures de prise) ne dependent que de Foundation: elles
# tournent donc ici, sur les MEMES fichiers de test que la CI, via un faux
# XCTest.
#
# Limite assumee: rien de SwiftUI ni de SwiftData ne passe par la. Ce script
# ne remplace pas la CI, il couvre la partie ou une erreur donne un chiffre
# faux a l'utilisateur.
set -uo pipefail
cd "$(dirname "$0")/.."

SUITES=(
    "ListingParser:LifeOS/Services/ListingParser.swift:LifeOSTests/ListingParserTests.swift"
    "CycleStats:LifeOS/Services/CycleStats.swift:LifeOSTests/CycleStatsTests.swift"
    "MedicationSchedule:LifeOS/Services/MedicationSchedule.swift:LifeOSTests/MedicationScheduleTests.swift"
    "ReminderIDs:LifeOS/Services/ReminderIDs.swift:LifeOSTests/ReminderIDsTests.swift"
    "FrenchTax:LifeOS/Services/FrenchTax.swift:LifeOSTests/FrenchTaxTests.swift"
)

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
total_fail=0

for entry in "${SUITES[@]}"; do
    name="${entry%%:*}"; rest="${entry#*:}"
    src="${rest%%:*}"; tst="${rest#*:}"

    # Les imports XCTest / @testable n'existent pas ici: le shim les remplace.
    # Les tests comptaient sur XCTest pour tirer Foundation: on le remet.
    { echo 'import Foundation'
      sed -e '/^import XCTest$/d' -e '/^@testable import LifeOS$/d' "$tst"
    } > "$work/tests.swift"

    # Un main genere appelle chaque methode test*, comme le ferait XCTest.
    cls=$(grep -oE 'final class [A-Za-z]+' "$tst" | head -1 | awk '{print $3}')
    {
        echo 'import Foundation'
        echo "let suite = $cls()"
        # try? : un test qui scanne le depot leve XCTSkip ici, c'est voulu.
        grep -oE 'func (test[A-Za-z0-9_]+)\(\)' "$tst" | awk '{print $2}' \
            | sed 's/^/try? suite./' | sed 's/$/;/'
        echo 'print("\(checks) contrôles, \(failures.count) échecs — '"$name"'")'
        echo 'for f in failures { print("  " + f) }'
        echo 'exit(failures.isEmpty ? 0 : 1)'
    } > "$work/main.swift"

    if swiftc -O -o "$work/run" "$src" scripts/localtests/Shim.swift \
        "$work/tests.swift" "$work/main.swift" 2>"$work/err"; then
        "$work/run" || total_fail=$((total_fail + 1))
    else
        echo "COMPILATION ÉCHOUÉE — $name"
        grep -E "error:" "$work/err" | head -8
        total_fail=$((total_fail + 1))
    fi
done

echo "---"
if [ "$total_fail" -eq 0 ]; then echo "logique: toutes les suites passent"; else echo "logique: $total_fail suite(s) en échec"; fi
[ "$total_fail" -eq 0 ]
