# Audit compatibilité CloudKit — SwiftData `cloudKitDatabase: .automatic`

Date : 2026-07-02 · Portée : les 50 modèles @Model (Models_Life, Models_Health, Models_Assets, Models_Reminders, CycleEntry, AIMessage)

## Verdict

**Pas activable en l'état.** Deux catégories de blocages dans le code + une configuration Xcode.

## Blocage 1 — Défauts au niveau des propriétés (≈45 modèles)

CloudKit exige que chaque propriété stockée soit **optionnelle ou ait une valeur par défaut inline** (`var name: String = ""`). Un défaut dans l'`init` ne suffit pas.

- Conformes : `Supplement`, `CustomReminder`, `GymDay` (défauts inline).
- Non conformes : tous les autres (`var name: String` sans `= ""`).

Correctif mécanique : ajouter `= <défaut de l'init>` à chaque déclaration. Aucune migration de store nécessaire (le schéma ne change pas).

## Blocage 2 — Relations non optionnelles (4)

CloudKit exige des relations optionnelles. À passer en `[X]?` (avec adaptation des usages `.append`, `.contains`, etc.) :

| Modèle | Relation |
|---|---|
| `Habit` | `completions: [HabitCompletion]` |
| `Pet` | `events: [PetCare]` |
| `Vehicle` | `fuelLogs: [FuelLog]` |
| `Trip` | `packing: [PackingItem]` |

## Blocage 3 — Configuration Xcode (action Jules)

- Capability **iCloud → CloudKit** + container `iCloud.com.blotjules.lifeos` sur le target LifeOS (Signing & Capabilities).
- Capability **Background Modes → Remote notifications** (sync silencieuse).
- Nécessite un compte développeur avec iCloud activé.

## Points déjà conformes

- Aucune contrainte `@Attribute(.unique)` (interdites par CloudKit).
- `CycleEntry.symptoms: [String]` : type supporté.
- `AIMessage.actions: Data?` : optionnel, OK.
- deleteRule `.cascade` : supporté.

## Ordre d'exécution recommandé

1. Jules active la capability iCloud dans Xcode (5 min).
2. Passe automatisée : défauts inline sur les 45 modèles.
3. Passe manuelle : 4 relations optionnelles + adaptation des call-sites.
4. `ModelConfiguration(cloudKitDatabase: .automatic)` dans `LocalStore` (un seul endroit depuis l'extraction du schéma).
5. Test sur deux appareils avec le même compte iCloud.
