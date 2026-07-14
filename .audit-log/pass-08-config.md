# Passe 08 — Secteur Config / Assets / xcconfig (finale)

Date : 2026-07-13
Fichiers audités : Info.plist (app + widget), LifeOS.entitlements, LifeOSWidgets.entitlements, Config.xcconfig / .example, .gitignore, Localizable.xcstrings
Méthode : lint plist, vérification gitignore, lecture des permissions FR.

## Constatations

### Important (UX)

**I1. `Info.plist` — accents manquants dans 5 permissions système**

Ces chaînes s'affichent verbatim dans les alertes iOS de demande de permission. Sans accents, elles trahissent l'app comme peu soignée.

- `NSCameraUsageDescription` : « avant/apres » → « avant/après »
- `NSFaceIDUsageDescription` : « l'acces a tes donnees personnelles » → « l'accès à tes données personnelles »
- `NSHealthShareUsageDescription` : « ta frequence cardiaque … ton score de recuperation » → « ta fréquence cardiaque … ton score de récupération »
- `NSHealthUpdateUsageDescription` : « tes seances et donnees de sommeil dans Sante » → « tes séances et données de sommeil dans Santé »
- `NSMicrophoneUsageDescription` : « journal de reves vocal » → « journal de rêves vocal »

Fix : chaînes rétablies avec les bons diacritiques. `plutil -lint` valide OK.

## Application

- 2 blocs d'édition dans Info.plist, contenu Unicode propre
- Post-fix : `plutil -lint` OK

## Absents / vérifiés

- **Secrets** : `Config.xcconfig` gitignored, `backend/.env` gitignored, `.example` exceptions préservées
- **Entitlements** (app + widgets) : HealthKit, WeatherKit, time-sensitive notifs, app group `group.lifeos.app` cohérent entre les deux targets — lint OK
- **URL scheme** : `lifeos://` déclaré une seule fois (Info.plist)
- **LSRequiresIPhoneOS + MinimumOSVersion 17.0** : cohérent avec le code (SwiftData, ActivityKit, `@Observable`)
- **Localizable.xcstrings** : 6917 lignes JSON, hors périmètre (auto-généré par Xcode)
- **NSSupportsLiveActivities** : true (nécessaire pour AlarmActivityWidget)
- **UIBackgroundModes** : uniquement `audio` (nécessaire pour le réveil vocal)

## Bilan Config

5 chaînes de permission corrigées, 0 autre problème. Toute la configuration statique est propre : secrets pas commités, entitlements cohérents, minimum OS aligné avec les APIs utilisées.

---

# BILAN GLOBAL — Audit LifeOS 8 passes

| Passe | Secteur | Fixes | Type |
|---|---|---|---|
| 1 | Services | 3 | 1 bug (profil coach), 1 UI (LLM), 1 cohérence |
| 2 | Core | 1 | 1 coquille FR |
| 3 | Shared | 2 | 1 UI (IA), 1 UX (accusé mensonger) |
| 4 | Modules | 1 | 1 UI (IA) |
| 5 | Models | 1 | 1 crash Calendar (force-unwrap) |
| 6 | Widgets | 1 | 1 crash Calendar (force-unwrap) |
| 7 | Backend | 1 | 1 hardening DoS |
| 8 | Config | 5 | 5 coquilles Info.plist |

**Total : 15 fixes.**

Ajouts hors fix :
- `LifeOSTests/UIVocabularySanityTests.swift` — verrou anti-régression sur « LLM » / « IA » dans les strings UI
- `LifeOSTests/UserContextBuilderTests.swift` — vérifie que le profil de vie parvient bien au coach

Grandfathering final : 0. Le sanity test tourne sans dérogation.
