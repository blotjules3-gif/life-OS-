# Sentry — brancher l'observabilité LifeOS

Objectif : voir les crashs et erreurs en prod côté iOS et côté backend FastAPI
sans construire notre propre infra. Sentry gratuit tient 5 000 événements/mois.

---

## 1. Créer le projet

1. Aller sur https://sentry.io → *Create Project*
2. Créer DEUX projets distincts :
   - `lifeos-ios` (platform: Swift / iOS)
   - `lifeos-backend` (platform: Python / FastAPI)
3. Noter les deux DSN dans un endroit sûr (jamais commités en clair).

---

## 2. iOS — intégration

### 2.1 Ajouter le package

Dans Xcode : **File → Add Packages…**

- URL : `https://github.com/getsentry/sentry-cocoa`
- Version : *Up to Next Major* depuis 8.30.0
- Target : `LifeOS` (pas les widgets)

### 2.2 Initialiser au démarrage

Ouvrir `LifeOS/Core/AppDelegate.swift`, ajouter dans `application(_:didFinishLaunchingWithOptions:)` :

```swift
import Sentry

SentrySDK.start { options in
    options.dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN_IOS") as? String
    options.debug = false
    options.tracesSampleRate = 0.1         // 10 % des traces perf
    options.profilesSampleRate = 0.05
    options.enableAppHangTracking = true
    options.enableAutoPerformanceTracing = true
    options.attachStacktrace = true
    // Pas de PII — on n'envoie pas l'IP ni l'e-mail.
    options.sendDefaultPii = false
}
```

### 2.3 Stocker le DSN hors dépôt

Dans `LifeOS/Config.xcconfig` (déjà présent, hors git) :

```
SENTRY_DSN_IOS = https:////xxxxxxx@o1234567.ingest.sentry.io/1234567
```

Attention : **les `/` doivent être doublés dans un `.xcconfig`** — sinon c'est vu
comme un commentaire. La double barre `//` devient `/` après lecture.

Puis dans `LifeOS/Info.plist` :

```xml
<key>SENTRY_DSN_IOS</key>
<string>$(SENTRY_DSN_IOS)</string>
```

Vérifier que `Config.xcconfig` est bien dans `.gitignore` (déjà le cas).

### 2.4 Envoyer manuellement une erreur pour vérifier

Ajouter temporairement dans le corps de `LifeOSApp` :

```swift
SentrySDK.capture(message: "Boot OK depuis LifeOS")
```

Lancer l'app une fois, vérifier que l'événement apparaît dans Sentry, puis retirer la ligne.

### 2.5 Lier avec AppLogger

`os.Logger` n'est pas capté automatiquement par Sentry. Pour les erreurs
critiques, utiliser explicitement :

```swift
} catch {
    AppLog.data.error("save failed: \(error.localizedDescription, privacy: .public)")
    SentrySDK.capture(error: error)
}
```

Ne PAS envoyer toutes les erreurs — seulement celles qu'on n'attend pas.

---

## 3. Backend — intégration

### 3.1 Dépendance

Dans `backend/requirements.txt` :

```
sentry-sdk[fastapi]>=1.45.0
```

Puis `pip install -r requirements.txt` en local + push pour redéploiement Railway.

### 3.2 Initialiser au démarrage

Ouvrir `backend/app/main.py`, ajouter tout en haut du fichier (avant `configure_logging`) :

```python
import os
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

if dsn := os.getenv("SENTRY_DSN_BACKEND"):
    sentry_sdk.init(
        dsn=dsn,
        traces_sample_rate=0.1,
        profiles_sample_rate=0.05,
        send_default_pii=False,
        integrations=[FastApiIntegration(), StarletteIntegration()],
        release=os.getenv("RAILWAY_GIT_COMMIT_SHA", "dev"),
        environment=os.getenv("RAILWAY_ENVIRONMENT", "prod"),
    )
```

### 3.3 Variable d'environnement Railway

Dashboard Railway → Project → Variables → **New Variable** :

- Nom : `SENTRY_DSN_BACKEND`
- Valeur : DSN Python obtenu à l'étape 1

Redéployer. Le premier boot avec la clé loggera implicitement un "sentry.init"
dans les logs Railway — c'est la confirmation.

### 3.4 Test manuel

Créer une route de test protégée par debug :

```python
@app.get("/debug/sentry-test")
async def sentry_test():
    if not settings.debug:
        return {"detail": "disabled"}
    raise RuntimeError("Test Sentry manuel — à ignorer")
```

L'appeler UNE fois avec `curl`. Vérifier dans Sentry backend que l'exception apparaît. Retirer la route.

---

## 4. Alertes

Sentry → *Alerts* → *Create Alert Rule* :

**Alerte 1 — Crash rate iOS > 1 %**
- When: An issue is first seen
- Filter: platform = cocoa, level = fatal
- Frequency: > 5 événements en 1h
- Send to: e-mail

**Alerte 2 — Backend 500 spike**
- When: An event is seen
- Filter: platform = python, level = error
- Frequency: > 20 événements en 15 min
- Send to: e-mail

---

## 5. Ne PAS envoyer à Sentry

- Toutes les entrées utilisateur brut (messages, notes) — reste local
- Les tokens APNs
- Les clés API (backend `.env`)
- Les données HealthKit
- Les valeurs des `@AppStorage` (l'utilisateur peut les avoir personnalisées)

Sentry SDK filtre déjà pas mal via `send_default_pii=False`, mais rester vigilant
dans les `SentrySDK.capture(...)` explicites.

---

## 6. Après le branchement

Ouvrir Sentry chaque jour pendant la première semaine pour :
- Identifier les erreurs récurrentes silencieuses
- Ajouter les `SentrySDK.capture(error:)` sur les paths critiques révélés
- Ajuster le sample rate si le quota gratuit se remplit trop vite

Coût estimé : 0 € tant qu'on reste sous 5 000 events/mois. Solo utilisateur =
plusieurs mois de marge.
