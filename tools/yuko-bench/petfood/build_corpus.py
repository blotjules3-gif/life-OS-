#!/usr/bin/env python3
"""Corpus reel d'aliments pour chats, pour mesurer Yuko sans choisir les codes qui marchent.

    python3 tools/yuko-bench/petfood/build_corpus.py

Echantillon SYSTEMATIQUE (pas trie a la main) dans Open Pet Food Facts :
- categorie en:cat-food, vendus en France, tries par nombre de scans : 1 fiche sur 20 ;
- en:cat-treats : 1 fiche sur 7 ;
- recherche "chaton" (fiches souvent mal classees) : 1 sur 3 des 18 premieres ;
- fiches SANS categorie chat ni chien (vendues en France) : 1 sur 2, 15 au plus ;
- le produit de l'utilisateur, 8445290938091 ("one junior").

Pour chaque fiche : le JSON brut de la base (memes champs que l'app) et, si la base n'a
pas la composition ou les valeurs, le texte lu par Vision sur ses photos d'etiquette
CHOISIES (memes reglages que PetLabelReader.recognize : precis, correction de langue,
fr/en/de/es/it/nl). C'est ce que l'app lit sur l'iPhone. Rien n'est envoye a la base.

Sortie : corpus.json ici, copie dans LifeOSTests/petfood-corpus.json (lu par
PetFoodCorpusTests, qui passe chaque fiche dans le vrai code de l'app).
"""
import json, os, shutil, subprocess, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
HOST = "https://world.openpetfoodfacts.org"
IMG = "https://images.openpetfoodfacts.org/images/products"
UA = {"User-Agent": "LifeOS-bench/1.0 (contact via App Store)"}
FIELDS = ("code,product_name,product_name_fr,brands,quantity,image_front_url,image_front_small_url,image_url,"
          "image_small_url,countries_tags,categories_tags,ingredients_text_fr,ingredients_text,additives_tags,"
          "allergens_tags,traces_tags,labels_tags,nutriments,serving_size,last_modified_t,images")

def get(url, timeout=40, raw=False):
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                data = r.read()
                return data if raw else json.loads(data)
        except Exception as e:
            err = e; time.sleep(2 + attempt * 3)
    print("  ! echec", url, err, file=sys.stderr)
    return None

def search(query, n):
    out, page = [], 1
    while len(out) < n:
        d = get(f"{HOST}/api/v2/search?{query}&sort_by=unique_scans_n&page_size=100&page={page}&fields=code")
        if not d or not d.get("products"): break
        out += [p["code"] for p in d["products"] if p.get("code")]
        if page >= d.get("page_count", 1): break
        page += 1
    return out

def path(code):
    d = "".join(c for c in code if c.isdigit())
    if len(d) <= 8: return d
    d = d.zfill(13)
    return f"{d[0:3]}/{d[3:6]}/{d[6:9]}/{d[9:]}"

def ocr(jpg):
    swift = os.path.join(HERE, "ocr.swift")
    r = subprocess.run(["swift", swift, jpg], capture_output=True, text=True, timeout=300)
    return r.stdout.strip() if r.returncode == 0 else None

def main():
    picks = []   # (code, why)
    cat = search("categories_tags_en=cat-food&countries_tags_en=france", 800)
    picks += [(c, f"cat-food France, rang {i + 1}/{len(cat)}") for i, c in enumerate(cat) if i % 20 == 0]
    treats = search("categories_tags_en=cat-treats", 60)
    picks += [(c, f"cat-treats, rang {i + 1}/{len(treats)}") for i, c in enumerate(treats) if i % 7 == 0]
    kit = get(f"{HOST}/cgi/search.pl?search_terms=chaton&json=1&page_size=18&fields=code") or {}
    kit = [p["code"] for p in kit.get("products", []) if p.get("code")]
    picks += [(c, f"recherche « chaton », rang {i + 1}") for i, c in enumerate(kit) if i % 3 == 0]
    # Fiches MAL CLASSEES (aucune categorie chat ni chien), comme « one junior » : c'est la
    # que l'identification se mesure vraiment. Elles peuvent etre pour chien ou autre.
    vague = []
    for page in (1, 2, 3, 4):
        d = get(f"{HOST}/api/v2/search?categories_tags_en=open-pet-food-facts&countries_tags_en=france&sort_by=unique_scans_n&page_size=100&page={page}&fields=code,categories_tags")
        for p in (d or {}).get("products", []):
            tags = " ".join(p.get("categories_tags") or [])
            if p.get("code") and not any(k in tags for k in ("cat-food", "dog-food", "cat-treat", "dog-treat")):
                vague.append(p["code"])
    picks += [(c, f"fiche sans catégorie chat/chien, rang {i + 1}/{len(vague)}") for i, c in enumerate(vague) if i % 2 == 0][:15]
    picks.append(("8445290938091", "produit de l'utilisateur (« one junior »)"))
    seen, corpus = set(), []
    tmp = os.path.join(HERE, ".img"); os.makedirs(tmp, exist_ok=True)
    for code, why in picks:
        if code in seen: continue
        seen.add(code)
        d = get(f"{HOST}/api/v2/product/{code}.json?fields={FIELDS}")
        if not d or d.get("status") != 1:
            corpus.append({"code": code, "why": why, "status": 0}); continue
        p = d["product"]
        ing = p.get("ingredients_text_fr") or p.get("ingredients_text")
        n = p.get("nutriments") or {}
        has_values = any(k in n for k in ("proteins", "proteins_100g", "fat", "fat_100g"))
        entry = {"code": code, "why": why, "status": 1, "product": p, "ocr": []}
        if not ing or not has_values:
            imgs = (p.get("images") or {})
            for kind in ("ingredients", "nutrition"):
                keys = sorted([k for k in imgs if k.startswith(kind + "_")], key=lambda k: (0 if k.endswith("_fr") else 1 if k.endswith("_en") else 2, k))
                if not keys or not imgs[keys[0]].get("rev"): continue
                url = f"{IMG}/{path(code)}/{keys[0]}.{imgs[keys[0]]['rev']}.full.jpg"
                data = get(url, raw=True, timeout=60)
                if not data: entry["ocr"].append({"photo": keys[0], "url": url, "error": "telechargement"}); continue
                f = os.path.join(tmp, f"{code}-{keys[0]}.jpg"); open(f, "wb").write(data)
                text = ocr(f)
                entry["ocr"].append({"photo": keys[0], "url": url, "text": text})
        corpus.append(entry)
        print(f"{code:>14}  {len(entry.get('ocr', []))} photo(s) lue(s)  {why}")
        time.sleep(0.5)
    shutil.rmtree(tmp, ignore_errors=True)
    out = {"built": time.strftime("%Y-%m-%d"), "source": HOST, "method": __doc__.strip().splitlines()[0], "items": corpus}
    json.dump(out, open(os.path.join(HERE, "corpus.json"), "w"), ensure_ascii=False, indent=1)
    shutil.copy(os.path.join(HERE, "corpus.json"), os.path.join(ROOT, "LifeOSTests", "petfood-corpus.json"))
    print(len(corpus), "fiches")

if __name__ == "__main__":
    main()
