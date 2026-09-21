#!/usr/bin/env python3
"""Verifie que chaque modele SwiftData respecte les regles de la synchro iCloud.

iCloud (CloudKit) refuse de synchroniser une base si un seul modele:
  - a une propriete stockee sans valeur par defaut et non optionnelle,
  - a une relation non optionnelle,
  - a une relation vers plusieurs objets sans lien retour cote enfant,
  - utilise @Attribute(.unique).
Et il ne le dit qu'au lancement, sur le telephone. Ce script le dit avant.
"""
import re, glob, sys

BASIC = {"String", "Int", "Double", "Bool", "Date", "UUID", "Data", "Float"}
problems, models = [], {}

for f in glob.glob("LifeOS/**/*.swift", recursive=True) + glob.glob("SharedModels/**/*.swift", recursive=True):
    s = open(f, encoding="utf-8").read()
    # Hors commentaires et hors textes entre guillemets: LocalStore en parle
    # dans un message de diagnostic, ce n'est pas un usage.
    code_only = re.sub(r'"[^"\n]*"', '""', re.sub(r"//.*", "", s))
    if "@Attribute(.unique" in code_only:
        problems.append(f"{f}: @Attribute(.unique) interdit")
    for m in re.finditer(r"@Model\s+(?:final\s+)?class\s+(\w+)[^{]*\{(.*?)\n\}", s, re.S):
        name, body = m.group(1), m.group(2)
        props, depth, pending_attr = [], 0, ""
        for line in body.split("\n"):
            code = line.split("//")[0]
            d = depth
            depth += code.count("{") - code.count("}")
            if d:
                continue
            if re.match(r"\s*@Relationship", code) and "var" not in code:
                pending_attr = code; continue
            mm = re.match(r"\s*(@\w+(?:\([^)]*\))?\s+)?var\s+(\w+)\s*:\s*([^=\{]+?)\s*(=.*)?$", code)
            if not mm:
                pending_attr = ""; continue
            attr = (mm.group(1) or "") + pending_attr
            pending_attr = ""
            if "{" in code and "=" not in code:
                continue                                  # propriete calculee
            props.append((mm.group(2), mm.group(3).strip(), bool(mm.group(4)), attr))
        models[name] = (f, props)

for name, (f, props) in models.items():
    for prop, typ, has_default, attr in props:
        optional = typ.endswith("?")
        base = typ.rstrip("?")
        is_rel = "@Relationship" in attr or (base.strip("[]") in models)
        if is_rel:
            if not optional:
                problems.append(f"{name}.{prop}: relation non optionnelle")
            if base.startswith("[") and "inverse:" not in attr:
                child = base.strip("[]")
                back = [p for p, t, _, _ in models.get(child, ("", []))[1] if t.rstrip("?") == name]
                if not back:
                    problems.append(f"{name}.{prop}: pas de lien retour dans {child}")
        elif not optional and not has_default:
            problems.append(f"{name}.{prop}: {typ} sans valeur par defaut")

print(f"{len(models)} modeles lus")
for p in problems:
    print("  PROBLEME", p)
print("pret pour iCloud" if not problems else f"{len(problems)} probleme(s)")
sys.exit(1 if problems else 0)
