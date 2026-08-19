# Intelligent Profile Engine — Spec

**Date :** 2026-08-19
**Auteur :** Claude (session Jules)
**Statut :** Approuvé, en implémentation

## Objectif

Remplacer le système de quiz statique + profil UserDefaults par un moteur adaptatif :
l'utilisateur ne remplit plus manuellement — il parle au coach (chat, voix, Raccourci iOS)
et le profil se complète automatiquement avec extraction typée, détection de catégorie,
gestion des contradictions et priorisation intelligente des questions.

## Décisions prises

| # | Question | Choix |
|---|---|---|
| 1 | Ordre des blocs | A → B → C → D → E → F → G |
| 2 | Rôle du LLM | Génère les questions librement (avec catalog de field specs) |
| 3 | Storage | SwiftData `@Model` `ProfileField` + `ProfileFieldRevision` |
| 4 | Migration | Automatique au premier lancement post-update |

## Architecture

### Bloc A — Modèle de données + Migration

- `ProfileField` @Model : id, category, valueString, valueType, confidence, source, dates, history
- `ProfileFieldRevision` @Model : snapshot immuable avant chaque update
- `ProfileFieldSpec` struct : catalog statique de 80-120 champs typés
- `ProfileStore` singleton `@MainActor` : upsert, contradiction detection, missingFields
- `ProfileMigration` : lit `moduleConfig_*` + AppStorage → crée les ProfileField au 1er lancement

### Bloc B — Question Engine LLM-driven

- `QuestionEngine.nextQuestion()` :
  1. missingFields filtered par dependsOn + priorityScore
  2. Top 3 candidats + snapshot user + précédente conversation → prompt LLM
  3. Renvoie `(text, targetFieldID, reason)`
- Fallback si Apple Intelligence indispo : template déterministe
- `IntelligentExtractor.extract(from:)` : regex FR rapide + fallback LLM structured JSON

### Bloc C — Extraction structurée depuis chat/voix

- Étendre `MemoryExtractor` → renvoie `[ExtractedField]` (typé) au lieu de `MemoryEntry` texte
- Chaque extraction appelle `ProfileStore.upsert(...)` avec confidence
- Affichage inline dans le chat : "✓ Poids mis à jour : 70 → 74.5 kg"

### Bloc D — Multi-catégorie + contradictions

- `CategoryDetector.detect(from:)` : LLM structured → `[AppCategory: relevance]`
- `ProfileStore.detectContradiction(...)` déjà défini en A
- UI de confirmation si contradiction critique

### Bloc E — Chat vocal continu

- `VoiceConversation` : boucle SpeechRecognizer + auto-send + TTS reply
- Deux modes : "single tap = dictée + envoi" (existant) et "hands-free continu" (nouveau)

### Bloc F — Endpoint API + App Intent Raccourci

- Nouveau `AppIntent` `IngestProfileTextIntent` : accepte `text: String`, appelle localement `IntelligentExtractor` + `ProfileStore.upsert`, retourne `dialog` avec ce qui a été ajouté
- 100% on-device — pas d'endpoint réseau nécessaire (aligné avec la promesse "local")
- Pattern conforme aux `LogWaterIntent`, `AddTodoIntent` existants

### Bloc G — UX chat qui affiche les insertions

- Nouveau composant `ProfileUpdateToast` dans `AIAssistantMessageRow`
- Sous chaque message user : chips vertes des ProfileField mis à jour
- Long-press sur un chip = undo

## Priorité de score des questions

```
priorityScore(field) =
    importance.weight *               // critical=10, high=5, medium=2, low=1
    goalRelevance *                   // 1.0 si aligné, 0.5 si neutre, 0.2 si off-goal
    (1.0 - existingConfidence) *      // 0 si déjà rempli, 1 si absent
    ageBoost                          // 1.0 récent, 1.5 si stale > 90 jours
```

## Règles d'écriture

| Confidence extraite | Comportement |
|---|---|
| ≥ 0.90 | Upsert automatique |
| 0.60 - 0.89 | Upsert si champ vide, sinon suggested contradiction |
| < 0.60 | Ignore |

Source manuelle ne peut être écrasée par source LLM sans confirmation.

## Migration

`ProfileMigration.version` incrémenté à chaque schema change. Idempotent.

Mapping ~60 clés UserDefaults → ProfileField id. Confidence 1.0, source `.migration`.

## Livrables

| Fichier | Rôle |
|---|---|
| `LifeOS/Models/Models_Profile.swift` | @Model ProfileField + Revision |
| `LifeOS/Services/ProfileFieldSpec.swift` | Catalog specs |
| `LifeOS/Services/ProfileStore.swift` | CRUD + contradictions |
| `LifeOS/Services/ProfileMigration.swift` | Migration UD |
| `LifeOS/Services/QuestionEngine.swift` | Ranker + LLM prompt |
| `LifeOS/Services/IntelligentExtractor.swift` | Regex + LLM JSON |
| `LifeOS/Services/CategoryDetector.swift` | LLM multi-cat |
| `LifeOS/Services/VoiceConversation.swift` | Boucle vocal continu |
| `LifeOS/Services/LifeOSIntents.swift` | +IngestProfileTextIntent |
| `LifeOS/Shared/ProfileUpdateToast.swift` | UI chips insertions |

## Estimated

- Bloc A : 4 h
- Bloc B : 8 h
- Bloc C : 6 h
- Bloc D : 4 h
- Bloc E : 3 h
- Bloc F : 5 h
- Bloc G : 3 h

**Total : 33 h.** Livrable progressif : A d'abord → OK build/tests → B → OK → C...
