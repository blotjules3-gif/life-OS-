# Passe 05 — Secteur Models

Date : 2026-07-13
Fichiers audités : 5 (Models_Assets, Models_Health, Models_Life, Models_Reminders, NutritionHelpers) — ~706 lignes
Méthode : lecture complète (fichiers courts, denses en @Model) + grep force-unwrap + audit de la stratégie de valeurs par défaut.

## Constatations

### Bloquant (crash potentiel)

**B1. `Models_Health.swift:190` — force-unwrap Calendar sur `Vaccination.isDue`**

```swift
var isDue: Bool {
    guard let next = nextDueDate else { return false }
    return next <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
}
```

Exactement le pattern protégé par `CalendarSafetyTests.swift`. Pour des dates extrêmes ou une locale Calendar bricolée, `date(byAdding:)` peut renvoyer nil → crash.

Fix : guard sur les deux dates, pas de `!`.

```swift
var isDue: Bool {
    guard let next = nextDueDate,
          let horizon = Calendar.current.date(byAdding: .day, value: 30, to: .now)
    else { return false }
    return next <= horizon
}
```

Sémantique préservée : si on ne peut pas calculer l'horizon, on considère le vaccin « pas dû » — safe default.

## Application

- `Models_Health.swift:188-192` — refactor du getter isDue, brace check Diff: 0.

## Absents

- Aucun autre force-unwrap dans Models
- Aucun @Model sans init par défaut (tous les init ont des valeurs)
- Aucune violation UI (pas de strings user-facing dans les Models)
- Pas de Codable custom fragile
- Relations (`@Relationship(deleteRule: .cascade)`) correctes (voir Habit → HabitCompletion)

## Bilan Models

5 fichiers, 1 fix. Le secteur est bien conçu : @Model avec valeurs par défaut sur toutes les propriétés (rétro-compat migrations), init exhaustifs, relations propres. Le seul risque restant était le force-unwrap Calendar isolé, corrigé.
