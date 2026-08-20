---
description: Amélioration continue et autonome du chat IA LifeOS. Avance étape par étape sur la roadmap d'audit critique jusqu'à ce que l'utilisateur dise « stop ».
---

# Commande — Améliorer le chat IA en continu

## Contexte

L'audit critique (docs/audit conversation Claude) a identifié un backlog priorisé de trous à combler dans l'écosystème coach LifeOS. Cette commande fait AVANCER le chat sans nécessiter de nouvelles instructions à chaque étape.

## Règles absolues

1. **Ne casse rien** : `xcodebuild build` + `xcodebuild test` doivent PASSER après chaque étape. Si un test échoue, corrige avant de continuer.
2. **Une étape = un livrable observable** : nouveau fichier, nouveau test, nouveau comportement visible par l'user.
3. **Vérif build + tests OBLIGATOIRE** après chaque étape (jamais deux étapes cumulées avant vérif).
4. **Documentation minimale** : commentaires courts sur le POURQUOI (pas le QUOI que fait déjà le code).
5. **Respecte swiftui-lifeos** : jamais "IA/LLM/modèle" dans strings UI, jamais d'emoji dans code, palette C.* / Theme.*, pas d'import React.
6. **Stop natif** : si l'utilisateur écrit « stop », interrompt immédiatement, résume ce qui n'a pas été fait.

## Backlog priorisé (ordre d'exécution)

### 🔴 P0 — Fondations MORTES à ressusciter (Phase 1 dead code)

1. Brancher `AIModelRouter` : `OnDeviceLLM.respond()` délègue à `router.execute()`.
2. Enregistrer 5 vrais `AITool` au boot : `GetUserProfileTool`, `GetProfileFieldTool`, `SearchMemoryTool`, `CreateHabitTool`, `CreateTodoTool`.
3. Wire `AIContextManager` dans le pipeline `send()` (remplace `PromptAssembler` legacy — ou utilise `PromptAssembler` en interne).
4. Compléter `AIActivityLogger` : recordContext + recordResponse + recordToolExecution + recordPostProcessing.

### 🟠 P1 — Coach proactif (le manque #1 de l'audit)

5. `CoachProactiveEngine` service — scan quotidien : streak à préserver, objectif oublié > 7j, sommeil qui chute 5j, poids stable > 4 semaines.
6. `BGTaskScheduler` daily task qui déclenche `CoachProactiveEngine`.
7. `NotificationManager` → notif contextuelle avec deep link vers chat avec question pré-formulée.

### 🟠 P1 — Time/Location awareness

8. `TimeAwareness` service : lit heure + jour semaine + saison + jour férié → injecté dans le prompt système.
9. `LocationAwareness` service : `CLLocationManager` (permission déjà OK) → context "à la maison / au bureau / gym" via places significatives.
10. Injection dans `AIContextManager.build(...)` via nouvelle section `timeContext`.

### 🟡 P1 — Vision multimodale

11. `PhotoAnalysisTool` : image → LLM Apple Intelligence vision (iOS 26.1+) → extraction structurée (aliments, tenue, document médical).
12. Wire dans `AIAssistantView.analyzeImage` : nouveau chemin vision au lieu de juste Vision.classify.

### 🟡 P2 — Multi-tour reasoning

13. Boucle tool calls : si `AIResponse.hasToolCalls` → exécute tool → renvoie result comme `AIChatMessage(role: .tool)` → refait un round LLM. Max 3 iterations.

### 🟡 P2 — Feedback loop réelle

14. `CoachFeedbackStore.summary()` catégorise par type (contenu / ton / longueur) au lieu d'injecter des snippets bruts.
15. Nouveau UI feedback qualitatif : après un dislike, chip "trop long", "pas assez concret", "hors sujet".

### 🟡 P2 — Mémoire multi-niveau

16. `MemoryEntry` gains `retentionType` (session/short/long/episodic) + `decayFactor`.
17. Retrieval scoring par relevance × recency × confidence × userConfirmation.

### 🟡 P3 — Explainability

18. `AIResponse.reasoning` : le coach explique pourquoi il propose X ("basé sur ton profil : Y").
19. UI : bouton "pourquoi ?" sous chaque réponse coach affiche le reasoning.

### 🟡 P3 — Tests scénarios conversationnels

20. `CoachScenarioTests` : 5 scénarios de conversation 3-5 tours (onboarding, coaching sport, détresse, chitchat, correction info) → assert comportement.

### 🟡 P3 — Analytics coach

21. `AnalyticsEvents.coachSessionLength`, `coachTimeToFirstResponse`, `coachRetention24h/7j`, `coachActionCompleted`.

### 🟡 P4 — Long-term decay

22. Job de nettoyage : `MemoryEntry` > 6 mois sans re-mention → confidence × 0.5. > 12 mois → archive.

### 🟡 P4 — RGPD complet

23. `DataEraser` : inclure `MemoryEntry`, `ProfileFieldRevision`, `CoachFeedbackStore.jsonl`, `AIActivityLogger` sessions.
24. UI "Voir ce qu'on sait de toi" — dump complet des ProfileField + MemoryEntry en JSON téléchargeable.

### 🟢 P5 — Foundation Models iOS 26.1+

25. Migration `@Generable` pour extraction JSON (garantie de schéma).
26. Migration `LanguageModelSession(tools:)` pour tool calling natif.
27. Fallback propre si iOS 26.0.

## Méthode

À chaque invocation :

1. Lis le fichier `.audit-log/improve-chat-progress.md` (crée-le si absent) pour savoir où on en est.
2. Prends la prochaine étape non-cochée.
3. Explique brièvement le problème (2-3 phrases).
4. Implémente proprement (code minimal, tests si applicable).
5. `xcodebuild build` + `xcodebuild test` (destination `id=64C849EA-2888-4F97-9546-0D99F883471B`).
6. Coche l'étape dans `.audit-log/improve-chat-progress.md` avec un mini-résumé.
7. Passe à la suivante — sauf si l'utilisateur a dit « stop ».

Ne pas demander de confirmation entre chaque étape. Enchaîne.

## Livrable final attendu

Chat coach LifeOS qui :
- Utilise VRAIMENT l'AI Core (0 dead code)
- Cherche l'utilisateur proactivement (notif contextuelle intelligente)
- Comprend le temps, le lieu, l'humeur
- Analyse les photos (assiette, tenue, doc)
- Raisonne en plusieurs étapes via tool calls
- Apprend catégoriquement du feedback
- Explique son raisonnement
- Est testé sur des scénarios réels
- Respecte RGPD à 100%
- Utilise les dernières API Apple Intelligence
