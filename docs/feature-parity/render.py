#!/usr/bin/env python3
"""Ecrit PARITY.md depuis ledger.json: une ligne par outil, l'etat reel et la preuve.
Relancer apres chaque mise a jour du registre: python3 docs/feature-parity/render.py"""
import json, os, collections

here = os.path.dirname(os.path.abspath(__file__))
rows = json.load(open(os.path.join(here, "ledger.json")))

def short(s, n=90):
    s = (s or "").replace("|", "/").replace("\n", " ").strip()
    return s if len(s) <= n else s[: n - 1] + "…"

def state(r):
    s = r.get("iOS_status", "")
    if s.startswith("partial") or s == "defect_repaired": return "partiel"
    if s.startswith("done"): return "fait"
    return "non commencé"

count = collections.Counter(state(r) for r in rows)
out = [f"# Parité des {len(rows)} outils", "",
       "Généré par `render.py` depuis `ledger.json`. **Aucun outil n'est marqué fait** tant que son test d'acceptation n'a pas tourné sur iPhone ET sur Mac.", "",
       f"État : {count['fait']} fait, {count['partiel']} partiel, {count['non commencé']} non commencé, sur {len(rows)}.", "",
       "| # | Outil | Référence | État | Preuve | Reste à faire |", "|---|---|---|---|---|---|"]
for r in rows:
    proof = r.get("manual_evidence") or r.get("automated_test") or "aucune"
    out.append(f"| {r['tool_id']} | {short(r['name'], 30)} | {short(r['reference_product'], 30)} | {state(r)} | {short(proof)} | {short(r.get('remaining_work'))} |")
open(os.path.join(here, "PARITY.md"), "w").write("\n".join(out) + "\n")
print(f"PARITY.md: {len(rows)} lignes, {dict(count)}")

# --- MATRIX.md : fonctionnalites requises / presentes / manquantes, par outil ---
# Champ "matrix" d'une fiche : [{"feature", "state", "proof"}], state parmi
# tested_auto (present + test automatique), present_untested (present, pas de test ni
# de parcours), device_verified (vu sur un vrai appareil), missing, dependency (bloque
# par un fournisseur, un compte ou un droit Apple). Une fonction non testee reste
# marquee non testee.
LABEL = {"device_verified": "vérifié sur appareil", "tested_auto": "présent, test auto",
         "present_untested": "présent, non testé", "missing": "manquant", "dependency": "dépendance externe"}
m = ["# Matrice des fonctionnalités", "",
     "Généré par `render.py`. États : " + ", ".join(f"**{v}**" for v in LABEL.values()) + ".",
     "Les outils sans matrice ne sont pas encore inventoriés fonction par fonction.", ""]
done_tools = [r for r in rows if r.get("matrix")]
m.append(f"Inventoriés : {len(done_tools)} sur {len(rows)}.")
m.append("")
cat = None
for r in rows:
    if r.get("category") != cat:
        cat = r.get("category"); m += ["", f"## {cat}", ""]
    if not r.get("matrix"):
        m.append(f"- **{r['name']}** : pas encore inventorié.")
        continue
    c = collections.Counter(f["state"] for f in r["matrix"])
    m += ["", f"### {r['name']} ({r.get('reference_product','')})",
          "Résumé : " + ", ".join(f"{LABEL[k]} {c[k]}" for k in LABEL if c[k]), "",
          "| Fonctionnalité | État | Preuve |", "|---|---|---|"]
    for f in r["matrix"]:
        m.append(f"| {short(f['feature'], 70)} | {LABEL[f['state']]} | {short(f.get('proof') or '', 80)} |")
open(os.path.join(here, "MATRIX.md"), "w").write("\n".join(m) + "\n")
print(f"MATRIX.md: {len(done_tools)} outils inventoriés")
