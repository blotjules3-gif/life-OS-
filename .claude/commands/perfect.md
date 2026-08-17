---
description: perfect — Passe LifeOS au niveau app parfaite (4 tiers d'améliorations, exécution autonome)
argument-hint: [tier1|tier2|tier3|tier4|all]
---

# perfect — App LifeOS niveau professionnel

Mode autonome multi-tiers. Exécute les améliorations qui font passer LifeOS d'une app "qui marche" à une app "parfaite" (soumissable App Store, présentable investisseur, différenciée sur son marché).

**Argument :** `/perfect tier1|tier2|tier3|tier4|all` — défaut = `tier1`

---

## Contexte de départ (déjà fait)

- `AppLogger.swift` créé (9 catégories `os.Logger`)
- `AppStorageKeys.swift` créé + adopté sur 263 sites
- `LifeStatusTile.swift` créé (composant Home unifiée réutilisable)
- `LifeSignalSyncer.swift` créé (Mood + Sleep + Nutrition syncers agrégats en App Group)
- `ModuleUsageTracker.swift` créé (mesure usage réel des modules)
- `UserContextBuilder` enrichi : 7 insights cross-modules pour le coach
- 30+ migrations `print()` / `catch { print }` / `try? save()` vers `AppLog` structuré
- 64 fonts safes migrées vers tokens Dynamic Type
- 15+ couleurs sémantiques migrées dans les modules
- 39 `accessibilityLabel` ajoutés (20 → 59)
- Build validé (`xcodebuild build` = SUCCEEDED)
- Tests validés (`xcodebuild test` = SUCCEEDED, 30+ tests)
- Documentation Sentry créée (`docs/observability/SENTRY_SETUP.md`)

Ce qui suit = ce qui manque pour l'objectif "app parfaite".

---

## TIER 1 — Bloquants App Store (12h, à faire absolument)

Sans ces items, la review App Store rejette. Ordre :

### 1.1 Privacy Manifest (2h)
Créer `LifeOS/PrivacyInfo.xcprivacy` (format XML plist) déclarant :
- Types de données collectées (UserDefaults keys, HealthKit, notifications)
- API sensibles utilisées avec justification (`NSPrivacyAccessedAPIReasons`)
- Domaines de tracking (aucun)
Obligatoire depuis mai 2024.

### 1.2 Suppression compte + data (2h)
Ajouter écran dans `ProfileView` : bouton "Supprimer mes données" qui :
- Confirmation double
- Efface tous les modèles SwiftData (fetch + delete cascade)
- Reset UserDefaults (garder onboarding pour éviter re-flow)
- Efface `ImageStore.dir` (photos avant/après, docs)
- Efface backups horodatés
Obligatoire selon guidelines Apple 5.1.1(v).

### 1.3 Politique confidentialité hébergée (1h)
`docs/privacy.html` existe. Ajouter dans `Info.plist` la clé `NSPrivacyPolicyURL` pointant vers l'URL publique. Créer une entrée dans ProfileView "Confidentialité" qui ouvre l'URL en Safari.

### 1.4 Copie App Store rédigée FR (2h)
Créer `docs/appstore/description-fr.md` avec :
- Titre (30 char max)
- Sous-titre (30 char max)
- Description (4000 char)
- Mots-clés (100 char)
- What's new (500 char)
Angle : "coach de vie IA qui voit tout ton contexte" (le vrai différenciateur).

### 1.5 Test iCloud sync réel documenté (1h)
Créer `docs/testing/icloud-sync-checklist.md` avec le protocole de test manuel multi-devices (si `cloudKitEnabled=true`). Documenter aussi le comportement quand désactivé.

### 1.6 Screenshots App Store 6.9" et 6.7" (4h)
Créer 6 screenshots par taille dans `docs/appstore/screenshots/` :
1. Home unifiée (état de vie)
2. Chat coach (avec insight cross-modules visible)
3. Hub d'un module clé (Fitness ou Nutrition)
4. Widget habits sur écran d'accueil
5. Écran d'un thème (Dark ou Volt)
6. Onboarding step 1

Utiliser SwiftUI Previews en 1290x2796 (6.9") et 1290x2778 (6.7") ou capturer via simulateur iPhone 17 Pro Max / iPhone 16 Pro Max.

---

## TIER 2 — Différenciation produit (28h, ce qui fait "wow")

Ce qui distingue une app "qu'on essaye" d'une app "qu'on garde".

### 2.1 Refonte onboarding en 3 écrans (8h)
Remplacer `OnboardingView.swift` (1597 lignes) + `IntakeHubView` par :
- Écran 1 : prénom + objectif principal (1 choix parmi 5)
- Écran 2 : 3 modules pré-cochés (décision inversée : dé-cocher)
- Écran 3 : permission notifs en contexte (pré-prompt)
Puis direct dans la Home. Découper en :
- `Onboarding/OnboardingRouter.swift` (flow)
- `Onboarding/StepIdentity.swift`
- `Onboarding/StepModules.swift`
- `Onboarding/StepNotifications.swift`

### 2.2 Home unifiée avec LifeStatusTile (6h)
`LifeStatusTile.swift` existe déjà mais n'est utilisé nulle part. Créer `LifeOS/Core/HomeView.swift` (structure) + fichiers dédiés :
- `Home+HeroEnergy.swift` (EnergyScore en héros)
- `Home+LifeStatusGrid.swift` (6 tuiles agrégeant les 15 modules)
- `Home+CoachCTA.swift` (bouton "Parler à ton coach")
- `Home+NextMoment.swift` (prochaine fenêtre d'action)
Remplacer `ShortcutsHomeView` dans `MainTabView`. Garder l'ancien fichier archivé.

### 2.3 Un flow coach "wow" démo (6h)
Enrichir `AIAssistantView` pour un moment "wow" au 1er lancement :
- Premier message auto-injecté qui utilise vraiment le contexte cross-modules
- Ex : "Salut Jules, je vois que tu as mal dormi et que tu es à 60% de tes protéines. Tu veux qu'on regarde comment ajuster ta journée ?"
- Boutons rapides (chips) pour répondre en 1 tap
Publie clairement les insights `crossModuleInsights` du `UserContextBuilder`.

### 2.4 Consolidation design system (5h)
- Merger `.card()` / `.surface()` / LifeStatusTile.background en 1 API `.lifeSurface(elevation:)`
- Merger `PressableButtonStyle` / `LifeOSPressStyle` / `TilePressStyle` en 1 seul `LifeButtonStyle`
- Documenter dans `docs/design-system.md`

### 2.5 60 fps profiling + fixes (3h)
- Lancer Instruments (Time Profiler) sur les 4 scrolls principaux : Home, Chat, Fitness hub, Bubble categories
- Identifier les frames > 16ms
- Fixer : `LazyVStack`, cache d'images, computed properties trop coûteuses dans body
- Documenter les gains dans `docs/perf-report.md`

---

## TIER 3 — Qualité invisible (35h, ce qui évite l'échec silencieux)

### 3.1 Sentry setup effectif (1h)
Suivre `docs/observability/SENTRY_SETUP.md`. Ajouter `import Sentry` + `SentrySDK.start` dans `AppDelegate.application(_:didFinishLaunchingWithOptions:)`. Escalader manuellement les erreurs critiques dans les `catch { AppLog.data.error(...) }` existants avec `SentrySDK.capture(error:)`.

### 3.2 +20 tests unitaires (6h)
Créer :
- `CoachExpertiseTests.swift` (8 topics)
- `CoachTextCleanerTests.swift` (10 formats)
- `CrossModuleInsightsTests.swift` (7 cas)
- `ModuleUsageTrackerTests.swift` (track / report / reset)
- `EnergyScoreTests.swift` (variations d'input)

Objectif : passer de 30 à 50+ tests, coverage > 40 % sur `Services/`.

### 3.3 CI GitHub Actions (1h)
Créer `.github/workflows/ci.yml` :
- Build iOS Simulator
- Run tests
- Lint Swift (SwiftLint si présent)
- Backend Python : `pytest` + `ruff check`
Bloquer le merge si rouge.

### 3.4 Migration fonts complète — décisions par écran (8h)
Pour les 531 `.system(size: X, weight: .Y)` restants, faire une passe fichier par fichier :
- Si taille correspond à un token Dynamic Type ± 1pt : migrer avec `.font(.tokenName.weight(.Y))`
- Si taille custom volontaire (hero, calculée) : garder + commenter pourquoi
Ne PAS toucher `Bubble.metal`, `LifeStatusTile` (déjà safe), tests.

### 3.5 Accessibility +90 labels (4h)
Passe VoiceOver sur les 15 God files. Pour chaque `Button { ... } label: { Image(systemName:) }` non triviale, ajouter `.accessibilityLabel("Verbe + objet")`. Objectif : 59 → 150+ labels.

### 3.6 Dynamic Type audit (2h)
Tester chaque écran principal (Home, Chat, Profile, 15 hubs modules) à la taille système la plus grande. Fixer les débordements par `.minimumScaleFactor(0.7)` ou `Layout` adaptatif.

### 3.7 Analytics events + funnel (3h)
Étendre `Analytics.swift` pour tracker :
- `chat.message.sent`
- `chat.action.executed` (avec type)
- `module.opened` (avec module)
- `habit.completed`
- `onboarding.step.completed` (avec step)
- `intake.step.completed`
Créer un funnel : Install → Onboarding OK → Premier chat → J1 retention → J7 retention.

### 3.8 Prompt caching Mistral (2h)
Dans le backend, activer prompt caching sur les blocs `CoachExpertise` (15k chars fixes par persona). Économie 50-70 % sur les tokens répétés.

### 3.9 Suppression compte / export data (5h)
Élargir la fonction du Tier 1.2 avec export JSON de toutes les données locales avant suppression (offre un backup à l'utilisateur avant de tout perdre).

### 3.10 FAQ in-app (3h)
Créer `LifeOS/Core/FAQView.swift` avec 15-20 questions groupées :
- Coach & IA
- Santé & données
- Notifications
- Compte
- Confidentialité
Accessible depuis `ProfileView`.

---

## TIER 4 — Nice-to-have (45h)

### 4.1 Localisation EN complète (12h)
Extraire tous les strings français hardcodés vers `Localizable.xcstrings` (déjà présent mais peu exploité). Traduire les ~2600 clés en anglais. Vérifier les formats de dates/nombres via `.formatted(.locale(...))`.

### 4.2 Widgets audit (1h)
Tester chaque widget (Habits, Alarm, ChallengeStreak, EnergyScore) sur simulateur iOS 17+ écran d'accueil. Corriger les cas cassés.

### 4.3 App Intents étendus (4h)
Compléter `LifeOSIntents.swift` avec 10 intents Siri :
- Logger un verre d'eau
- Ajouter un repas rapide
- Commencer une séance muscu
- Voir mon énergie du jour
- Créer une habitude
- Etc.

### 4.4 Notifications riches (3h)
Enrichir `NotificationManager` :
- Actions inline (marquer fait, snooze, ouvrir module)
- Contenus dynamiques (score du jour dans le titre)
- Sons custom pour les alarmes importantes

### 4.5 Découpe des 4 God files (15h)
Découper dans l'ordre :
1. `AIAssistantView.swift` (1708 → 4 fichiers)
2. `ShortcutsHomeView.swift` (1630 → 4 fichiers) — sera remplacé par HomeView du Tier 2 mais utile en archive
3. `OnboardingView.swift` (1597 → 5 fichiers) — remplacé aussi mais utile
4. `ProfileView.swift` (1170 → 3 fichiers)

### 4.6 Backup manuel utilisateur (3h)
Export JSON de toutes les données SwiftData dans un fichier partageable via `ShareLink`. Import depuis un fichier JSON (avec validation de schéma).

### 4.7 Restauration compte (3h)
Import du backup 4.6 avec merge intelligent (pas d'écrasement bête).

### 4.8 Test cross-devices (4h)
Documenter dans `docs/testing/cross-devices.md` :
- iPhone SE (petit écran)
- iPhone 17 Pro Max (grand écran)
- iPad (adaptation split view si applicable)
- iOS 17 (min supporté)
- iOS 18/26 (dernières versions)

---

## Règles d'exécution (impératives)

### Avant toute action
1. Lire les fichiers concernés (`Read`) avant d'éditer
2. Créer les tâches via `TaskCreate` pour tracker
3. Marquer `in_progress` avant, `completed` après

### Pendant chaque item
1. Vérifier accolades après chaque édition Swift (Diff: 0)
2. Ignorer les diagnostics SourceKit faux positifs ("Cannot find X in scope") — documentés dans skill `swiftui-lifeos`
3. Ne JAMAIS toucher au pbxproj (auto-compilé via synchronized groups)
4. Respecter les règles CLAUDE.md :
   - Pas d'emojis dans le code ou l'UI
   - Textes UI en français, tutoiement
   - Pas de commentaires IA génériques
   - UI ne dit jamais "IA / LLM / modèle" → "ton coach"
5. Si un fichier > 500 lignes doit être créé, avertir + demander confirmation

### Après chaque item
1. `xcodebuild build` doit rester vert
2. `xcodebuild test` doit rester vert (au minimum en fin de tier)
3. Commit atomique préféré (mais l'auto-commit loop tourne, donc pas obligatoire)

### Après chaque tier
1. Build + tests complets
2. Rapport court : items faits, items skippés (avec raison), bugs trouvés + fixés
3. Vérification que l'app se lance dans le simulateur (via `xcrun simctl launch`)

### En fin d'exécution complète
Rapport final structuré :
- Tier X : items faits (chiffres) · items skippés (avec raison)
- Bugs trouvés + corrigés
- Métriques : accessibilityLabel, tests, adoptions tokens
- Build : SUCCEEDED / FAILED
- Runtime : app lancée OK ou non
- 3 suggestions pour la suite

---

## Contraintes hard (jamais dévier)

- Ne pas casser les tests existants
- Ne pas casser le build
- Ne pas toucher `Bubble.metal` (shader Metal)
- Ne pas toucher `Theme.swift` sauf pour AJOUTER des tokens
- Ne pas modifier les modèles SwiftData sans migration (`buildContainer` dans `LifeOSApp` gère les échecs mais préfère éviter)
- Ne pas commit des secrets (vérifier `.gitignore` avant tout ajout de `Config.xcconfig` ou clé API)
- Ne pas déployer le backend (Railway) sans confirmation explicite

---

## Mot d'arrêt

Si l'utilisateur écrit "stop", "STOP", "arrête", "annule", ou "fin" → arrêt immédiat.
Répondre uniquement : "Arrêté." puis lister ce qui n'a pas été fait dans le tier en cours.

---

## Argument par défaut

Si `/perfect` est appelé sans argument → exécuter `tier1` uniquement (le plus urgent, bloquants App Store).
Si `/perfect all` → exécuter tier1 → tier2 → tier3 → tier4 dans l'ordre, sans s'arrêter entre les tiers sauf blocker.
Si `/perfect tier2` (ou tier3, tier4) → exécuter uniquement ce tier.

Pour `all` : prévenir en début de session que ça représente ~120h de travail. Confirmer une fois puis attaquer sans re-demander.

---

## Rappel final

Cette commande est faite pour être **exhaustive et autonome**. Ne pas demander de confirmation à chaque item. Ne pas s'arrêter pour clarifier des choix esthétiques mineurs (utiliser le meilleur jugement). Signaler uniquement les vrais blockers (impossibilité technique, décision produit majeure, risque de perte de données).
