# Visual Cleanup Sprint 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (inline mode chosen) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Corriger les 4 points visuels les plus critiques de LifeOS identifiés par l'audit du 2026-07-07 — sans casser l'app, avec build vert à la fin de chaque tâche.

**Architecture:** Renforcer `Theme.swift` avec des tokens animation, migrer chirurgicalement les `cornerRadius: 14` vers `Theme.radiusSmall` (le plus fréquent — 71 occurrences), ajouter les `accessibilityLabel` sur les 3 zones tactiles les plus visibles (chat input, satellites orbe profil, hub fitness), fixer les touch targets < 44pt sur les mêmes zones.

**Tech Stack:** SwiftUI, iOS 17+, Xcode 15+, xcodebuild pour vérification.

## Global Constraints

- Ne modifier QUE ce qui est ciblé par la tâche — pas de refacto opportuniste
- Vérifier accolades après chaque édition (`Diff: 0`)
- Build Xcode complet obligatoire à la fin de chaque tâche
- Zéro régression fonctionnelle
- Skill LifeOS `swiftui-lifeos` déjà lu (SourceKit false-positives à ignorer)
- Palette et vocabulaire coach (voir CLAUDE.md) inchangés
- Aucun emoji ajouté

---

## Task 1: Ajouter les tokens Animation dans Theme

**Files:**
- Modify: `LifeOS/Core/Theme.swift` (ajout après les tokens radius/pad)

**Interfaces:**
- Produces:
  - `Theme.animQuick: Animation` (spring response 0.28, damping 0.75)
  - `Theme.animDefault: Animation` (spring response 0.35, damping 0.8)
  - `Theme.animSlow: Animation` (spring response 0.45, damping 0.9)
  - `Theme.animMicro: Animation` (spring response 0.2, damping 0.7 — pour presses)

- [ ] **Step 1.1: Read Theme.swift autour de la zone radius/pad pour situer**
- [ ] **Step 1.2: Insérer le bloc animation tokens juste après la ligne `static let sectionGap: CGFloat = 24`**
- [ ] **Step 1.3: Vérifier accolades**
- [ ] **Step 1.4: Build check**
- [ ] **Step 1.5: Commit**

---

## Task 2: Migration `cornerRadius: 14` → `Theme.radiusSmall`

**Files:**
- Modify: 40+ fichiers Swift dans LifeOS/ contenant `cornerRadius: 14`
- Tool: le skill `code-cleanup-migration` (créé aujourd'hui)

**Interfaces:**
- Consumes: `Theme.radiusSmall` (existe déjà = 14)
- Produces: cohérence — 0 occurrence de `cornerRadius: 14` en dur, N occurrences de `Theme.radiusSmall` (N = ancien N)

- [ ] **Step 2.1: Inventaire exhaustif — liste des fichiers/lignes touchés**

```bash
grep -rn 'cornerRadius: 14' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/ > /tmp/radius14-before.txt
wc -l /tmp/radius14-before.txt
```
Attendu : ~71 lignes.

- [ ] **Step 2.2: Vérifier que `Theme.radiusSmall = 14` existe bien**

```bash
grep -n "radiusSmall" /Users/blotjules/LifeOS-associe/LifeOS/Core/Theme.swift
```
Attendu : `static let radiusSmall: CGFloat = 14`

- [ ] **Step 2.3: Migration fichier par fichier via `sed`**

```bash
find /Users/blotjules/LifeOS-associe/LifeOS -name "*.swift" -exec sed -i '' 's/cornerRadius: 14/cornerRadius: Theme.radiusSmall/g' {} \;
```

- [ ] **Step 2.4: Vérification exhaustive**

```bash
grep -rn 'cornerRadius: 14' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/ | wc -l
```
Attendu : 0

```bash
grep -rn 'cornerRadius: Theme.radiusSmall' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/ | wc -l
```
Attendu : ~71

- [ ] **Step 2.5: Build check obligatoire**

```bash
cd /Users/blotjules/LifeOS-associe && xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

- [ ] **Step 2.6: Commit**

---

## Task 3: Touch targets ≥ 44pt sur le chat input

**Files:**
- Modify: `LifeOS/Shared/AIAssistantView.swift` (autour des lignes 1105-1115 — PhotosPicker frame 34×34)

**Interfaces:**
- Produces: PhotosPicker + WaveformView avec zone tactile 44×44 min (via `.contentShape`)

- [ ] **Step 3.1: Localiser les frames < 44pt dans AIAssistantView**

```bash
grep -n "frame(width: 34, height: 34)" /Users/blotjules/LifeOS-associe/LifeOS/Shared/AIAssistantView.swift
```

- [ ] **Step 3.2: Modifier PhotosPicker pour zone tactile 44pt+**

Remplacer :
```swift
Image(systemName: "photo.on.rectangle.angled")
    .font(.system(size: 20, weight: .medium))
    .foregroundStyle(vm.isLoading ? Color.secondary : accent)
    .frame(width: 34, height: 34)
```
Par :
```swift
Image(systemName: "photo.on.rectangle.angled")
    .font(.system(size: 20, weight: .medium))
    .foregroundStyle(vm.isLoading ? Color.secondary : accent)
    .frame(width: 44, height: 44)
    .contentShape(Rectangle())
```

- [ ] **Step 3.3: Modifier WaveformView pour même zone tactile**
- [ ] **Step 3.4: Vérifier accolades**
- [ ] **Step 3.5: Build check**
- [ ] **Step 3.6: Commit**

---

## Task 4: `accessibilityLabel` sur le hub Fitness

**Files:**
- Modify: `LifeOS/Modules/FitnessModule.swift`

**Interfaces:**
- Produces: chaque `Button` du `FitnessHubView` a un `.accessibilityLabel(…)` explicite

- [ ] **Step 4.1: Identifier les Buttons sans label**

```bash
grep -n "Button {" /Users/blotjules/LifeOS-associe/LifeOS/Modules/FitnessModule.swift | head -10
```

- [ ] **Step 4.2: Ajouter `.accessibilityLabel` sur les 4 boutons principaux**

Les 4 boutons dans `FitnessHubView` :
- "Génère ma séance du jour" → `.accessibilityLabel("Génère ma séance du jour avec le coach")`
- "Mon profil sportif" → `.accessibilityLabel("Éditer mon profil sportif")`
- "HIIT / Tabata" (showTabata) → `.accessibilityLabel("Minuteur HIIT plein écran")`
- Le banner coach intro → `.accessibilityLabel("Profil sportif à compléter")`

- [ ] **Step 4.3: Vérifier accolades**
- [ ] **Step 4.4: Build check**
- [ ] **Step 4.5: Commit**

---

## Task 5: Vérification finale + commit + push

**Files:** aucun (verification-only)

**Interfaces:**
- Consumes: le résultat cumulé des tâches 1-4
- Produces: build vert + commit sémantique + push sur main

- [ ] **Step 5.1: Comptage des progrès**

```bash
grep -rn 'cornerRadius: 14[^0-9]' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/ | wc -l
# Attendu: 0

grep -rn 'Theme.animDefault\|Theme.animQuick\|Theme.animSlow\|Theme.animMicro' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/Core/Theme.swift | wc -l
# Attendu: 4

grep -rn 'accessibilityLabel' --include="*.swift" /Users/blotjules/LifeOS-associe/LifeOS/ | wc -l
# Doit avoir augmenté de +4 minimum
```

- [ ] **Step 5.2: Build final complet**

```bash
cd /Users/blotjules/LifeOS-associe && xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | tail -5
```
Attendu : `** BUILD SUCCEEDED **`

- [ ] **Step 5.3: Commit sémantique + push**

```bash
git commit --allow-empty -m "chore(ui): visual cleanup sprint 1 (animation tokens, radius migration, touch targets, a11y)"
git push origin jules
git checkout main && git merge --ff-only jules && git push origin main
git checkout jules
```

- [ ] **Step 5.4: Mise à jour du ROADMAP.md avec les items faits**

---

## Hors scope de ce sprint (documenté pour la suite)

Ces items du top 5 de l'audit demandent plus de temps ou de décisions UX — reportés :

- **colorScheme audit sur 67 emplacements** — nécessite décision UX par écran (dark variant per hex color). ~3 h.
- **100+ accessibilityLabels sur toute l'app** — chantier à faire écran par écran. ~4 h.
- **Migration des autres cornerRadius non-standards (`10`, `12`, `18`, `20`)** — 138 occurrences supplémentaires. Nécessite une décision : arrondir vers Theme ou créer des tokens intermédiaires ? ~1 h de discussion + 1 h de migration.
- **179 padding hors grille 8pt** — même problème que les radius non-standards.

Ces items rejoindront la **Phase 2 du ROADMAP.md** (Accessibilité + App Store readiness).
