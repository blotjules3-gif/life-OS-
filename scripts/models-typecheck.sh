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
# AppSchema est exclu: sans @Model les classes ne sont plus des modeles
# SwiftData, donc sa liste ne peut pas typer ici. Elle est lue plus bas.
for f in SharedModels/*.swift; do
[ "$(basename "$f")" = AppSchema.swift ] && continue
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
# Chaque nom de la liste AppSchema doit exister comme classe de modele.
missing=$(python3 - <<'PY2'
import re,glob
src="".join(open(f,encoding="utf-8").read() for f in glob.glob("SharedModels/*.swift"))
listed=re.findall(r"(\w+)\.self",open("SharedModels/AppSchema.swift").read())
declared=set(re.findall(r"@Model\s+(?:final\s+)?class\s+(\w+)",src))
print(" ".join(x for x in listed if x not in declared))
PY2
)
[ -n "$missing" ] && { echo "modeles listes mais introuvables: $missing"; n=$((n+1)); }
echo "liste AppSchema: $(grep -o '\.self' SharedModels/AppSchema.swift | wc -l | tr -d ' ') modeles, tous declares dans SharedModels: $([ -z "$missing" ] && echo oui || echo NON)"
[ "$n" -eq 0 ]
