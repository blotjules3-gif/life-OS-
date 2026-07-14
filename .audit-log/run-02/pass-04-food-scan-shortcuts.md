# Run 2 — Passe 04 · Raccourcis Scan Repas

Date : 2026-07-14
Objectif : rendre le scan de repas (module Nutrition, `PhotoCalorie.swift`) accessible depuis 3 emplacements iOS supplémentaires : Centre de Contrôle, écran d'accueil, Siri.

## Ce qui a été fait

### 1. `PhotoCalorieView` — nouveau paramètre `autoOpenCamera`

- Ajout d'un `var autoOpenCamera: Bool = false`
- Si vrai, `onAppear` déclenche `showCamera = true` avec 0.25 s de délai (évite l'animation saccadée sur double présentation)
- Comportement par défaut inchangé — les usages existants ne bougent pas

### 2. `OpenFoodScanIntent` dans `Services/LifeOSIntents.swift`

- `AppIntent` conforme, `openAppWhenRun: Bool = true`
- `perform()` poste la notification `NotificationCenter.default.post(name: .lifeOSOpenFoodScan, object: nil)`
- Sert de cible pour Siri et pour l'app shortcut phrases

### 3. `Notification.Name.lifeOSOpenFoodScan`

- Ajouté à côté des 3 existantes dans `Core/AppDelegate.swift`

### 4. Deep link `lifeos://scan-food`

- Wiring dans `LifeOSApp.swift`:
  - `.onOpenURL` étendu pour router `host == "scan-food"` → `showFoodScan = true`
  - `.onReceive(...lifeOSOpenFoodScan)` idem
  - `.fullScreenCover(isPresented: $showFoodScan)` affiche `PhotoCalorieView(autoOpenCamera: true)` avec un bouton « Fermer »
- Le schéma `lifeos://` est déjà déclaré dans `Info.plist` (`CFBundleURLTypes`)

### 5. `LifeOSWidgets/FoodScanControlWidget.swift` (nouveau, iOS 18+)

- `ControlWidget` conforme, `@available(iOS 18.0, *)`
- `ControlWidgetButton(action: OpenURLIntent(URL(...)))` — utilise l'intent Apple built-in pour ouvrir un URL, pas besoin de partager un AppIntent avec le target app
- Ouvre `lifeos://scan-food` en un tap

### 6. `LifeOSWidgets/FoodScanWidget.swift` (nouveau)

- `Widget` classique avec 3 familles supportées :
  - `.systemSmall` (Home Screen) — carte verte dégradée « Scan repas · Kcal · Protéines »
  - `.accessoryCircular` (Lock Screen rond) — icône fork.knife
  - `.accessoryRectangular` (Lock Screen large) — icône + label
- `.widgetURL(URL(string: "lifeos://scan-food"))` sur chaque variante

### 7. `LifeOSWidgetsBundle.swift`

- Enregistre `FoodScanWidget()` inconditionnellement
- Enregistre `FoodScanControlWidget()` sous `if #available(iOS 18.0, *)`

### 8. Siri shortcut

- Ajout dans `LifeOSShortcuts.appShortcuts` en première position — priorité à la voix :
  - « Scanne mon repas avec LifeOS »
  - « Prends en photo mon assiette dans LifeOS »
  - « Analyse mon plat avec LifeOS »
- shortTitle : « Scanner un repas », icône : fork.knife

## Chaîne complète — 3 chemins d'accès

```
Utilisateur ──┬── Centre de Contrôle iOS 18+ (FoodScanControlWidget)
              │        │
              │        └─→ OpenURLIntent(lifeos://scan-food)
              │
              ├── Widget Home / Lock (FoodScanWidget)
              │        │
              │        └─→ widgetURL(lifeos://scan-food)
              │
              └── Siri « Scanne mon repas »
                       │
                       └─→ OpenFoodScanIntent
                                │
                                └─→ NotificationCenter.lifeOSOpenFoodScan
                                             │
                                             ▼
                                   Toutes les routes convergent vers
                                   LifeOSApp `.fullScreenCover($showFoodScan)`
                                             │
                                             ▼
                                   PhotoCalorieView(autoOpenCamera: true)
                                             │
                                             ▼
                                   Caméra iOS ouverte instantanément
                                             │
                                             ▼
                                   Vision framework on-device
                                   → kcal + protéines → SwiftData
```

## Vérifications

- Brace check sur les 7 fichiers touchés : **Diff: 0** partout
- Build target `LifeOS` : **0 erreurs**
- Build target `LifeOSWidgetsExtension` : **0 erreurs**
- Tests : **10/10 passent** (UIVocabularySanity, UserContextBuilder × 2, CalendarSafety × 7)
- Aucune régression sur les fixes des runs précédents

## Notes pour l'utilisateur

Comment activer côté iPhone après build :

1. **Centre de Contrôle** : long-press sur le CC → bouton « + » en haut à gauche → chercher « Scan repas » ou « LifeOS » → ajouter le bouton
2. **Widget Home** : long-press écran d'accueil → « + » → chercher LifeOS → « Scan repas »
3. **Lock Screen widget** : Réglages → Fond d'écran → Personnaliser → widgets sous l'heure → LifeOS → Scan repas
4. **Siri** : « Dis Siri, scanne mon repas avec LifeOS » — la 1ère fois iOS demande la confirmation d'accès

## Bilan chiffres

- **Fichiers créés** : 2 (`FoodScanControlWidget.swift`, `FoodScanWidget.swift`)
- **Fichiers modifiés** : 5 (`LifeOSApp.swift`, `PhotoCalorie.swift`, `LifeOSIntents.swift`, `AppDelegate.swift`, `LifeOSWidgetsBundle.swift`)
- **Nouveaux points d'entrée pour l'utilisateur** : 3
- **Tests verts** : 10/10
- **Compat** : iOS 17+ pour widget Home + Siri, iOS 18+ pour Control Center
