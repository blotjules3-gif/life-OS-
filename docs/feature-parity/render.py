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
