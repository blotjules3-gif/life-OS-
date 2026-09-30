#!/usr/bin/env python3
"""Construit les cours Trilingo depuis Tatoeba (phrases traduites par des humains,
licence CC BY 2.0 FR). Un cours = une paire source -> cible.

    python3 tools/trilingo/build_courses.py fra eng spa deu ...

Pour chaque paire: phrases courtes avec leur traduction humaine, classees par
difficulte (rang de frequence de leurs mots dans la langue cible), coupees en jours
de 12 phrases et unites de 10 jours. Un cours n'est declare COMPLET qu'a partir de
180 jours ET au moins 8 000 paires; sinon il est publie PARTIEL avec son nombre exact de jours.
Sortie: LifeOS/Resources/Trilingo/<src>-<tgt>.json et manifest.json.
Rien n'est genere par une IA: chaque phrase et sa traduction viennent de Tatoeba,
avec leur identifiant pour l'attribution.
"""
import bz2, collections, json, os, re, sys, time, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "LifeOS", "Resources", "Trilingo")
CACHE = os.path.join(HERE, ".cache")
UA = {"User-Agent": "LifeOS-content/1.0 (contact via App Store)"}
PER_DAY, DAYS_PER_UNIT, FULL_DAYS, MAX_DAYS = 12, 10, 180, 240
NO_SPACES = {"jpn", "cmn", "yue", "wuu", "tha", "khm", "lao", "mya"}

def fetch(url, path):
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r, open(path + ".part", "wb") as f:
            f.write(r.read())
        os.rename(path + ".part", path)
    return path

def sentences(lang):
    p = fetch(f"https://downloads.tatoeba.org/exports/per_language/{lang}/{lang}_sentences.tsv.bz2", f"{CACHE}/{lang}_sentences.tsv.bz2")
    out = {}
    with bz2.open(p, "rt", encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            if len(c) >= 3: out[int(c[0])] = c[2]
    return out

def links(src, tgt):
    p = fetch(f"https://downloads.tatoeba.org/exports/per_language/{src}/{src}-{tgt}_links.tsv.bz2", f"{CACHE}/{src}-{tgt}_links.tsv.bz2")
    with bz2.open(p, "rt", encoding="utf-8") as f:
        return [tuple(map(int, l.split("\t")[:2])) for l in f if l.strip()]

def audio_ids(lang):
    try:
        p = fetch(f"https://downloads.tatoeba.org/exports/per_language/{lang}/{lang}_sentences_with_audio.tsv.bz2", f"{CACHE}/{lang}_audio.tsv.bz2")
        with bz2.open(p, "rt", encoding="utf-8") as f:
            return {int(l.split("\t")[0]) for l in f if l.strip()}
    except Exception:
        return set()

def transcriptions(lang):
    """id -> {script: texte}. cmn: Latn = pinyin, Hans/Hant = l'autre ecriture;
    jpn: Hrkt = lecture en kana avec [kanji|lecture]."""
    out = collections.defaultdict(dict)
    try:
        p = fetch(f"https://downloads.tatoeba.org/exports/per_language/{lang}/{lang}_transcriptions.tsv.bz2", f"{CACHE}/{lang}_tr.tsv.bz2")
    except Exception:
        return out
    with bz2.open(p, "rt", encoding="utf-8") as f:
        for line in f:
            c = line.rstrip("\n").split("\t")
            if len(c) >= 5: out[int(c[0])][c[2]] = c[4]
    return out

TONES = {"a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ"}

def pinyin_marks(text):
    """"You3 ren2 lai2 le5." -> "Yǒu rén lái le." (regles usuelles: a/e d'abord, puis "ou", sinon la derniere voyelle)."""
    def syl(m):
        body, tone = m.group(1).replace("v", "ü").replace("u:", "ü"), int(m.group(2))
        if tone == 5 or tone == 0: return body
        low = body.lower()
        if "a" in low: i = low.index("a")
        elif "e" in low: i = low.index("e")
        elif "ou" in low: i = low.index("o")
        else: i = max(low.rfind(v) for v in "aeiouü")
        if i < 0: return body
        ch = low[i]
        mark = TONES[ch][tone - 1]
        return body[:i] + (mark.upper() if body[i].isupper() else mark) + body[i + 1:]
    return re.sub(r"([A-Za-züÜv:]+)([0-5])", syl, text)

def kana(hrkt):
    # "[弾|ひ]" -> "ひ", "[場所|ば|しょ]" -> "ばしょ"
    return re.sub(r"\[([^|\]]+)\|([^\]]+)\]", lambda m: m.group(2).replace("|", ""), hrkt)

def tokens(text, lang):
    t = text.lower()
    if lang in NO_SPACES: return [c for c in t if c.isalnum()]
    return re.findall(r"[^\W\d_]+(?:['’][^\W\d_]+)?", t)

def jaccard(a, b):
    return len(a & b) / max(1, len(a | b))

def build(src, tgt, src_sent):
    tgt_sent = sentences(tgt)
    tr = transcriptions(tgt) if tgt in ("cmn", "jpn") else {}
    pairs = {}
    for a, b in links(src, tgt):
        if a in src_sent and b in tgt_sent:
            # Chinois: sinogrammes SIMPLIFIES seulement (Tatoeba melange les deux
            # ecritures; une phrase simplifiee porte une transcription "Hant").
            if tgt == "cmn" and "Hant" not in tr.get(b, {}): continue
            s, t = src_sent[a], tgt_sent[b]
            n = len(tokens(t, tgt))
            limit = (4, 22) if tgt in NO_SPACES else (2, 10)
            if not (limit[0] <= n <= limit[1]) or len(s) > 90 or len(t) > 90: continue
            key = t.strip().lower()
            if key not in pairs:
                entry = {"sid": a, "tid": b, "s": s.strip(), "t": t.strip()}
                if tgt == "cmn" and "Latn" in tr.get(b, {}): entry["tr"] = pinyin_marks(tr[b]["Latn"])
                if tgt == "jpn" and "Hrkt" in tr.get(b, {}): entry["tr"] = kana(tr[b]["Hrkt"])
                pairs[key] = entry
    items = list(pairs.values())
    toks = [set(tokens(p["t"], tgt)) for p in items]
    freq = collections.Counter(w for ts in toks for w in ts)
    ranked = [w for w, _ in freq.most_common()]
    index = collections.defaultdict(list)
    for i, ts in enumerate(toks):
        for w in ts: index[w].append(i)
    aud = audio_ids(tgt)
    # Progression par le VOCABULAIRE: les mots sont introduits du plus frequent au
    # plus rare (~10 par jour). Une phrase n'entre que si tous ses mots sont deja
    # introduits, et elle doit apporter au moins un mot pas encore VU dans une phrase.
    # Sans ca, les 2 880 phrases les plus faciles restaient toutes en A1.
    new_per_day = 14 if tgt in NO_SPACES else 10
    introduced, seen, used, days, pos = set(), set(), set(), [], 0
    def fits(i): return toks[i] <= introduced
    while len(days) < MAX_DAYS and pos < len(ranked):
        chosen = []
        for _ in range(12):  # elargit le vocabulaire du jour tant qu'il manque des phrases
            batch = ranked[pos:pos + new_per_day]; pos += new_per_day
            introduced.update(batch)
            fresh_words = introduced - seen
            cands = {i for w in fresh_words for i in index[w] if i not in used and fits(i)}
            if len(cands) >= PER_DAY or pos >= len(ranked): break
        order = sorted(cands, key=lambda i: (-min(3, len(toks[i] - seen)), len(toks[i])))
        day_seen = set()
        for i in order:
            if len(chosen) >= PER_DAY: break
            if not (toks[i] - seen - day_seen) and len(chosen) >= PER_DAY // 2: continue
            if all(jaccard(toks[i], toks[j]) < 0.7 for j in chosen):
                chosen.append(i); day_seen |= toks[i]
        if len(chosen) < PER_DAY // 2:
            if pos >= len(ranked): break
            continue
        used.update(chosen)
        day_words = sorted({w for i in chosen for w in toks[i]} - seen, key=lambda w: freq[w], reverse=True)
        seen.update(w for i in chosen for w in toks[i])
        n = len(seen)
        level = ("A1" if n <= 300 else "A2" if n <= 800 else "B1" if n <= 1500 else "B2") if tgt in NO_SPACES \
            else ("A1" if n <= 600 else "A2" if n <= 1500 else "B1" if n <= 3000 else "B2")
        days.append({"day": len(days) + 1, "unit": len(days) // DAYS_PER_UNIT + 1, "level": level,
                     "items": [{**items[i], "audio": items[i]["tid"] in aud} for i in chosen], "words": day_words[:20],
                     "known": n})
    known = seen
    complete = len(days) >= FULL_DAYS and len(items) >= 8000
    status = "complet" if complete else ("partiel" if days else "vide")
    course = {"source": src, "target": tgt, "version": time.strftime("%Y.%m.%d"), "status": status, "days": days,
              "license": "Phrases, traductions et enregistrements : Tatoeba (tatoeba.org), licence CC BY 2.0 FR. Identifiants conservés pour l'attribution.",
              "noSpaces": tgt in NO_SPACES}
    os.makedirs(OUT, exist_ok=True)
    if days:
        json.dump(course, open(os.path.join(OUT, f"trilingo_{src}-{tgt}.json"), "w"), ensure_ascii=False, separators=(",", ":"))
    return {"target": tgt, "status": status, "days": len(days), "pairs": len(items), "knownWords": len(known),
            "withAudio": sum(p["audio"] for d in days for p in d["items"])}

def main():
    src, targets = sys.argv[1], sys.argv[2:]
    src_sent = sentences(src)
    manifest_path = os.path.join(OUT, "trilingo_manifest.json")
    manifest = json.load(open(manifest_path)) if os.path.exists(manifest_path) else {"source": src, "courses": {}}
    for t in targets:
        try: r = build(src, t, src_sent)
        except Exception as e: r = {"target": t, "status": "erreur", "days": 0, "pairs": 0, "error": str(e)[:120]}
        manifest["courses"][t] = r
        print(r, flush=True)
        time.sleep(1)
    manifest["builtAt"] = time.strftime("%Y-%m-%d")
    json.dump(manifest, open(manifest_path, "w"), ensure_ascii=False, indent=1)

if __name__ == "__main__":
    main()
