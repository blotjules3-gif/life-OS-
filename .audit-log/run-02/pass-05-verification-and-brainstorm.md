# Run 2 — Passe 05 · Vérification + brainstorm raccourcis

Date : 2026-07-14

## 1. Vérification fresh (skill verification-before-completion)

### Build app LifeOS (clean rebuild)

```
xcodebuild clean build -project LifeOS.xcodeproj -scheme LifeOS ...
```

**Résultat : 0 erreurs, 0 warnings** (après fixes ci-dessous)

Fixes appliqués pendant la vérif :
- `SpeechRecognizer.swift:134` — `.allowBluetooth` (déprécié iOS 8) → `.allowBluetoothHFP`
- `CoachReportAlerts.swift:70` — `try? handle.seekToEnd()` → `_ = try? handle.seekToEnd()` (result unused)
- `AlarmActivityWidget.swift:154` — `.symbolEffect(.bounce, ...)` gardé sous `if #available(iOS 18.0, *)` (l'app cible iOS 17)
- `FaceAnalysis.swift`, `DocScan.swift` — `@preconcurrency import Vision` ajouté

De 82 warnings avant vérif → **0 warnings** après. Le build est propre.

### Build target LifeOSWidgetsExtension (clean rebuild)

**Résultat : 0 erreurs, 0 warnings.**

### Tests complets LifeOSTests

```
xcodebuild test -only-testing:LifeOSTests
```

**28 test cases passent, 0 échec.** Détail :

| Suite | Tests |
|-------|-------|
| AlarmManagerTests | 5 |
| CalendarSafetyTests | 7 |
| ImageStoreTests | 9 |
| LifeOSTests (placeholder) | 1 |
| ThemeContrastTests | 3 |
| UIVocabularySanityTests | 1 |
| UserContextBuilderTests | 2 |

### Cross-check chaîne deep link scan food

9 maillons vérifiés indépendamment via grep :

1. ✓ URL scheme `lifeos` dans `Info.plist:CFBundleURLSchemes`
2. ✓ `Notification.Name.lifeOSOpenFoodScan` déclarée dans AppDelegate.swift
3. ✓ `OpenFoodScanIntent.perform()` poste la notification
4. ✓ `LifeOSApp.onOpenURL` route `host == "scan-food"` → `showFoodScan = true`
5. ✓ `LifeOSApp.onReceive(...lifeOSOpenFoodScan)` fait de même
6. ✓ `PhotoCalorieView(autoOpenCamera: true)` déclenche `showCamera` à l'apparition
7. ✓ `FoodScanControlWidget` utilise `OpenURLIntent(URL(...))` sur `lifeos://scan-food`
8. ✓ `FoodScanWidget` a `widgetURL(lifeos://scan-food)` sur les 3 familles supportées
9. ✓ `LifeOSShortcuts.appShortcuts` déclare la phrase Siri « Scanne mon repas… »

Chaîne complète, aucun maillon manquant.

## 2. Brainstorm — autres raccourcis rapides possibles

Le pattern « Control Center + widget Home + Siri » qu'on vient de mettre en place peut se démultiplier facilement — chaque nouveau raccourci = 1 URL scheme + 1 handler dans LifeOSApp + widgets qui pointent dessus.

### Idées classées par utilité fréquentielle

#### Tier S (usage quotidien, gestes rapides — le plus rentable)

1. **Timer de jeûne** — bouton toggle « démarrer / arrêter » le jeûne. Le module FastingSession existe déjà. Control Center adapté (état visible : icône remplie si actif). Home widget affiche l'heure écoulée en direct.

2. **Note vocale rapide** — bouton qui ouvre l'enregistrement vocal du module Mind (SpeechRecognizer déjà en place). Idéal pour capturer une idée sans dérouler l'app.

3. **Journal du soir** — bouton qui ouvre `EveningSummaryView` en fullScreen. Prend 30 s le soir, mérite un accès direct.

4. **Chat coach** — le briefing widget existe déjà, mais un bouton dédié « parler au coach » ouvrant `AIAssistantView` en fullScreen serait pratique. Deep link `lifeos://coach`.

#### Tier A (utile plusieurs fois par semaine)

5. **Scan code-barres nutrition** — alternative au photo food. Module Nutrition (`CalAIView.swift` ou similaire) a du VisionKit. Un scan de code-barres = kcal fiables en 2 s.

6. **Log humeur express** — widget Home avec 5 émojis tappables (1-5). Insère `MoodEntry` direct, pas d'app à ouvrir.

7. **Photo progrès** — même flux que scan repas mais pour `LooksmaxxKit.faceAnalysis`. Une photo/jour pour le suivi visage.

8. **Prochain rendez-vous médical** — widget Home qui affiche le prochain `MedicalAppointment` avec compte à rebours. Tap = ouvre le module Medical.

#### Tier B (utile ponctuellement)

9. **Trip departure timer** — quand un `Trip` a un `departureDate < now + 24h`, widget qui compte à rebours. Tap = ouvre TravelModule.

10. **Compléments du soir « rappel + confirm »** — bouton Control Center qui, tapé, marque les compléments du soir comme pris (`ConfirmationStore.markDone`). Complémente les notifs existantes.

11. **Voir le score énergie du jour** — Control Center avec un chiffre (0-100). Utilise `EnergyScore.today(ctx)` — déjà en place depuis Phase 2B.

12. **Vue par module** — deep link `lifeos://module/<name>` (partiellement en place via `.lifeOSOpenModule`) → 1 widget par module qu'on peut épingler individuellement.

### Ce qui vaut le coup vs pas

- **Rentable en 30 min de code** : Timer jeûne, Journal soir, Chat coach direct, Photo progrès
- **Rentable en 1 h** : Log humeur express (widget interactif avec `AppIntent` param), Score énergie widget
- **Pas rentable maintenant** : Trip departure (peu utilisé), scan code-barres (double emploi avec photo food)

## 3. Recommandation

Enchaîner un pack de 4 raccourcis « Tier S » dans une seule passe (1-2 h total, tous suivent le même pattern déjà validé aujourd'hui) :

1. Timer jeûne (Control Center + widget)
2. Journal soir (Siri + widget)
3. Chat coach direct (Siri + Control Center)
4. Photo progrès looksmaxx (mêmes 3 emplacements que scan repas)

Chaque raccourci = ~15 min : nouveau `AppIntent`, wiring dans LifeOSApp, nouveau widget si utile, phrase Siri ajoutée à `LifeOSShortcuts`.
