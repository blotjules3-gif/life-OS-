#!/usr/bin/env python3
"""Pose l'URL de confidentialite et l'URL de support sur la fiche App Store de LifeOS.

Les deux vivent a des endroits DIFFERENTS chez Apple, et c'est le piege:
  - privacyPolicyUrl -> appInfoLocalizations (la fiche de l'app)
  - supportUrl       -> appStoreVersionLocalizations (la version)
Ecrire les deux au meme endroit echoue en silence sur l'un des deux.
"""
import sys, time, json, urllib.request, urllib.error, jwt

KEY_ID = "A86WZYJNN8"
ISSUER = "b55a2f54-1bc5-475c-a591-e07b9b7cc790"
APP    = "6813532133"
B      = "https://api.appstoreconnect.apple.com/"
KEY    = open("/Users/Shared/Claude/.credentials/AuthKey_%s.p8" % KEY_ID).read()


def headers():
    tok = jwt.encode({"iss": ISSUER, "exp": int(time.time()) + 1200,
                      "aud": "appstoreconnect-v1"},
                     KEY, algorithm="ES256",
                     headers={"kid": KEY_ID, "typ": "JWT"})
    return {"Authorization": "Bearer " + tok, "Content-Type": "application/json"}


def call(method, path, body=None, tries=5):
    """L'API d'Apple coupe la connexion assez souvent depuis ce reseau, donc on
    reessaie. Sans ca, un timeout fait croire que l'ecriture a ete refusee."""
    data = json.dumps(body).encode() if body is not None else None
    last = None
    for _ in range(tries):
        req = urllib.request.Request(B + path, data=data, headers=headers(), method=method)
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()[:400]
        except Exception as e:
            last = e
            time.sleep(4)
    return 0, "reseau: %s" % last


def main(privacy_url, support_url):
    # La version encore modifiable. Une version deja envoyee ou en vente est
    # refusee en ecriture (409 INVALID_STATE), ce n'est pas un bug.
    _, vs = call("GET", "v1/apps/%s/appStoreVersions?limit=10" % APP)
    ver = next((v["id"] for v in vs["data"]
                if v["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION"), None)
    if not ver:
        sys.exit("Aucune version en preparation: rien a modifier.")

    _, infos = call("GET", "v1/apps/%s/appInfos?limit=5" % APP)
    info = next(i["id"] for i in infos["data"]
                if i["attributes"]["appStoreState"] == "PREPARE_FOR_SUBMISSION")

    _, locs = call("GET", "v1/appInfos/%s/appInfoLocalizations" % info)
    for loc in locs["data"]:
        s, b = call("PATCH", "v1/appInfoLocalizations/" + loc["id"],
                    {"data": {"type": "appInfoLocalizations", "id": loc["id"],
                              "attributes": {"privacyPolicyUrl": privacy_url}}})
        print("privacyPolicyUrl", loc["attributes"]["locale"], "->", s, "" if s < 300 else b)

    _, vlocs = call("GET", "v1/appStoreVersions/%s/appStoreVersionLocalizations" % ver)
    for loc in vlocs["data"]:
        s, b = call("PATCH", "v1/appStoreVersionLocalizations/" + loc["id"],
                    {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"],
                              "attributes": {"supportUrl": support_url,
                                             "marketingUrl": support_url.rsplit("/", 1)[0] + "/"}}})
        print("supportUrl      ", loc["attributes"]["locale"], "->", s, "" if s < 300 else b)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: set-store-urls.py <url-confidentialite> <url-support>")
    main(sys.argv[1], sys.argv[2])
