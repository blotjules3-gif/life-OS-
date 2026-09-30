#!/usr/bin/env python3
"""Banc d'essai Yuko: la meme recherche par code que l'app (API v3 universelle
d'Open Food Facts, product_type=all), sur un jeu de codes reproductible.

    python3 tools/yuko-bench/bench.py            # mesure avec codes.json
    python3 tools/yuko-bench/bench.py --refresh  # reconstruit codes.json puis mesure

Mesure separement: reconnu, fiche complete, photo, note calculable, latence.
BIAIS A CONNAITRE: les produits "populaires" viennent de la base elle-meme, donc ils
mesurent la chaine de l'app (normalisation, base universelle, completude), PAS la
couverture de la base. La couverture reelle se mesure avec failed_scans.txt: un
code par ligne, les produits que l'utilisateur n'a pas trouves chez lui.
"""
import json, os, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UA = {"User-Agent": "LifeOS-bench/1.0 (contact via App Store)"}
FIELDS = "code,product_name,product_type,image_front_url,ingredients_text,ingredients_text_fr,nutriments,nutriscore_score,nutriscore_grade,additives_tags"

def get(url, timeout=20):
    t = time.time()
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
            return r.status, r.read(), time.time() - t, r.geturl()
    except urllib.error.HTTPError as e:
        return e.code, e.read(), time.time() - t, url
    except Exception as e:
        return 0, str(e).encode(), time.time() - t, url

def checksum_ok(d):
    if not d.isdigit() or len(d) < 8: return False
    body = [int(c) for c in d[:-1]][::-1]
    s = sum(v * (3 if i % 2 == 0 else 1) for i, v in enumerate(body))
    return (10 - s % 10) % 10 == int(d[-1])

def candidates(raw):
    d = "".join(c for c in raw if c.isdigit() and c.isascii())
    if not 6 <= len(d) <= 14: return []
    can = "0" + d if len(d) == 12 else (d[1:] if len(d) == 14 and d.startswith("0") else d)
    out = [can, d]
    if len(can) == 13 and can.startswith("0"): out.append(can[1:])
    if len(can) == 13 and can.startswith("00000") and checksum_ok(can[-8:]): out.append(can[-8:])
    seen = []
    for c in out:
        if c not in seen: seen.append(c)
    return seen

def popular(query, n):
    q = urllib.parse.urlencode({"q": query, "page_size": n, "sort_by": "-unique_scans_n", "fields": "code,product_name"})
    st, body, _, _ = get("https://search.openfoodfacts.org/search?" + q)
    return [(h["code"], h.get("product_name") or "") for h in json.loads(body).get("hits", [])] if st == 200 else []

def popular_beauty(term, n):
    q = urllib.parse.urlencode({"search_terms": term, "json": 1, "page_size": n, "fields": "code,product_name", "sort_by": "unique_scans_n"})
    st, body, _, _ = get("https://world.openbeautyfacts.org/cgi/search.pl?" + q)
    try: return [(p["code"], p.get("product_name") or "") for p in json.loads(body).get("products", [])] if st == 200 else []
    except Exception: return []

def refresh():
    groups = {
        "aliment": [('categories_tags:"en:breakfast-cereals" countries_tags:"en:france"', 5), ('categories_tags:"en:biscuits" countries_tags:"en:france"', 5),
                    ('categories_tags:"en:yogurts" countries_tags:"en:france"', 5), ('categories_tags:"en:hams" countries_tags:"en:france"', 4),
                    ('categories_tags:"en:chips-and-fries" countries_tags:"en:france"', 4), ('categories_tags:"en:cheeses" countries_tags:"en:france"', 4),
                    ('categories_tags:"en:spreads" countries_tags:"en:france"', 4), ('categories_tags:"en:pastas" countries_tags:"en:italy"', 3),
                    ('categories_tags:"en:chocolates" countries_tags:"en:germany"', 3), ('categories_tags:"en:snacks" countries_tags:"en:united-states"', 3)],
        "boisson": [('categories_tags:"en:sodas" countries_tags:"en:france"', 5), ('categories_tags:"en:waters" countries_tags:"en:france"', 4),
                    ('categories_tags:"en:fruit-juices" countries_tags:"en:france"', 4), ('categories_tags:"en:plant-based-milks"', 3)],
        "complément": [('categories_tags:"en:protein-powders"', 5), ('categories_tags:"en:dietary-supplements"', 5)],
    }
    codes = []
    for kind, qs in groups.items():
        for q, n in qs:
            for c, name in popular(q, n): codes.append({"code": c, "kind": kind, "name": name, "expect": "found"})
            time.sleep(1)
    for term in ["shampoing", "gel douche", "déodorant", "crème hydratante", "dentifrice", "maquillage", "savon"]:
        for c, name in popular_beauty(term, 3): codes.append({"code": c, "kind": "cosmétique", "name": name, "expect": "found"})
        time.sleep(3)
    # Pieges de lecture, construits a partir de vrais codes: la meme fiche doit revenir.
    food13 = [c for c in codes if len(c["code"]) == 13 and c["code"].startswith("0")][:3]
    for c in food13: codes.append({"code": c["code"][1:], "kind": "variante UPC-A", "name": c["name"], "expect": "found"})
    for c in [c for c in codes if len(c["code"]) == 13][:3]: codes.append({"code": "0" + c["code"], "kind": "variante GTIN-14", "name": c["name"], "expect": "found"})
    for c in [c for c in codes if len(c["code"]) == 13][3:5]:
        bad = c["code"][:-1] + str((int(c["code"][-1]) + 1) % 10)
        codes.append({"code": bad, "kind": "chiffre de contrôle faux", "name": c["name"], "expect": "absent"})
    # Temoins hors alimentation (livres, electronique), source independante: Wikidata.
    for c in ["9780812989786", "6941565920362", "6958265174483", "9791035102333", "3616403703607"]:
        codes.append({"code": c, "kind": "témoin hors alimentation", "name": "", "expect": "absent"})
    seen, uniq = set(), []
    for c in codes:
        if c["code"] not in seen: seen.add(c["code"]); uniq.append(c)
    json.dump(uniq, open(os.path.join(HERE, "codes.json"), "w"), ensure_ascii=False, indent=1)
    print(f"codes.json: {len(uniq)} codes")

def lookup(raw):
    tries = []
    for code in candidates(raw):
        for attempt in range(3):
            st, body, dt, final = get(f"https://world.openfoodfacts.org/api/v3/product/{code}?product_type=all&fields={FIELDS}")
            tries.append((code, st, round(dt, 2)))
            if st != 429: break
            time.sleep(30 * (attempt + 1))
        if st == 429: return None, tries, "limité"
        try: prod = json.loads(body).get("product")
        except Exception: prod = None
        if prod: return prod, tries, "beauty" if "openbeautyfacts" in final or prod.get("product_type") == "beauty" else "food"
        time.sleep(0.7)
    return None, tries, None

def scorable(p, base):
    ing = p.get("ingredients_text_fr") or p.get("ingredients_text")
    if base == "beauty": return bool(ing)
    n = p.get("nutriments") or {}
    nutri = p.get("nutriscore_score") is not None or all(n.get(k) is not None for k in ["energy-kcal_100g", "sugars_100g", "saturated-fat_100g", "salt_100g"])
    return bool(ing) and nutri

def main():
    if "--refresh" in sys.argv or not os.path.exists(os.path.join(HERE, "codes.json")): refresh()
    codes = json.load(open(os.path.join(HERE, "codes.json")))
    fp = os.path.join(HERE, "failed_scans.txt")
    if os.path.exists(fp):
        for line in open(fp):
            c = line.split("#")[0].strip()
            if c: codes.append({"code": c, "kind": "échec utilisateur", "name": "", "expect": "found"})
    rows = []
    for c in codes:
        prod, tries, base = lookup(c["code"])
        found = prod is not None
        rows.append({**c, "found": found, "base": base, "tries": tries,
                     "complete": bool(found and (prod.get("product_name")) and (prod.get("ingredients_text") or prod.get("ingredients_text_fr"))),
                     "image": bool(found and prod.get("image_front_url")),
                     "scorable": bool(found and scorable(prod, base)),
                     "latency": round(sum(t[2] for t in tries), 2)})
        time.sleep(0.7)
    json.dump(rows, open(os.path.join(HERE, "results.json"), "w"), ensure_ascii=False, indent=1)
    kinds = sorted(set(r["kind"] for r in rows))
    out = ["# Banc d'essai Yuko", "", f"Mesuré le {time.strftime('%Y-%m-%d %H:%M')}, {len(rows)} codes. Recherche identique à l'app (API v3 universelle).", "",
           "**Biais :** les produits populaires viennent de la base elle-même. Ils mesurent la chaîne de l'app, pas la couverture. La couverture se mesure avec `failed_scans.txt`.", "",
           "| Groupe | Codes | Attendu | Conforme | Fiche complète | Photo | Note calculable | Latence médiane |", "|---|---|---|---|---|---|---|---|"]
    for k in kinds:
        rs = [r for r in rows if r["kind"] == k]
        limited = [r for r in rs if r["base"] == "limité"]
        rs = [r for r in rs if r["base"] != "limité"] or rs
        ok = sum(1 for r in rs if r["found"] == (r["expect"] == "found"))
        f = [r for r in rs if r["found"]]
        lat = sorted(r["latency"] for r in rs)[len(rs) // 2]
        out.append(f"| {k} | {len(rs)}{f' (+{len(limited)} limités)' if limited else ''} | {rs[0]['expect']} | {ok}/{len(rs)} | {sum(r['complete'] for r in f)}/{len(f)} | {sum(r['image'] for r in f)}/{len(f)} | {sum(r['scorable'] for r in f)}/{len(f)} | {lat} s |")
    miss = [r for r in rows if r["base"] != "limité" and r["found"] != (r["expect"] == "found")]
    lim = [r for r in rows if r["base"] == "limité"]
    if lim: out += ["", f"{len(lim)} code(s) non mesurés : la base a limité les requêtes (429) malgré trois essais. Ce ne sont pas des absences."]
    if miss:
        out += ["", "## Non conformes", ""] + [f"- `{r['code']}` ({r['kind']}) {r['name'][:40]} : essais {r['tries']}" for r in miss]
    open(os.path.join(HERE, "REPORT.md"), "w").write("\n".join(out) + "\n")
    print("\n".join(out))

if __name__ == "__main__":
    main()
