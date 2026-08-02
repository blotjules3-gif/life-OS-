# Passe Station F — préparation produit

Date : 2026-08-02
Objectif : combler les gaps produit qui bloquent une candidature Station F crédible.
Portée : uniquement le code app + widgets. Le pitch / deck / vidéo restent côté fondateurs.

## Ce qui a été livré

### P1. Moteur SmartNotifications (`Services/SmartNotifications.swift`)

- Branche `LifeBrain.insights` (qui existait déjà) au système de notifications
- Génère 3 notifs / jour (matin 9h, midi 13h, soir 19h) basées sur l'état cross-pôles réel
- Dédup par titre : pas 3 fois le même insight sur la journée
- Interruption level `.timeSensitive` si priorité ≥ 80 (perce Focus)
- Opt-in via flag `smartNotifsEnabled` UserDefaults (défaut off — pas de spam)
- Appelé au `didBecomeActiveNotification` dans `LifeOSApp`

Exemple concret que ça peut pousser (via LifeBrain déjà en place) :
> « Nuit courte (5.2h) — Récup' en priorité. Allège ta séance (dos + biceps) et bois +500 ml pour compenser la fatigue. »

C'est **l'unfair advantage produit** vs mono-verticaux (Fabulous, WHOOP, Strava) — aucun ne peut produire ce type de recommandation sans avoir toutes les catégories.

### P2. CloudKit sync — code prêt, opt-in par flag

- `LocalStore.cloudKitEnabled` toggle UserDefaults
- `LifeOSApp.buildContainer` utilise `ModelConfiguration(cloudKitDatabase: .automatic)` quand toggle on
- Fallback automatique local-only si CloudKit échoue au boot (capability manquante, schéma incompatible)
- `CloudKitReadiness.report()` — helper qui liste ce qui manque encore

**Action requise côté Jules avant d'activer en prod** :
1. Xcode → Signing & Capabilities → « + Capability » → iCloud
2. Cocher CloudKit + créer container `iCloud.com.blotjules.lifeos`
3. Migrer 4 relations non-Optional en Optional (blocking pour CloudKit) :
   - `Habit.completions: [HabitCompletion]` → `[HabitCompletion]? = []`
   - `Pet.events`, `Vehicle.fuelLogs`, `Trip.packing` idem
4. Puis toggle `LocalStore.cloudKitEnabled = true` depuis Settings

Sans ces 3 étapes, le flag existe mais rien ne bougera (fallback local). Une fois faits, sync iCloud automatique iPhone↔iPad↔Mac.

### P3. Widget « Score énergie » (`LifeOSWidgets/EnergyScoreWidget.swift`)

- 3 familles : `systemSmall`, `accessoryCircular` (lock screen), `accessoryRectangular` (barre lock screen)
- Lit `energyScore.value` depuis App Group defaults (publié par l'app)
- `EnergyScore.publishToAppGroup(...)` étendu — appelé automatiquement au `didBecomeActiveNotification`
- Gradient couleur selon le score (vert → orange → rouge)
- Score visible sans ouvrir l'app = perception que « LifeOS colonise l'iPhone »

### P4. Live Activity « Streak habitude » (`LifeOSWidgets/StreakActivityWidget.swift`)

- Se déclenche aux paliers 7, 14, 30, 100 jours d'affilée
- Lock Screen card horizontale + Dynamic Island (compact / expanded / minimal)
- Fichier `StreakAttributes.swift` dupliqué à l'identique dans les 2 targets (pattern LifeOS existant)
- Manager : `StreakActivityManager.startIfMilestone(habitName:iconName:streakDays:doneToday:)` — appelable depuis le check d'habitude
- Cycle de vie : start / update / endAll

**Action requise côté Jules** : appeler `StreakActivityManager.startIfMilestone(...)` après chaque toggle d'habitude (dans `HealthRepository.toggleHabit` ou équivalent). Ligne à ajouter :
```swift
let streak = currentStreak(for: habit)
if #available(iOS 16.1, *) {
    StreakActivityManager.startIfMilestone(
        habitName: habit.name, iconName: habit.icon,
        streakDays: streak, doneToday: true
    )
}
```

### P5. Widget interactif « Habitudes iOS 17+ » (`LifeOSWidgets/InteractiveHabitsWidget.swift`)

- Version iOS 17+ qui affiche les habitudes avec boutons cliquables
- Chaque tap → `ToggleHabitIntent` — toggle direct sans ouvrir l'app
- L'intent flip le flag dans `widget_habits` App Group defaults (visuel immédiat)
- Ajoute une entrée dans `widget_pending_toggles` (queue à rejouer côté app)
- `WidgetToggleReconciler.drainAndApply(ctx:)` — appelé au `didBecomeActiveNotification`, rejoue dans SwiftData
- Familles : `systemMedium` (4 habits) + `systemLarge` (8 habits)
- Coexiste avec l'ancien `HabitsWidget` non-interactif (compat iOS < 17)

## Fichiers modifiés / créés

| Fichier | Type | Rôle |
|---------|------|------|
| `LifeOS/Services/SmartNotifications.swift` | **nouveau** | Engine notifs cross-pôles |
| `LifeOS/Services/EnergyScore.swift` | modifié | + `publishToAppGroup(...)` |
| `LifeOS/Services/LocalStore.swift` | modifié | CloudKit config opt-in |
| `LifeOS/Services/StreakActivityManager.swift` | **nouveau** | Cycle de vie Live Activity streak |
| `LifeOS/Services/WidgetToggleReconciler.swift` | **nouveau** | Rejoue toggles widget → SwiftData |
| `LifeOS/Core/StreakAttributes.swift` | **nouveau** | Type Live Activity (partagé) |
| `LifeOS/LifeOSApp.swift` | modifié | Wire les 4 nouveaux services au boot |
| `LifeOSWidgets/EnergyScoreWidget.swift` | **nouveau** | Widget score énergie 3 familles |
| `LifeOSWidgets/StreakActivityWidget.swift` | **nouveau** | Widget Live Activity streak |
| `LifeOSWidgets/StreakAttributes.swift` | **nouveau** | Copie type Live Activity (widget target) |
| `LifeOSWidgets/InteractiveHabitsWidget.swift` | **nouveau** | Widget habits interactif iOS 17+ |
| `LifeOSWidgets/ToggleHabitIntent.swift` | **nouveau** | AppIntent pour toggle widget |
| `LifeOSWidgets/LifeOSWidgetsBundle.swift` | modifié | Enregistre 3 nouveaux widgets |

**Total : 8 fichiers créés, 5 modifiés.**

## Vérifications

- Brace check tous fichiers touchés : Diff: 0
- Build app clean : **0 erreurs, 0 warnings**
- Build widget clean : **0 erreurs, 0 warnings**
- Tests LifeOSTests target : **28/28 passent** (AlarmManager, CalendarSafety, ImageStore, ThemeContrast, UIVocabularySanity, UserContextBuilder + placeholder)

## Ce qui reste à faire — split côté toi vs code

### Toi (Jules) — hors code

- [ ] **Deck pitch 12 slides** (framework Vision → Problème → Solution → Marché → Concurrence → Unfair advantage (les notifs cross-pôles !) → Roadmap → BM → Traction → Team → Ask)
- [ ] **Vidéo pitch 3 min** — toi + Léo direct caméra + captures app
- [ ] **Vidéo demo 60s** — app en action iPhone réel
- [ ] **App Store screenshots** — 6 vues calibrées avec headlines marketing
- [ ] **App Preview vidéo** 15-30s pour la fiche App Store
- [ ] **Landing page waitlist** — ajouter formulaire (Tally/TypeForm) au docs/index.html + Plausible pour metrics
- [ ] **Bio équipe** — 2 courtes bios factuelles
- [ ] **Un-pager PDF** — résumé exécutif A4
- [ ] **Campagne acquisition waitlist** — objectif 500-1000 avant candidature (Twitter build-in-public, LinkedIn FR, ProductHunt coming-soon, HN Show)

### Léo (co-founder) — design

- [ ] Réviser les couleurs des 3 nouveaux widgets (accents / palette)
- [ ] Illustrer les milestones streak (7/14/30/100 avec petites icons custom si envie)
- [ ] Screenshots App Store — préparer les maquettes des 6 écrans

### Code — micro-actions restantes (côté toi, 30 min chacune)

- [ ] **Brancher StreakActivityManager** dans le flow toggle habitude (voir P4 ci-dessus)
- [ ] **Écran opt-in SmartNotifs** dans NotificationSettingsSheet — toggle « Notifications intelligentes » + explication
- [ ] **Écran opt-in CloudKit** dans Settings — après avoir migré les 4 relations Optional
- [ ] **Publier score énergie aussi depuis SleepCheckSheet** après submit — ajouter `EnergyScore.publishToAppGroup(...)` là où le score est calculé + `WidgetCenter.shared.reloadTimelines(ofKind: "EnergyScoreWidget")`

### Onboarding — pas fait ici, à discuter

Le gap **onboarding** que j'ai flagué reste ouvert. `OnboardingView.swift` existe (1569 lignes) mais je n'ai pas refactoré parce que :
- Grosse surface, risque de tout casser sans lire toute la logique en détail
- Décisions produit importantes (quel objectif prioritaire ? combien de modules activer par défaut ?)
- Mieux fait avec toi + Léo autour d'une table + Figma

Prochaine passe possible : audit ciblé de l'onboarding + proposition de refonte 5 écrans.

## Estimation impact Station F

Ce qui vient d'être livré transforme concrètement 3 dimensions du dossier :

1. **Product depth démontrable** — 4 widgets sur écran d'accueil + Lock Screen + Dynamic Island = « LifeOS colonise l'iPhone entier » (positioning fort)
2. **Unfair advantage tangible** — SmartNotifications cross-pôles = démo qui pique en 30s pendant le pitch
3. **Readiness scaling** — CloudKit prêt à enable + widget interactif = pas juste un MVP démo

**Ce qui reste critique côté dossier** = deck + vidéo + traction waitlist. Sans ces 3-là, la meilleure app ne passe pas.
