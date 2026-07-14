# Run 2 — Passe 03 · Option C, Phase 2B

Date : 2026-07-13
Objectif : **extinction complète du cloud**. Aucune requête réseau ne doit plus partir de l'app pour de la donnée personnelle.

## Ce qui a été fait

### 1. Nouveau service `LifeOS/Services/EnergyScore.swift`

Port du calcul backend Python (`backend/app/services/energy.py`) vers Swift on-device. Pondération identique :
- Sommeil qualité 30 pts · durée 10 pts
- Hydratation 20 pts
- Habitudes 20 pts
- Humeur 15 pts
- Anti-fatigue 5 pts

API :
- `EnergyScore.compute(Input)` — calcul pur
- `EnergyScore.today(ctx)` — lecture SwiftData + UserDefaults, retourne `Result?`
- `Result` : `score`, `label`, `colorHex`

### 2. Migration des 8 call sites metadata restants

| # | Fichier | Ancien appel | Nouveau comportement |
|---|---------|--------------|----------------------|
| 1 | SleepCheckSheet.swift | `logCheckin` | Écriture SwiftData + UserDefaults + `EnergyScore.today` |
| 2 | DailyBriefingView.swift | `logCheckin` | Idem, calcul via `EnergyScore.compute` avec les valeurs manuelles |
| 3 | ProfileView.swift | `fetchEnergyScore` | `EnergyScore.today(ctx)` |
| 4-5 | DailyBriefingView.swift | `listGoals` + `fetchChallenges` + `fetchBehavioralInsights` | Listes vides, prompt du briefing refactoré sans ces paramètres |
| 6 | AIAssistantView.swift | `fetchChallenges` (checkAbandonedChallenges) | No-op, TODO pour un futur `LifeChallenge` SwiftData local |
| 7 | RemoteConfig.swift | `fetchRemoteConfig` | Statique — `chatEnabled = true` toujours |
| 8 | CoachReportAlerts.swift | `reportMessage` | Écriture locale JSONL dans `Documents/coach_reports.jsonl` |

### 3. Suppressions / simplifications

- **`Services/AgentAPI.swift`** — supprimé (512 lignes de code réseau + 4 sessions URLSession + types Codable)
- **`Services/Configuration.swift`** — réduit à un shim de 15 lignes (retire `baseURL`, `apiKey`, `timeoutInterval`, `chatTimeoutInterval`, `isLocalDev`, `defaultKey`)
- **`Services/ServerStatusMonitor.swift`** — vidé : renvoie toujours `.online`, `dotColor = .green`, `canSendChatMessages = true`. Les 3 vues qui l'utilisent (MainTabView, ProfileView, AIAssistantView) continuent à marcher sans modification.
- **`Services/RemoteConfig.swift`** — retire le fetch, valeur défaut hardcodée

### 4. Refactor `DailyBriefingView.buildBriefingPrompt`

Signature simplifiée : `buildBriefingPrompt()` au lieu de `buildBriefingPrompt(goals:, challenges:)`. Les states `briefingGoals`, `briefingChallenges` retirés. `behavioralInsights` conservé (state) mais toujours vide — la vue affiche « rien » à sa place.

## Vérifications

- Grep `AgentAPI` dans `LifeOS/` = **2 hits** (uniquement des commentaires historiques dans `LocalCoach.swift` et `OnDeviceLLM.swift`)
- Brace check sur les 10 fichiers touchés : **Diff: 0** partout
- Build : **0 erreurs**
- Tests : **10/10 passent** (UIVocabularySanity, UserContextBuilder × 2, CalendarSafety × 7)

## Effet sur la privacy policy

**La contradiction principale est éteinte.**

- Le user_context (poids, cycle, humeur, PR force, habitudes…) n'est plus construit ni envoyé pour les chats (Phase 2A)
- Les endpoints metadata (goals, challenges, energy, logCheckin, reportMessage, remoteConfig) ne sont plus appelés (Phase 2B)
- Le seul reste de code réseau côté iOS est `URLSession` dans quelques services non-utilisateurs (HealthKit, etc.), qui ne parlent pas à un serveur applicatif

Le texte de `docs/privacy.html` (« Pas de serveur, pas de compte, tout reste sur votre iPhone ») **tient désormais dans les faits** pour l'app iOS.

## Ce qu'il reste (Phase 2C — décision produit)

- Décider quoi faire du **backend Railway** : il tourne toujours et coûte encore de l'OpEx. Options : arrêt immédiat, dump Postgres pour archivage, garder pendant 30 j pour transition
- Purger les données déjà côté Postgres pour respecter la nouvelle promesse (droit à l'oubli implicite)
- Mettre à jour la landing page : les chiffres "16 pôles / 41 entités" sont marketing volontaire côté pote, mais rajouter une mention "iOS 26 requis pour le coach LLM (Apple Intelligence), rule-based sinon" si tu veux être transparent
- Optionnel : recréer `.github/workflows/qa.yml` via web UI (retiré au push précédent faute de scope OAuth)

## Régressions conscientes

- **Historique de conversation cross-device** : perdu (aligné avec Option C)
- **Actions de coach depuis le chat** : partiellement maintenues via LocalCoach action detection ; les actions moins courantes (`updateConfig`, `addModule`) sont désactivées quand Apple Intelligence répond
- **Goals + Challenges + Insights côté briefing** : dégradés en listes vides. Un modèle `Goal` et `Challenge` SwiftData local est possible en Phase 2D si la feature vaut le coup
- **Kill switch coach** : plus dispo. C'est cohérent : sans serveur, pas de kill switch nécessaire

## Bilan chiffres

- **Fichiers supprimés** : 1 (`AgentAPI.swift`)
- **Fichiers créés** : 1 (`EnergyScore.swift`)
- **Fichiers modifiés** : 8
- **Lignes de code réseau retirées** : ~700 (AgentAPI + Configuration + ServerStatusMonitor + RemoteConfig avant/après)
- **Endpoints Railway côté iOS restants** : **0**
- **Tests verts** : 10/10
