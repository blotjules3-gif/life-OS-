#!/bin/bash
# Pose la cle Notion sur le serveur lifeos-names, puis prouve qu'il lit la table.
#
# La cle se lit dans un fichier, jamais en argument ni a l'ecran:
#   /Users/Shared/Claude/.credentials/notion-lifeos.token   (mode 600)
set -euo pipefail
cd "$(dirname "$0")"
F=/Users/Shared/Claude/.credentials/notion-lifeos.token
[ -s "$F" ] || { echo "Fichier absent ou vide: $F"; exit 1; }
chmod 600 "$F"
tr -d '\n\r ' < "$F" | npx wrangler secret put NOTION_TOKEN >/dev/null
echo "cle posee. verification dans 20 s..."
sleep 20
curl -s "https://lifeos-names.chifandcopt.workers.dev/names?check=$(date +%s)" \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print('source:',d['source'],'| noms:',len(d['names']),'| problemes:',d['problems'] or 'aucun')"
echo "Si la source reste 'fallback': la page Notion n'est pas partagee avec l'integration (menu ... > Connexions)."
