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
- [x] 9. LocationAwareness — LocationSnapshot cache 10 min, permission when-in-use
- [x] 10. Injection dans OnDeviceLLM.respondViaAppleIntelligence

## 🟡 P1 — Vision multimodale

- [x] 11. PhotoAnalysisTool — Vision classify + OCR + route sémantique (food/document/outfit/medical/general)
- [x] 12. Enregistré dans CoachToolsBootstrap.registerAll

## 🟡 P2 — Multi-tour reasoning

- [ ] 13. Boucle tool calls — REPORTÉ (nécessite iOS 26.1+ LanguageModelSession.tools réelle)

## 🟡 P2 — Feedback loop réelle

- [x] 14. CoachFeedbackStore par catégorie — DislikeReason enum + summary agrégé
- [ ] 15. UI feedback qualitatif — TODO (chip après dislike dans AIAssistantMessageRow)

## 🟡 P2 — Mémoire multi-niveau

- [ ] 16. MemoryEntry retentionType + decayFactor — TODO
- [ ] 17. Retrieval scoring pondéré — TODO

## 🟡 P3 — Explainability

- [ ] 18. AIResponse.reasoning — TODO
- [ ] 19. UI bouton "pourquoi ?" — TODO

## 🟡 P3 — Tests scénarios

- [ ] 20. CoachScenarioTests — TODO

## 🟡 P3 — Analytics coach

- [ ] 21. Events retention + sessionLength — TODO

## 🟡 P4 — Long-term decay

- [x] 22. MemoryDecayJob — 6 mois obsolète, 12 mois archivage, revisions max 12/field

## 🟡 P4 — RGPD complet

- [x] 23. DataEraser.eraseAIArtifacts — CoachFeedback + ActivityLogger + UserContextBuilder cache + coach_reports
- [ ] 24. UI "Voir ce qu'on sait de toi" — TODO (ProfileFieldsView existe déjà partiellement)

## 🟢 P5 — Foundation Models iOS 26.1+

- [ ] 25. @Generable structured output — TODO (nécessite iOS 26.1)
- [ ] 26. LanguageModelSession(tools:) — TODO (nécessite iOS 26.1)
- [ ] 27. Fallback iOS 26.0 — préparé (protocol AIProvider)

---

## Journal

**Session 1 (2026-08-20)**

**P0.1** Brancher `AIModelRouter` — `OnDeviceLLM.respondViaAppleIntelligence` délègue maintenant à `AIModelRouter.shared.execute(AIRequest)`. Logging session actif (recordContext, recordResponse, recordPostProcessing). **Build OK, tests 127/127.**

**P0.2** Enregistrer 5 tools — Créé `CoachTools.swift` avec `GetUserProfileTool`, `GetProfileFieldTool`, `SearchMemoryTool`, `CreateHabitTool`, `CreateTodoTool`. Bootstrap via `AIModelRouter.bootstrapToolsIfNeeded()` (lazy, pas besoin d'edit LifeOSApp). **Build OK.**

**P0.3** AIContextManager wired — définitions tools passées via `ToolRegistry.shared.availableDefinitions()` dans le budget de contexte + AIRequest. Pas encore utilisées par Apple Intelligence (nécessite Phase 5), mais visibles dans debug. **Build OK.**

**P0.4** Logger complet — déjà fait en P0.1.

**P1.5** CoachProactiveEngine — 4 signaux : streakMilestone (J6→J7, J13→J14, J29→J30, J99→J100), forgottenGoal (>7j sans update), sleepDeclining (<6h), weightStale (>28j sans update). Chaque nudge génère titre + body + prefilledMessage + urgency. **Build OK.**

**P1.6-7** CoachProactiveScheduler — `BGAppRefreshTask` avec identifier `com.blotjules.lifeos.coach.proactive`. Anti-spam 1/jour + cooldown 48h par signal. Notif locale avec `userInfo` deep link `lifeos://coach?prefill=…`. **Build OK.**

⚠️ Info.plist doit ajouter `BGTaskSchedulerPermittedIdentifiers` avec `com.blotjules.lifeos.coach.proactive` sinon iOS refuse. Non fait ici — à ajouter manuellement dans Xcode.

**P1.8-10** AwarenessContext — snapshot texte "mardi 22h, soirée, en semaine + location". `LocationSnapshot` avec CLLocationManager, cache 10 min. Injection dans OnDeviceLLM system prompt final. **Build OK, tests 127/127.**

**P1.11-12** PhotoAnalysisTool — wrap Vision classify + OCR dans structure `AITool` typée. Route sémantique (food/document/outfit/medical/general). Enregistré au bootstrap. **Build OK.**

**P2.14** Feedback catégorisé — `DislikeReason` enum (tooLong, notConcrete, offTopic, wrong, tone). `summary()` v2 agrège par raison au lieu d'injecter des snippets bruts. **Build OK, tests 127/127.**

**P4.22** MemoryDecayJob — 7 jours cooldown, 6 mois → `[obsolète]` prefix, 12 mois → delete, revisions max 12/field. Idempotent via `lastRunKey`. **Build OK.**

**P4.23** DataEraser.eraseAIArtifacts — supprime CoachFeedback jsonl, coach_reports jsonl, AIActivityLogger sessions, UserContextBuilder cache. Appelé automatiquement dans `eraseAllData()`. **Build OK, tests 127/127.**

---

## À faire ensuite (session suivante)

- P2.15 UI feedback qualitatif (chip DislikeReason)
- P2.16-17 Memory multi-niveau (retentionType + retrieval scoring)
- P3.18-21 Explainability + tests scénarios + analytics coach
- P4.24 UI "Voir ce qu'on sait de toi"
- P5.25-27 Foundation Models iOS 26.1+ (@Generable + tools API)

12 étapes complétées, 12 restantes.
