# Passe 03 — Secteur Shared

Date : 2026-07-13
Fichiers audités : 8 (~3 288 lignes)
Méthode : grep transverse LLM/IA + force-unwrap + lecture ciblée AIAssistantView (banner offline), ModuleChatView, CoachReportAlerts, CoachDisclaimerSheet.

## Constatations

### Important

**I1. `AIAssistantView.swift:1386` — violation UI « IA »**

```swift
subtitle: err ?? "Le service IA ne répond pas"
```

Bannière visible quand le coach est indisponible. Le paramètre `err` peut aussi contenir des mots interdits (vient du champ `LLMStatus.error` côté serveur).

Fix : sortir de `case .llmDown(let err)` vers `case .llmDown:`, chaîne fixe « Service momentanément en panne — réessaie plus tard ». Aligné avec le fix passe 01 sur ServerStatusMonitor.

**I2. `CoachReportAlerts.swift:54` — accusé de signalement dishonest**

```swift
try? await AgentAPI.shared.reportMessage(...)
didSubmit = true   // s'exécute même si l'envoi échoue
```

L'utilisateur voit « Signalement envoyé — Merci, nous allons relire cette réponse. » alors que la requête réseau a échoué silencieusement.

Fix : `do/catch`, ne bascule `didSubmit` que sur succès.

## Application

- `AIAssistantView.swift` — chaîne neutralisée (`0000000` auto-commit à venir)
- `CoachReportAlerts.swift` — try/catch propre au lieu de try?
- `LifeOSTests/UIVocabularySanityTests.swift` — AIAssistantView retiré du grandfathering (il n'en reste qu'un : `Modules/PoleSetups.swift`)

Brace check → Diff: 0 sur les 3 fichiers.
Sanity grep `"[^"]*\b(LLM|IA)\b[^"]*"` sur Shared → 0 match.

## Absents

- Aucun force-unwrap (`try!`, `as!`, `.first!`)
- Aucun autre littéral suspect

## Hors périmètre

- AIAssistantView.swift = 1808 lignes, seule zone auditée en détail = la bannière et son env immédiat. Une revue complète des flows du chat justifierait sa propre passe si besoin.
