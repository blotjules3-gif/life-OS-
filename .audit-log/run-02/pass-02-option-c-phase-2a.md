# Run 2 — Passe 02 · Option C, Phase 2A

Date : 2026-07-13
Décision produit : **Option C — 100 % on-device + Apple Intelligence** (validée par Jules via AskUserQuestion).
Périmètre de cette passe : **coupure du LLM cloud**. Les endpoints metadata (goals, challenges, energy) restent côté Railway pour l'instant — traités en Phase 2B.

## Ce qui a été fait

### 1. Nouveau service `LifeOS/Services/OnDeviceLLM.swift`

- Routing en 3 étapes :
  1. Si le message ressemble à une action locale (`crée habitude`, `j'ai bu un verre`…) → `LocalCoach.respond` gère (action SwiftData + confirmation)
  2. Sinon, Apple Intelligence via `FoundationModels.SystemLanguageModel` si dispo (iOS 26+ + device éligible)
  3. Sinon, `LocalCoach.respond` rule-based en filet
- API : `OnDeviceLLM.respond(to:ctx:moduleContext:) async -> Reply`
- `Reply.source` indique `.onDeviceLLM` ou `.localRules` — utile pour tests ou debug
- Gate `#if canImport(FoundationModels)` + `if #available(iOS 26.0, *)` → compile OK sur toutes les versions cibles

### 2. Migration des 9 call sites conversationnels

| Fichier | Site | Avant | Après |
|---------|------|-------|-------|
| DailyBriefingView.swift | :225 | `AgentAPI.shared.chat` briefing du matin | `OnDeviceLLM.respond` |
| DailyBriefingView.swift | :552 | `AgentAPI.shared.chat` retry briefing | `OnDeviceLLM.respond` |
| ShortcutsHomeView.swift | :1344 | `AgentAPI.shared.chat` bilan hebdo | `OnDeviceLLM.respond` |
| ModuleChatView.swift | :238 | `AgentAPI.shared.chat` chat par module | `OnDeviceLLM.respond` |
| AIAssistantView.swift | triggerProactive | `AgentAPI.shared.chat` push proactif | `OnDeviceLLM.respond` |
| AIAssistantView.swift | send | `AgentAPI.shared.chatStream` | `OnDeviceLLM.respond` |
| AIAssistantView.swift | fallbackSend | `AgentAPI.shared.chat` | `OnDeviceLLM.respond` (legacy filet) |
| AIAssistantView.swift | triggerWelcome | `AgentAPI.shared.chat` 1er lancement | `OnDeviceLLM.respond` |

Grep confirme : `grep AgentAPI.shared.chat LifeOS/` = 0 call sites restants (la méthode elle-même reste déclarée dans AgentAPI.swift).

### 3. Ajustements de scope

- `WeeklyBilanView` (ShortcutsHomeView.swift) : ajouté `@Environment(\.modelContext) private var ctx` — nécessaire pour que le filet LocalCoach puisse lire les données SwiftData

## Ce qui n'est PAS fait dans cette passe

Reste pour la Phase 2B (~1 j) :
- 8 call sites metadata AgentAPI restants (listGoals, fetchChallenges, fetchBehavioralInsights, fetchEnergyScore, logCheckin × 2, reportMessage, fetchRemoteConfig)
- Migration Goals + Challenges + Energy vers SwiftData local
- Extinction Railway

Phase 2C (~1 h) après B :
- Vérifier privacy policy — si vraiment plus rien ne part vers Railway, elle tient telle quelle

## Vérifications

- Brace check : Diff: 0 sur les 5 fichiers touchés (OnDeviceLLM, AIAssistantView, ModuleChatView, DailyBriefingView, ShortcutsHomeView)
- Build : 0 erreurs
- Tests : 10/10 passent (UIVocabularySanity, UserContextBuilder × 2, CalendarSafety × 7)
- Grep : 0 `AgentAPI.shared.chat\|chatStream` call sites hors OnDeviceLLM

## Régression consciente

- **Actions du coach depuis le chat** : le backend renvoyait des `AIAction` (createHabit, createTodo, updateConfig, addModule…) exécutées côté iOS. En on-device pur, ces actions ne peuvent pas venir du LLM. **Mitigation** : `LocalCoach` détecte déjà les intents « crée une habitude », « j'ai bu un verre », etc. et exécute directement les mêmes actions SwiftData. Le prompt `isLikelyLocalAction` route ces messages vers LocalCoach en priorité.
- **Streaming token par token** : perdu. Le LLM Apple Intelligence répond en une passe. Peut être ré-ajouté plus tard via `session.streamResponse` (dispo dans FoundationModels).
- **conversation_id / historique persisté** : plus persisté côté serveur, donc plus disponible en cross-device. C'est cohérent avec Option C (rien ne quitte l'iPhone).

## Effet immédiat sur la privacy

**Depuis cette passe, aucune donnée conversationnelle ne quitte plus l'iPhone.** Le `user_context` (poids, cycle, humeur, PR de force, habitudes…) n'est plus construit ni envoyé pour les chats. La contradiction principale de la privacy policy est levée.

Il reste 8 endpoints metadata qui parlent encore à Railway — Phase 2B fermera ce reste.
