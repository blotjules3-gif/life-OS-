#!/usr/bin/env python3
"""Compare des modeles de vision sur les photos annotees (truth.json).
Mesure: fausse soupe, aliments retrouves, aliments inventes, latence.
Usage: CF_ACCOUNT=... CF_TOKEN=... python3 eval_models.py model1 model2 ..."""
import base64, json, os, sys, time, urllib.request, unicodedata

PROMPT = """Tu regardes une photo de repas. Réponds UNIQUEMENT avec du JSON, sans texte autour.
Format: {"items":[{"name":"...","grams":0,"preparation":"...","confidence":0.0,"alternatives":["..."]}],"question":null}
Règles: un élément par aliment VISIBLE (pas un nom de plat global). name en français, court. grams: portion visible estimée.
preparation: cru, cuit à l'eau, rôti, frit, sauté, en sauce, en soupe... confidence entre 0 et 1.
alternatives: 1 à 3 autres identités plausibles si tu hésites. N'invente pas d'aliment caché.
question: une question courte si un détail change beaucoup les calories (huile, sauce), sinon null."""

def norm(s): return "".join(c for c in unicodedata.normalize("NFD", s.lower()) if unicodedata.category(c) != "Mn")

SYN = {"haricots verts": ["haricot"], "legumes verts sautes": ["legume", "epinard", "feuille", "vert"], "legumes rotis": ["legume", "carotte", "chou-fleur", "champignon", "brocoli"],
       "couscous de mais": ["couscous", "semoule", "mais", "polenta", "tamal"], "poulet roti": ["poulet"], "cuisse de poulet": ["poulet"], "riz blanc": ["riz"],
       "sauce bolognaise": ["bolognaise", "viande", "sauce"], "chips de mais": ["chips", "tortilla", "nacho"], "canette de soda": ["coca", "soda", "canette", "boisson"],
       "bœuf": ["boeuf", "steak", "viande"], "steak": ["steak", "boeuf", "viande"], "tomates cerises": ["tomate"], "salade": ["salade", "laitue", "roquette"],
       "epinards": ["epinard", "salade"], "soupe de legumes": ["soupe", "potage", "bouillon"], "pizza margherita": ["pizza"], "pommes de terre": ["pomme de terre", "patate"],
       "oignons": ["oignon"], "poivrons": ["poivron"], "courgettes": ["courgette"], "chou": ["chou"], "carottes": ["carotte"], "olives": ["olive"], "oeufs": ["oeuf"],
       "thon": ["thon", "poisson"], "frites": ["frite"], "spaghetti": ["spaghetti", "pate"], "petits pois": ["pois"], "brocoli": ["brocoli"], "chou-fleur": ["chou-fleur"], "omelette": ["omelette"]}

def hit(truth_item, names):
    keys = SYN.get(norm(truth_item), [norm(truth_item).split()[0]])
    return any(any(k in n for k in keys) for n in names)

def call(model, img):
    acc, tok = os.environ["CF_ACCOUNT"], os.environ["CF_TOKEN"]
    b64 = base64.b64encode(open(img, "rb").read()).decode()
    body = {"model": model, "max_tokens": 700, "temperature": 0.1, "messages": [{"role": "user", "content": [
        {"type": "text", "text": PROMPT}, {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + b64}}]}]}
    req = urllib.request.Request(f"https://api.cloudflare.com/client/v4/accounts/{acc}/ai/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    t = time.time()
    try:
        r = json.load(urllib.request.urlopen(req, timeout=90))
        return r["choices"][0]["message"]["content"] or "", time.time() - t, None
    except urllib.error.HTTPError as e:
        return "", time.time() - t, f"HTTP {e.code} {e.read()[:200]!r}"
    except Exception as e:
        return "", time.time() - t, str(e)[:200]

def parse(text):
    s, e = text.find("{"), text.rfind("}")
    if s < 0 or e < 0: return None
    try: return json.loads(text[s:e + 1])
    except Exception: return None

truth = json.load(open("truth.json"))
report = {}
for model in sys.argv[1:]:
    rows = []
    for key, t in truth.items():
        text, dt, err = call(model, f"photos/{key}.jpg")
        j = parse(text) if not err else None
        items = (j or {}).get("items") or []
        names = [norm(str(i.get("name", "")) + " " + str(i.get("preparation", ""))) for i in items]
        found = sum(hit(ti, names) for ti in t["items"])
        soup = any("soupe" in n or "potage" in n or "bouillon" in n for n in names)
        rows.append({"photo": key, "ok_json": j is not None, "error": err, "items": [i.get("name") for i in items],
                     "recall": f"{found}/{len(t['items'])}", "false_soup": soup and not t["soup"], "missed_soup": t["soup"] and not soup, "latency": round(dt, 1)})
        time.sleep(0.5)
    rec = sum(int(r["recall"].split("/")[0]) for r in rows) / sum(int(r["recall"].split("/")[1]) for r in rows)
    report[model] = {"json_ok": sum(r["ok_json"] for r in rows), "recall": round(rec, 2), "false_soup": sum(r["false_soup"] for r in rows),
                     "missed_soup": sum(r["missed_soup"] for r in rows), "median_latency": sorted(r["latency"] for r in rows)[len(rows) // 2], "rows": rows}
    print(model, {k: v for k, v in report[model].items() if k != "rows"}, flush=True)
json.dump(report, open("results-models.json", "w"), ensure_ascii=False, indent=1)
