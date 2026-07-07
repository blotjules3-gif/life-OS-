# LifeOS — Roadmap d'amélioration

_Généré après audit du 2026-07-07. Priorisation par ROI et impact utilisateur réel._

---

## Résumé du diagnostic

- 35 299 lignes Swift (après purge de ~2 500 lignes RiskCrypto)
- 111 fichiers Swift · 15 God files ≥ 500 lignes
- 4 tests unitaires iOS · 3 tests backend
- 13 accessibilityLabels sur toute l'app
- 141 `try?` non gérés · 15 `catch` avec juste `print()`

Score global de l'audit : **4,5 / 10**. L'app fonctionne, mais elle a des angles morts en accessibilité, tests, et logging.

---

## ✅ Sprint 0 — Fait dans cette session (2026-07-07)

| # | Item | Fichiers | Impact |
|---|---|---|---|
| ✅ | Suppression `CryptoModule.swift` (1258 lignes) | `LifeOS/Modules/CryptoModule.swift` | −1 258 lignes de dette |
| ✅ | Suppression `CryptoData.swift` (12 KB) | `LifeOS/Modules/CryptoData.swift` | −250 lignes |
| ✅ | Purge `cryptoProxyURL` de Configuration | `LifeOS/Services/Configuration.swift` | Config plus claire |
| ✅ | Registre central `AppStorageKeys` | `LifeOS/Services/AppStorageKeys.swift` (nouveau) | Fini les 11× `@AppStorage("appTheme")` |
| ✅ | `accessibilityLabel` sur PhotosPicker chat | `LifeOS/Shared/AIAssistantView.swift` | 1 label en plus |
| ✅ | Emojis retirés des commentaires structurels | `LifeOS/Core/TodayAgenda.swift` | Cohérence règle CLAUDE.md |

**Total gagné :** −1 417 lignes de code inutile · 1 nouveau service central · aucune régression fonctionnelle.

---

## Phase 1 — Sécurité opérationnelle (2-3 sessions)

**But :** ne plus être aveugle en production. Voir quand ça casse, chez qui, pourquoi.

### 1.1 Logging structuré côté iOS (M1, M5)

Migration `print()` + `catch { print(...) }` → `os.Logger` avec catégories (`network`, `data`, `coach`, `speech`).

```swift
import os
let log = Logger(subsystem: "com.blotjules.lifeos", category: "coach")
log.error("createHabit failed: \(error.localizedDescription, privacy: .public)")
```

- 18 `print()` à migrer
- 15 `catch { print(...) }` à passer en `log.error()`
- Créer `LifeOS/Services/AppLogger.swift` avec les catégories définies

### 1.2 Sentry (ou équivalent) branché iOS + backend

- Compte Sentry gratuit (5 000 events/mois)
- SDK iOS : 5 min d'intégration
- SDK Python : 5 min sur FastAPI (middleware)
- Alertes email si crash rate > 1 %

### 1.3 Health check LLM côté backend au boot ✅ (déjà fait)

Endpoint `/health/llm` + log au démarrage — déjà en place.

### 1.4 Gestion propre des `try?` critiques (B2)

**141 occurrences** — impossible de tout gérer d'un coup. Prioriser :
- 20 dans les save SwiftData → passer en `do/catch` + log erreur
- 15 dans les décodage JSON → wrap avec fallback explicite
- 100+ restants dans du glue code peu risqué → laisser mais audit dans phase 3

### 1.5 CI GitHub Actions minimal

- `swift build` + `swift test` sur PR
- Backend : `pytest` + `ruff check`
- Bloque le merge si rouge

---

## Phase 2 — Accessibilité + App Store readiness (1-2 sessions)

**But :** ne pas se faire rejeter à la review App Store.

### 2.1 Accessibility labels systématiques (M2)

- Passe VoiceOver sur les 15 God files : chaque `Button`, `Image`, `Circle` avec sémantique → label
- Objectif : passer de 13 à 100+ labels
- Utiliser Xcode Accessibility Inspector pour QA

### 2.2 Dynamic Type

- Remplacer les `size: XX` fixes par `.font(.body)` / `.footnote` etc. sur les textes de contenu (les titres design peuvent rester fixes)
- Tester en Réglages → Accessibilité → Taille du texte plus grande

### 2.3 Dark mode audit

- Vérifier chaque `Color(hex: 0x...)` : contraste OK en dark ?
- Utiliser `Color("MyToken")` depuis Assets.xcassets pour supporter le light/dark automatiquement
- Écrans à re-tester : ProfileView, ShortcutsHomeView, AIAssistantView

### 2.4 Textes non localisés

- `Localizable.xcstrings` (2 663 lignes) existe mais est peu exploité
- Extraire les strings hardcodés en `String(localized: "chat.placeholder")`
- Prépare une éventuelle EN plus tard

### 2.5 Emojis dans les notifications système

- `AppDelegate.swift:119` — "quand tu peux 😉" dans push notif
- `NutritionModule.swift` — titres notifs "💊 …"
- Décision : garder ou virer pour la version App Store ?

---

## Phase 3 — Refactor architectural (3-5 sessions)

**But :** casser les 5 God files ≥ 1 200 lignes pour redevenir maintenable.

### 3.1 `AIAssistantView.swift` (1 766 lignes) → 5 fichiers

Ordre de découpe :
1. `AIAssistantViewModel.swift` (extraire ~500 lignes)
2. `AIAssistantView+InputArea.swift` (voice, mic, waveform ~400 lignes)
3. `AIAssistantView+MessageCells.swift` (~300 lignes)
4. `CoachTextCleaner.swift` (déjà autonome, 50 lignes)
5. `AIAssistantView.swift` restant (~500 lignes de body principal)

### 3.2 `ShortcutsHomeView.swift` (1 612 lignes) → 4 fichiers

1. `ShortcutsHome+HabitsSection.swift`
2. `ShortcutsHome+MoodSection.swift`
3. `ShortcutsHome+AgendaSection.swift`
4. `ShortcutsHomeView.swift` (structure principale)

### 3.3 `OnboardingView.swift` (1 569 lignes) → un fichier par step

Onboarding = flow avec 8-10 étapes. Chaque step doit être son propre fichier.

### 3.4 `ProfileView.swift` (1 170 lignes) → 3 fichiers

1. `ProfileView+OrbitHero.swift`
2. `ProfileView+Settings.swift`
3. `ProfileView.swift` (structure + facettes)

### 3.5 Migration `@AppStorage` vers `AppStorageKeys`

- 11 `@AppStorage("appTheme")` → `@AppStorage(AppStorageKeys.appTheme)`
- Idem pour `waterGoal`, `userName`, `kcalGoal` (8 occurrences chacun)
- Faisable en 30 min avec find & replace régex

---

## Phase 4 — Tests + confiance (2-3 sessions)

**But :** avoir un filet quand on refacto.

### 4.1 Tests unitaires critiques

Cibles prioritaires :
- `CoachExpertise.detectTopics` — 8 cas (1 par domaine)
- `CoachTextCleaner.clean` — 10 cas (markdown, puces, séparateurs)
- `UserContextBuilder.build(message:)` — snapshot testing
- `SpeechRecognizer` — mock du provider
- Backend : `orchestrator.py` avec messages types
- Backend : `chat.py` endpoint smoke test

Objectif court terme : passer de 4 → 20 tests iOS, 3 → 15 tests backend.

### 4.2 Tests d'intégration chat

Un test qui envoie "combien de protéines par jour" et vérifie que la réponse contient "1.6" ou "2.2". Sinon → alerte.

### 4.3 Snapshot tests UI

Pour les 5 vues les plus visibles (Chat, Profile, Muscu hub, Onboarding step 1, Home).

---

## Phase 5 — Performance + polish (2 sessions)

### 5.1 Lazy loading

- `LifeOSApp.swift` : lazy-init des services (`HealthService.shared`, etc.) au premier usage plutôt qu'au boot
- Modules : `NavigationLink { LazyView(FitnessHubView()) }` pour éviter d'instancier tous les hubs

### 5.2 Cache d'images

- `AsyncImage` sans cache = re-download à chaque render
- Utiliser `Kingfisher` ou un cache maison

### 5.3 Fonts variantes numériques

- Toutes les stats (`123 kcal`, `1h 42`) → `.monospacedDigit()` pour éviter les sautillements

### 5.4 Réduction `.animation`

- Beaucoup de springs redéclarés à la main. Créer `Animation.lifeOSDefault`, `.lifeOSSpring` dans `Theme.swift` et n'utiliser que ça.

---

## Phase 6 — Backend hardening (1-2 sessions)

### 6.1 Splitter `prompts.py` (672 lignes)

Un fichier par persona / module :
- `prompts/system.py`
- `prompts/fitness.py`
- `prompts/nutrition.py`
- `prompts/sleep.py`

### 6.2 Rate limits per user (pas per device)

Actuellement `device_id` : un user avec 2 devices contourne le rate limit. Passer sur user_id.

### 6.3 Prompt caching Mistral

Bloc d'expertise coach = 15k chars mais fixe. Mistral supporte le prompt caching → économie 50-70 % sur les tokens répétés.

### 6.4 Endpoint `/admin/usage`

- Compteur DAU
- Compteur messages/heure
- Latence p50/p95 Mistral
- Coût estimé du jour

---

## Décisions différées (à ne pas faire maintenant)

- **Emojis dans `LocalCoach.swift`** : c'est le fallback offline avec un style volontairement chaleureux. Décision UX à prendre : gardes-tu ce ton ? Ou uniformisation avec le coach principal ?
- **`Localizable.xcstrings` 2 663 lignes** : est-ce que ça marche encore ? Fichier suspect d'être un artefact.
- **Self-hosting LLM** : uniquement quand tu dépasses 5 000 msg/jour de coût, pas avant.
- **Widget coach status** : nice-to-have, pas critique.

---

## Ordre de bataille recommandé

Si tu n'as qu'un après-midi par semaine :

1. **Semaine 1** — Sentry iOS + backend (1.2) → tu vois enfin les crashs
2. **Semaine 2** — Logging structuré (1.1) → tu vois d'où viennent les erreurs
3. **Semaine 3** — Découpe `AIAssistantView` (3.1) → ton fichier le plus critique
4. **Semaine 4** — Tests unitaires CoachExpertise + CoachTextCleaner (4.1) → filet minimum
5. **Semaine 5** — Accessibility labels sur les 3 écrans principaux (2.1)
6. **Semaine 6** — Découpe `ShortcutsHomeView` (3.2)
7. **Semaine 7** — Dynamic Type + dark mode audit (2.2, 2.3)
8. **Semaine 8** — Prompt caching Mistral (6.3) → économie tokens immédiate

Après 2 mois → tu es en A-tier. Aujourd'hui = C+.

---

_Fichier à mettre à jour à chaque fin de session pour tracer l'avancement._
