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

## Statut : 17/24 étapes complétées, 133/133 tests passent

Reste :
- P2.13 (multi-tour), P3.18-19 (reasoning), P4.24 (data audit UI), P5 (@Generable + tools API iOS 26.1) — tous nécessitent des APIs iOS 26.1+ ou effort UI conséquent
