# Passe 02 — Secteur Core

Date : 2026-07-13
Fichiers audités : 37 (~13 610 lignes)
Méthode : grep transverse (force unwraps, try!, print, LLM/IA UI, coquilles FR) + lecture des points d'entrée lifecycle (LifeOSApp, AppDelegate, RootView, MainTabView, NotificationManager) + spot-check des sheets et vues principales.

## Constatations

### Important

**I1. `NotificationManager.swift:173` — coquille dans le body du bilan hebdo**

```swift
content.body = "Tes habitudes, ton humeur, tes objectifs — tout est la."
```

« la » sans accent → doit être « là ». Chaîne user-facing d'une notification récurrente hebdomadaire (dimanche 20h) → visible chaque semaine.

Fix : ajouter l'accent.

### Signalé, non touché (structure / hors scope)

- **LifeOSApp.swift** — deux `.onChange(of: onboardingDone)` sur le même conteneur. Pas un bug (les deux blocs sont idempotents), mais duplication. Fusion possible mais change la structure du chain de modifiers → refusé pour cette passe.
- **UDKey (Core/UserPreferencesKeys.swift)** — registre exhaustif de clés UserDefaults, **zéro usage** dans tout le repo (`grep UDKey.` = 0). Même diagnostic que `AppStorageKeys` en Services. Nettoyage architectural = passe transverse dédiée, pas ici.
- **Prints** (`ImageStore`, `HabitDefaults`, `SleepCheckSheet`, `ShortcutsHomeView`, `BubbleCategoriesView`, `AppDelegate`) — la plupart dans des blocs de gestion d'erreur SwiftData ; `AppDelegate` est déjà en `#if DEBUG`. Migration vers un logger = passe transverse.
- **ProfileView.swift** — couvert par le skill dédié `lifeos-orbit-profile`, pas touché.

### Absence de trouvailles

- Aucune occurrence de `try!` / `as!` / force-unwrap `.first!` `.last!` `[i]!` dans Core.
- Aucun littéral UI contenant « LLM » ou « IA » (confirmé par `UIVocabularySanityTests`).
- Aucun `TouchableOpacity`-équivalent SwiftUI douteux ; les patterns `Button`/`Pressable`-like sont conformes.
- Le bug clé `"userLifeProfile"` → `"lifeProfile"` déjà réglé à la passe 01. Écriture/lecture alignées (voir trace ligne 65 et 234 de OnboardingView vs ligne 30 et 34 de UserContextBuilder).

## Application

- `NotificationManager.swift:173` — accent ajouté → « tout est là. »
- Brace check → Diff: 0.

## En parallèle de cette passe

- Test de sanity `UIVocabularySanityTests` ajouté dans LifeOSTests/ — scanne toutes les chaînes Swift pour détecter les violations « LLM » / « IA », avec grandfathering des 2 occurrences historiques restantes (Shared/AIAssistantView, Modules/PoleSetups) à traiter dans leurs passes.
- Test unitaire `UserContextBuilderTests` — vérifie que le bloc « Profil: » apparaît bien dans le contexte coach quand la clé `lifeProfile` est renseignée, et qu'il n'apparaît pas sinon.
