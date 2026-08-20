# Improve-chat — progression

Suivi étape par étape des améliorations chat IA. Coche au fur et à mesure.
Backlog défini dans `.claude/commands/improve-chat.md`.

## 🔴 P0 — Fondations mortes à ressusciter

- [ ] 1. Brancher AIModelRouter dans OnDeviceLLM.respond()
- [ ] 2. Enregistrer 5 vrais AITool au boot
- [ ] 3. Wire AIContextManager dans le pipeline send()
- [ ] 4. Compléter AIActivityLogger (recordContext + recordResponse + tools + postProc)

## 🟠 P1 — Coach proactif

- [ ] 5. CoachProactiveEngine service
- [ ] 6. BGTaskScheduler daily
- [ ] 7. Notification contextuelle avec deep link

## 🟠 P1 — Awareness

- [ ] 8. TimeAwareness service
- [ ] 9. LocationAwareness service
- [ ] 10. Injection AIContextManager

## 🟡 P1 — Vision multimodale

- [ ] 11. PhotoAnalysisTool (Apple Intelligence vision)
- [ ] 12. Wire dans AIAssistantView.analyzeImage

## 🟡 P2 — Multi-tour reasoning

- [ ] 13. Boucle tool calls (max 3 itérations)

## 🟡 P2 — Feedback loop réelle

- [ ] 14. CoachFeedbackStore par catégorie
- [ ] 15. UI feedback qualitatif

## 🟡 P2 — Mémoire multi-niveau

- [ ] 16. MemoryEntry.retentionType + decayFactor
- [ ] 17. Retrieval scoring pondéré

## 🟡 P3 — Explainability

- [ ] 18. AIResponse.reasoning
- [ ] 19. UI bouton "pourquoi ?"

## 🟡 P3 — Tests scénarios

- [ ] 20. CoachScenarioTests (5 scénarios)

## 🟡 P3 — Analytics coach

- [ ] 21. Events sessionLength + retention + actionCompleted

## 🟡 P4 — Long-term decay

- [ ] 22. Job cleanup MemoryEntry vieux

## 🟡 P4 — RGPD complet

- [ ] 23. DataEraser inclut MemoryEntry + Revision + Feedback + Logger
- [ ] 24. UI "Voir ce qu'on sait de toi"

## 🟢 P5 — Foundation Models iOS 26.1+

- [ ] 25. @Generable structured output
- [ ] 26. LanguageModelSession(tools:) tool calling natif
- [ ] 27. Fallback iOS 26.0

---

## Journal

(mises à jour au fur et à mesure)
