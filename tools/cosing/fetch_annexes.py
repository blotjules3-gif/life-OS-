#!/usr/bin/env python3
"""Telecharge les annexes II (interdits) et III (restreints) du reglement cosmetique
(CE) 1223/2009 depuis l'API publique de CosIng (Commission europeenne), et ecrit
LifeOS/Resources/cosing_annexes.tsv : nom INCI | annexe | numero | type.

type = prohibited (annexe II), allergen (annexe III, doit etre declare sur l'etiquette
au-dela d'un seuil), restricted (annexe III, autorise sous conditions).
Seules les entrees qui ont un nom INCI du glossaire sont gardees : ce sont les seules
qu'une etiquette peut porter. Relancer : python3 tools/cosing/fetch_annexes.py
"""
import json, os, sys, time, urllib.request, uuid

API = "https://api.tech.ec.europa.eu/search-api/prod/rest/search?apiKey=285a77fd-1257-4271-8507-f0c6b2961203&text=*&pageSize=100&pageNumber={}"
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "LifeOS", "Resources", "cosing_annexes.tsv")

def page(annex, n):
    q = json.dumps({"bool": {"must": [{"terms": {"itemType": ["substance"]}}, {"terms": {"annexNo": [annex]}}]}})
    b = uuid.uuid4().hex
    body = (f"--{b}\r\nContent-Disposition: form-data; name=\"query\"; filename=\"q.json\"\r\n"
            f"Content-Type: application/json\r\n\r\n{q}\r\n--{b}--\r\n").encode()
    req = urllib.request.Request(API.format(n), data=body, method="POST",
                                 headers={"Content-Type": f"multipart/form-data; boundary={b}"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)
        except Exception as e:
            time.sleep(3 * (attempt + 1)); err = e
    raise err

RES = os.path.join(os.path.dirname(__file__), "..", "..", "LifeOS", "Resources")
INCI = {l.strip().lower() for l in open(os.path.join(RES, "cosing_inci_names.txt")) if l.strip() and not l.startswith("#")}
rows = {}
for annex in ("II", "III"):
    n, total = 1, None
    while True:
        d = page(annex, n)
        total = d.get("totalResults", 0)
        for r in d.get("results", []):
            m = r["metadata"]
            ref = (m.get("refNo") or [""])[0]
            # La condition "a declarer sur l etiquette" peut etre dans n importe quel champ.
            other = json.dumps(m, ensure_ascii=False).lower()
            kind = "prohibited" if annex == "II" else ("allergen" if "indicated in the list of ingredients" in other else "restricted")
            names = list(m.get("nameOfCommonIngredientsGlossary") or [])
            if annex == "II" and not names:
                # L'annexe II n'a presque jamais de nom de glossaire : on garde le nom
                # de substance SEULEMENT s'il existe tel quel dans la liste INCI (sinon
                # aucune etiquette ne peut le porter, inutile de le chercher).
                for raw in m.get("inciName") or []:
                    for part in raw.split(";"):
                        base = part.split(", except")[0].split(" and its salts")[0].replace("(ISO)", "")
                        base = " ".join(base.strip().lower().split())
                        if base in INCI:
                            names.append(base)
            for name in names:
                for part in name.split(";"):
                    inci = " ".join(part.strip().lower().split())
                    if len(inci) < 3 or inci in ("moved or deleted",):
                        continue
                    # Une interdiction l'emporte sur une restriction pour le meme nom.
                    prev = rows.get(inci)
                    rank = {"prohibited": 3, "allergen": 2, "restricted": 1}
                    if prev is None or rank[kind] > rank[prev[2]]:
                        rows[inci] = (annex, ref, kind)
        if n * 100 >= total:
            break
        n += 1
    print(annex, total, file=sys.stderr)

with open(OUT, "w") as f:
    f.write("# CosIng, Commission europeenne (CC BY 4.0). Annexes II et III du reglement (CE) 1223/2009.\n")
    f.write(f"# Genere le {time.strftime('%Y-%m-%d')} par tools/cosing/fetch_annexes.py\n")
    for inci, (annex, ref, kind) in sorted(rows.items()):
        f.write(f"{inci}\t{annex}\t{ref}\t{kind}\n")
from collections import Counter
print(len(rows), Counter(v[2] for v in rows.values()), file=sys.stderr)
