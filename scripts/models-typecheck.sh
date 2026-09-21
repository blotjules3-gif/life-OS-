#!/bin/bash
# Verifie les TYPES des modeles, pas seulement leur syntaxe, sans Xcode.
# Le plugin des macros SwiftData n'existe pas dans les Command Line Tools: on
# retire donc @Model / @Relationship / @Attribute d'une copie et on compile le
# reste contre le SDK macOS. Ca attrape une valeur par defaut du mauvais type,
# un nom introuvable, et tout ce qui empecherait l'app Watch de compiler les
# modeles seuls (ils ne doivent dependre de rien d'autre).
set -uo pipefail
cd "$(dirname "$0")/.."
d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
for f in LifeOS/Models/*.swift; do
python3 - "$f" "$d/$(basename "$f")" <<'PY'
import re,sys
s=open(sys.argv[1],encoding="utf-8").read()
s=re.sub(r"@Model\b","",s)
s=re.sub(r"@Relationship\([^)]*\\[^)]*\)|@Relationship\([^)]*\)","",s)
s=re.sub(r"@Attribute\([^)]*\)","",s)
s=re.sub(r"@Transient\b","",s)
open(sys.argv[2],"w",encoding="utf-8").write(s)
PY
done
out=$(swiftc -typecheck -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos14 "$d"/*.swift 2>&1 | grep "error:" | sed "s|$d/||")
n=$(printf '%s' "$out" | grep -c "error:" || true)
[ -n "$out" ] && echo "$out" | sort -u | head -20
echo "types des modeles: $(ls "$d" | wc -l | tr -d ' ') fichiers, $n erreur(s)"
[ "$n" -eq 0 ]
