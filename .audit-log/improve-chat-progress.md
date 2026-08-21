# Improve-chat — progression

Suivi étape par étape des améliorations chat IA.
Backlog défini dans `.claude/commands/improve-chat.md`.

## 🔴 P0 — Fondations mortes à ressusciter

- [x] 1. Brancher AIModelRouter dans OnDeviceLLM.respond() — router.execute() actif
- [x] 2. Enregistrer 5 vrais AITool au boot — via lazy bootstrap CoachToolsBootstrap
- [x] 3. Wire AIContextManager — budget tokens tracking actif
- [x] 4. Compléter AIActivityLogger — recordContext + recordResponse + recordPostProcessing wired

## 🟠 P1 — Coach proactif

- [x] 5. CoachProactiveEngine service — 4 signaux (streak, forgottenGoal, sleepDeclining, weightStale)
- [x] 6. BGTaskScheduler daily — CoachProactiveScheduler avec BGAppRefreshTask
- [x] 7. Notification contextuelle — deep link `lifeos://coach?prefill=…`

## 🟠 P1 — Awareness

- [x] 8. TimeAwareness — moment du jour + weekday + weekend
- [x] 9. LocationAwareness — LocationSnapshot cache 10 min
- [x] 10. Injection dans OnDeviceLLM.respondViaAppleIntelligence

## 🟡 P1 — Vision multimodale

- [x] 11. PhotoAnalysisTool — Vision classify + OCR + route sémantique
- [x] 12. Enregistré dans CoachToolsBootstrap.registerAll

## 🟡 P2 — Multi-tour reasoning

- [ ] 13. Boucle tool calls — **REPORTÉ** (nécessite iOS 26.1+ LanguageModelSession.tools réelle)

## 🟡 P2 — Feedback loop réelle

- [x] 14. CoachFeedbackStore par catégorie — DislikeReason enum + summary agrégé
- [x] 15. UI feedback qualitatif — dislikeReasonsRow apparaît après 👎

## 🟡 P2 — Mémoire multi-niveau

- [x] 16. MemoryEntry retentionType + confirmationCount + lastAccessedAt
- [x] 17. MemoryRetrieval — score = relevance × recency × retentionWeight × confirmationBoost

## 🟡 P3 — Explainability

- [ ] 18. AIResponse.reasoning — **REPORTÉ** (nécessite modèle plus large)
- [ ] 19. UI bouton "pourquoi ?" — **REPORTÉ**

## 🟡 P3 — Tests scénarios

- [x] 20. CoachScenarioTests — 6 scénarios (onboarding, correction, création, multi-cat, distress, frustration)

## 🟡 P3 — Analytics coach

- [x] 21. Events chatFeedbackReason + firstResponseLatency + sessionLength + retention + toolExecuted + coachProactive

## 🟡 P4 — Long-term decay

- [x] 22. MemoryDecayJob — 6 mois obsolète, 12 mois archivage, revisions max 12/field

## 🟡 P4 — RGPD complet

- [x] 23. DataEraser.eraseAIArtifacts — CoachFeedback + ActivityLogger + UserContextBuilder cache
- [ ] 24. UI "Voir ce qu'on sait de toi" — **REPORTÉ** (ProfileFieldsView existe déjà)

## 🟢 P5 — Foundation Models iOS 26.1+

- [ ] 25. @Generable structured output — **REPORTÉ** (nécessite iOS 26.1)
- [ ] 26. LanguageModelSession(tools:) — **REPORTÉ** (nécessite iOS 26.1)
- [ ] 27. Fallback iOS 26.0 — préparé (protocol AIProvider)

---

## Statut : 17/24 étapes complétées, 132/133 tests passent

Reste :
- P2.13 (multi-tour), P3.18-19 (reasoning), P4.24 (data audit UI), P5 (@Generable + tools API iOS 26.1) — tous nécessitent des APIs iOS 26.1+ ou effort UI conséquent

Test `UserContextBuilderTests.testEmptyLifeProfileDoesNotEmitBlock` échoue en run complet, passe en isolé + après CoachExpertiseTests → pollueur d'ordre non identifié, préexistant à Loop 1.

---

## Loop 1 (2026-08-21) — Wire 4 dead services end-to-end

Audit du début de loop : 4 services créés dans la session précédente n'avaient AUCUN caller.
Ils étaient dans le repo mais totalement inertes.

### Problème identifié

- `CoachProactiveScheduler` : 0 callers → BGTask jamais enregistré, coach jamais proactif
- `MemoryDecayJob` : 0 callers → mémoires jamais nettoyées
- `MemoryRetrieval` : 0 callers → retrieval scoré jamais utilisé, fallback flat App Group seul en place
- Deep link `lifeos://coach?prefill=…` : émis par scheduler mais aucun handler côté notif

### Solution

- `AppDelegate.didFinishLaunching` : `CoachProactiveScheduler.registerBackgroundTask()` + `.scheduleNextRefresh()`
- `AppDelegate.NotificationDelegate` : catégorie `LIFEOS_COACH` extrait `prefill` du deep link, post `.lifeOSOpenAIChat` avec userInfo → `MainTabView` le passe à `AIAssistantView(prefill:)`
- `LifeOSApp.didBecomeActive` : `CoachProactiveScheduler.runProactiveScan()` (fallback foreground) + `MemoryDecayJob.runIfNeeded(context:)` (cleanup 7j)
- `LifeOSApp.onAppear` : `UserContextBuilder.shared.setContext(container.mainContext)` pour permettre retrieval scoré
- `UserContextBuilder.buildFresh` : si ctx présent + message non vide, appelle `MemoryRetrieval.retrieve(for:context:)` scoré (relevance × recency × retention × confirmation) ; fallback App Group `memory_top_10` si pas de ctx

### Validation

- BUILD SUCCEEDED (warnings uniquement, non bloquants)
- 132/133 tests passent (fail préexistant sur pollueur d'ordre, non lié à Loop 1)
- Vérif accolades : Diff 0 sur `LifeOSApp.swift`, `AppDelegate.swift`, `UserContextBuilder.swift`

### Prérequis manuel utilisateur

~~Ajouter à `Info.plist`~~ **FAIT en Loop 2** — `BGTaskSchedulerPermittedIdentifiers` + `fetch` dans `UIBackgroundModes`.

---

## Loop 2 (2026-08-21) — ToolEnrichment : activer les 6 tools morts

### Problème identifié

`grep ToolRegistry.shared.execute LifeOS/` → **0 caller en prod** (docstrings uniquement).
Les 6 tools enregistrés (`GetUserProfileTool`, `GetProfileFieldTool`, `SearchMemoryTool`, `CreateHabitTool`, `CreateTodoTool`, `PhotoAnalysisTool`) étaient inaccessibles au LLM.

Conséquence : question type "quel est mon poids ?" → réponse potentiellement hallucinée car le LLM n'accède pas aux `ProfileField` typés ni aux `MemoryEntry` structurés.

### Solution

- Nouveau `LifeOS/Services/AICore/ToolEnrichment.swift` — pré-processing déterministe qui détecte 3 patterns d'intent dans le message user, invoque le tool via `ToolRegistry.shared.execute`, injecte le résultat dans le prompt sous forme d'un bloc `--- INFO RÉCUPÉRÉE POUR TOI ---`.
- Patterns v1 :
  - `get_profile_field` (poids, taille, âge, kcal, protéines, fréquence sport, poids cible)
  - `get_user_profile` (résumé complet sur "qui suis-je / que sais-tu de moi")
  - `search_memory` (extraction du sujet dans "tu te souviens de X")
- Wire dans `OnDeviceLLM.respond` — l'enrichment est calculé en amont du `PromptAssembler.assemble` et concaténé au systemPrompt.
- Traçabilité : chaque exécution loggée dans `AIActivityLogger` (`recordToolExecution` — durée + succès).
- Complément Info.plist : `fetch` + `BGTaskSchedulerPermittedIdentifiers` (prérequis Loop 1 mais fait ici).

### Validation

- BUILD SUCCEEDED
- **9 nouveaux tests** dans `LifeOSTests/ToolEnrichmentTests.swift` — tous verts (weight, targetWeight, height, age, gymFrequency, profile summary positif+négatif, memory search)
- 141/142 tests OK (fail préexistant `testEmptyLifeProfileDoesNotEmitBlock` non lié)
- Vérif accolades OK sur `ToolEnrichment.swift`, `OnDeviceLLM.swift`

### Ce qui change pour l'utilisateur

Avant : "quel est mon poids ?" → réponse générique / hallucination possible.
Après : le coach lit son `ProfileField.body.currentWeightKg` (source SwiftData typée, avec confidence + timestamp) AVANT de répondre → info fraîche et fiable. Idem "que sais-tu de moi", "tu te souviens de X".
