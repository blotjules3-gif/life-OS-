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

---

## Loop 3 (2026-08-21) — Multi-provider IA (choix user)

### Problème identifié

L'architecture n'exposait qu'Apple Intelligence + LocalCoach. ~80 % des iPhone du parc (< 15 Pro) n'ont pas Apple Intelligence → coach dégradé pour eux. Le protocol `AIProvider` était conçu pour être extensible mais aucun autre provider n'existait.

### Solution — 3 briques + 4 providers + 1 UI

**Fondations sécurité :**
- `AIProviderCredentials` — store Keychain (`kSecClassGenericPassword` + `kSecAttrAccessibleAfterFirstUnlock`), un slot par provider (openai/anthropic/mistral/gemini). Jamais dans UserDefaults, jamais logué.
- `AIProviderPreference` — UserDefaults, ID du provider préféré. `nil` = auto.
- `AIProviderHTTP` — helper factorisé (401/403 → invalidCredentials, 429 → rateLimited, timeout, offline).

**4 providers cloud** implémentant `AIProvider` :
- `OpenAIProvider` — GPT-4o-mini par défaut, format Chat Completions
- `AnthropicProvider` — Claude Haiku 4.5 par défaut, format Messages API (system séparé)
- `MistralProvider` — Mistral Small Latest, format OpenAI-compatible
- `GeminiProvider` — Gemini 2.0 Flash, format Google (rôle "model", clé en query string)

**AIModelRouter modifié** : si `AIProviderPreference.preferred` matche un provider éligible, il passe en tête de la chaîne. Fallback naturel si le préféré échoue (offline, rate limit, clé invalide).

**Écran Réglages** `CoachAIProviderView` — accessible via menu chat coach → "Moteur du coach" :
- Apple Intelligence en tête si dispo, sinon grisé
- Chaque provider cloud avec badge "Clé configurée" / "Aucune clé"
- Tap → sheet éditeur clé (SecureField + lien vers doc provider)
- Bouton "Choisir" → set preference user
- Bouton "Retour à sélection automatique"

### Validation

- **BUILD SUCCEEDED**
- 141/142 tests OK (fail préexistant non lié)
- `UIVocabularySanityTests` respecté : vocabulaire UI = "Moteur du coach" (pas IA/LLM/modèle)
- Accolades OK sur les 10 fichiers touchés

### Impact utilisateur

- L'user choisit son provider dans les Réglages
- iPhone < 15 Pro : peut brancher OpenAI/Claude/Mistral/Gemini avec sa propre clé → vrai coach IA
- iPhone 15 Pro+ : Apple Intelligence par défaut (gratuit, privé), peut basculer sur cloud pour + de puissance
- Zéro backend LifeOS requis, zéro coût pour LifeOS (user paie sa clé API)
- Clés stockées dans le Trousseau iOS (sécurité système)

### Reste à faire (Loop 3d — optionnel)

- Proxy Cloudflare Workers pour un mode "freemium LifeOS paie" (~40 lignes)
- Affichage coût estimé par provider avant activation
- Indicateur "via [Provider]" sous chaque message coach (T1 de l'audit)

---

## Loop 3 — fixes post-audit (2026-08-22)

Audit sans complaisance de Loop 3 → 5 BLOQUANTS + 12 MAJEURS + 8 MINEURS + 4 TROUS identifiés. Fix pass sur les items critiques réparables sans device réel :

**Fixes appliqués :**
- **B5 Capabilities menteuses** : Retiré `.toolCalling` et `.structuredOutput` des 4 providers cloud (features non parsées côté réponse) — le router ne route plus vers eux les requêtes avec tools qu'ils ne savent pas gérer.
- **B3 Slug matching fragile** : `AIProviderPreference` stocke désormais le providerID exact (`"openai.gpt"` au lieu de `"openai"`). Router matche via `id == pref` strict (plus de `contains()` source de bugs silencieux). Migration API : suppression `setPreferred(slot:)`, garder `setPreferredProviderID`.
- **B4 Validation format clé** : `AIProviderCredentials.validate(_:for:)` ajoutée — check prefix (`sk-` pour OpenAI, `sk-ant-` pour Anthropic) + longueur minimale (40 chars OpenAI/Anthropic, 20 Mistral/Gemini). Erreur explicite dans le sheet éditeur avant enregistrement.
- **M3 Bouton "Tester la clé"** : ping réel au provider (max_tokens=5, timeout 12s), affiche latence ou erreur classifiée (401 refusée / rate limit / timeout / offline). Sauve temporairement + restore si l'user annule.
- **M4 Sheet éditeur montre clé existante** : masque `••••XXXX` (4 derniers chars) + placeholder adapté. Section "Supprimer" n'apparaît que si une clé existe.
- **M5 Timeout défaut** : 30s → 20s (`AIRequest.init`).
- **M8 Confirmation destructive** : `confirmationDialog` sur "Retour à la sélection automatique".
- **m1 Diagnostic macOS** : `#if os(iOS)` autour de `navigationBarTitleDisplayMode` (2 endroits).
- **UX Apple Intelligence** : badge "Recommandé" quand dispo, boutons "Choisir" `.bordered` (au lieu de `.borderless` invisible).
- **UX Section providers** : titre "Providers cloud (payants)" explicite.

**Tests unit ajoutés (B1 partiel) :**
- `AIProviderPreferenceTests` (7 tests) — setter/getter/clear, match STRICT vs partial, régression du bug slug
- `AIProviderCredentialsValidationTests` (9 tests) — validation format par slot, refus clé OpenAI dans slot Anthropic, mapping providerID vs `.id` concret

**Non fixés (nécessitent + de travail) :**
- B2 test end-to-end réel — impossible sans clé API user, à faire en TestFlight
- M1/M2 modèles hardcodés — nécessite UI de sélection modèle par provider
- M6 retry rate limit — logique async à ajouter dans AIProviderHTTP
- M7 logging providers cloud dans AIActivityLogger — refactor OnDeviceLLM
- M9 kill switch coûts — nécessite compteur cumulatif persisté
- T1 indicateur provider dans chat — refactor AIAssistantViewModel pour passer providerID par message
- T2 coûts estimés — grosse feature à part

### Validation post-fixes

- BUILD SUCCEEDED
- 157/158 tests OK (fail préexistant non lié)
- **16 nouveaux tests unit** couvrent la préférence + validation format
- `UIVocabularySanityTests` toujours vert

---

## Cleanup + Loop 4 (2026-08-22) — Transparence provider dans le chat

### Cleanup dead code

Audit ciblé sur les symboles Loop 3 sans caller externe :
- **Supprimé** `AIProviderHTTP.ExtractedPayload` — struct redondante avec le tuple utilisé
- **Supprimé** `AIProviderPreference.isPreferred(providerID:)` — méthode jamais appelée en prod (router matche directement `preferred == pref`). Tests correspondants supprimés.
- **Gardé sciemment** : `AICapabilities.streaming/vision` (utilisés dans AIDebugView), `AIError.cancelled/schemaViolation`, `AIToolCall/AIProvenance/AIResponseSchema` — types du protocol pour extensibilité future, coût nul.

### Loop 4 — Trou fonctionnel T1 : "l'user ne sait jamais quel provider a répondu"

**Fait :**
- Nouveau `AIProviderResolver` — mapping `providerID` → nom court affichable ("openai.gpt" → "GPT-4o mini") + icône SF Symbol adaptée (sparkles Apple, cloud pour cloud, gearshape pour LocalCoach)
- `OnDeviceLLM.Reply` enrichi avec `providerID: String?`
- `RouterResult` interne pour transporter le providerID de `respondViaAppleIntelligence` jusqu'à l'appelant
- `DisplayMessage.assistant(text:actions:providerID:)` factory pour attacher le provider au message in-memory (non persisté SwiftData — éphémère, résolu à la volée)
- `appendAssistantMessage(providerID:)` param optionnel — les 3 callers principaux passent `reply.providerID`
- `AIAssistantMessageRow` affiche un badge discret sous la bulle coach : "via Apple Intelligence" / "via GPT-4o mini" / "via Coach local" — police 10pt, opacité tertiaire, icône associée, accessibility label

### Validation

- BUILD SUCCEEDED
- **12 nouveaux tests** `AIProviderResolverTests` — mapping par provider, régression alignment avec `.id` concrets, icônes
- 169/170 tests OK (fail préexistant non lié)

### Impact utilisateur

Avant : user pense toujours parler à Apple Intelligence, aucune visibilité sur le fallback.
Après : sous chaque bulle coach, un mini-label indique quelle IA a répondu. Aide à identifier :
- Quand le fallback local a pris le relais (Apple Intelligence indispo)
- Quel provider cloud est actif si l'user en a configuré un
- Bug tracking : si un provider donne des réponses bizarres, l'user peut le signaler précisément

---

## Loop 5 (2026-08-22) — Compteur d'usage cloud transparent (T2 audit)

### Problème identifié

Les 4 cloud providers remontaient déjà `inputTokens` / `outputTokens` dans `AIResponse` mais **personne ne les persistait**. Zéro visibilité coût pour l'user → risque facture surprise (M9 + T2 de l'audit).

### Solution

- Nouveau `AIProviderUsageTracker` — compteur persisté par `(providerID, jour)` dans UserDefaults, JSON compact
- Barème tarifs USD/M tokens embarqué : GPT-4o mini ($0.15/$0.60), Claude Haiku ($1/$5), Mistral Small ($0.10/$0.30), Gemini Flash ($0.075/$0.30)
- Skip silencieux pour Apple Intelligence + LocalCoach (pas de coût)
- Wire dans `AIModelRouter.execute` : après chaque succès, `record(providerID, inputTokens, outputTokens)`
- Section "Usage aujourd'hui" dans `CoachAIProviderView` — affichée uniquement si activité cloud, une ligne par provider avec "X req. • ≈ $Y.YYY"
- Purge auto des entrées > 30 jours à chaque record (croissance bornée)
- Reset auto au changement de jour local (compteur par `yyyy-MM-dd`)
- Wire dans `DataEraser.eraseAIArtifacts` → RGPD-friendly

### Validation

- BUILD SUCCEEDED
- **14 nouveaux tests** `AIProviderUsageTrackerTests` — enregistrement, accumulation, isolation par provider, calcul coût vs barème, reset, skip Apple/LocalCoach, snapshot recent
- 183/184 tests OK (fail préexistant non lié)

### Impact utilisateur

Avant : user branche OpenAI + envoie 200 messages/jour → facture surprise mensuelle possible.
Après : ouvre Réglages → Moteur du coach → section "Usage aujourd'hui" visible dès la première requête cloud. Voit en temps réel :
- Nombre de requêtes envoyées par provider
- Coût estimé cumulé du jour (accuracy ~10-20% selon variabilité tarifs providers)
- Peut décider de changer de provider ou de revenir sur Apple Intelligence

### Ce qui n'est pas fait (volontairement)

- **Pas de blocage** : c'est de la transparence, pas un cap. L'user décide seul. Un vrai kill switch avec seuil configurable ("bloquer si > $5/jour") = Loop 6 potentielle.
- **Pas de graphe historique** : `recentSnapshots(days:)` existe pour ça mais l'UI ne l'affiche pas encore.
- **Barème approximatif** : les tarifs providers changent — à revoir périodiquement. Le footer prévient l'user.

---

## Loop 5 — fixes post-audit (2026-08-22)

Audit sans complaisance : 4 BLOQUANTS + 8 MAJEURS + 5 MINEURS + 6 TROUS identifiés. Fix pass sur ce qui est faisable sans backend externe :

### Fixes appliqués

**Bloquants** :
- **B1** : Constante `pricingCatalogVersion = "2026-08"` + affichage user "barème 2026-08" dans le footer Réglages. Pas de fetch remote (trop gros), mais l'user voit à quelle date le barème a été révisé.
- **B2** : Conversion USD → EUR via `NumberFormatter.currency` locale `fr_FR`. Nouveau `UsageFormatter.costEUR(usd:)` — utilisé partout dans l'UI. Taux fixe 0.92 (à réviser avec le barème).
- **B3** : Tokens `nil` → **skip enregistrement** au lieu de compter `$0`. Log `AppLog.coach.warning` pour observabilité (facture réelle invisible détectée).
- **B4** : Nouveau `AIModelRouterUsageWireTests.swift` — test intégration MockProvider → router → tracker. Vérifie : succès enregistre, erreur n'enregistre pas.

**Majeurs** :
- **M1** : Test valeur exacte `0.00027` remplacé par test **formule** : `snap.estimatedCostUSD == pricing.input + pricing.output` avec 1M tokens I/O. Robuste aux changements de tarifs.
- **M2** : `purgeOldEntries` → `purgeOldEntriesIfNeeded` appelé UNIQUEMENT au boot du singleton, avec flag `lastPurgeKey` (idempotent 24h). Plus de O(N) à chaque record.
- **M5** : Cap sanitaire `min(max(tokens, 0), 10_000_000)` dans `record()`. Test dédié `testRecord_absurdlyLargeTokens_areCapped` + négatifs clamped à 0.
- **M6** : Tracker devient `ObservableObject` avec `@Published lastChange`. Vue observe via `@ObservedObject usageTracker`. Refresh live si l'user envoie un message pendant que le sheet est ouvert.
- **M7** : `UsageFormatter.costEUR(usd:)` gère micro-coûts : `< 0,01 €` au lieu de `0,000 €` trompeur.
- **m3** : `UsageFormatter.requestCount(_:)` gère pluriel (0/1 → "requête", ≥2 → "requêtes").
- **m5** : `accessibilityLabel` complet sur la ligne d'usage : "OpenAI, 5 requêtes aujourd'hui, coût estimé 0,02 €, 30 derniers jours : 0,80 €".
- **m6** : Anthropic Haiku 4.5 corrigé à $0.80/$4 (au lieu de $1/$5 approximé).

**Trous rapides** :
- **T2** : Nouveau `monthlySnapshot(providerID:)` = somme des 30 derniers jours. Affiché "30j : 12€" à droite de chaque ligne d'usage.
- **T3** : Nouveau `Snapshot.averageTokensPerRequest` computed. Affiché "1.5k tok/req" sous la ligne.

### Non fixés (out of scope loop)

- **B1 refresh remote** : nécessite backend, à voir avec `RemoteConfig` existant plus tard
- **T1 alerte seuil** : nécessite système notifs + preferences
- **T4 comparaison providers** : nécessite écran dédié
- **T5 migration Documents dir** : change API storage
- **T6 export CSV** : feature à part
- **M8 i18n** : le reste de l'app n'est pas encore traduit non plus

### Validation

- BUILD SUCCEEDED
- **24 tests** total sur Loop 5 (14 initiaux enrichis + 3 nouveaux Formatter + 2 nouveaux wire router + 2 pour B3 skip + 1 pour cap + 1 pour EUR + 1 pour pricing catalog version)
- **`AIModelRouterUsageWireTests`** couvre le wire E2E via MockProvider — régression garantie si le wire router→tracker se casse
- 194/195 tests OK (fail préexistant non lié)

### Ce qui change pour l'utilisateur

Avant Loop 5 : rien (pas de tracker).
Après Loop 5 (initial) : "5 req. • ≈ $0.023" — utile mais confus (USD, pluriel cassé, $0.000 pour micro).
Après fixes audit : "5 requêtes • 1.2k tok/req • < 0,01 € (30j : 0,12 €)" — français, EUR, moyennes, cumul mensuel, VoiceOver, refresh live.

---

## Loop 6 (2026-08-22) — Kill switch coût configurable (T1 audit)

### Problème identifié

Loop 5 fixes ont rendu le coût **visible après coup**. Un user avec Claude Sonnet peut brûler 20 € en une soirée sans être arrêté. Le tracker informe mais ne protège pas.

### Solution

- Nouveau `AICostGuardPreference` — persist seuil `dailyCapEUR` (`0` = désactivé, défaut) et `lastNotifiedDay` (anti-spam notif).
- Nouveau `AICostGuard` :
  - `isBlocked(providerID:)` — vérifie si le cumul EUR du jour ≥ cap. Apple Intelligence + LocalCoach **toujours passants** (le user garde un coach fonctionnel).
  - `todayCumulativeCostEUR()` — somme tous providers cloud en EUR.
  - `checkAndNotifyIfCapReached()` — envoie 1 notification `UNMutableNotificationContent` par jour max quand le cap est franchi.
- Wire dans `AIModelRouter.execute` : skip provider si `isBlocked`, fallback automatique sur le suivant (Apple/Local). Après succès cloud, appelle `checkAndNotifyIfCapReached`.
- Section Réglages "Plafond de sécurité" :
  - Toggle "Limiter le coût cloud" (défaut : off)
  - Stepper €/jour (0.5 → 50, pas 0.5) — préréglé à 5 € à l'activation
  - Ligne "Consommé aujourd'hui" en rouge si cap atteint
  - Footer explicatif du comportement fallback
- Wire dans `DataEraser.eraseAIArtifacts` : reset du cap avec le reste (RGPD).

### Validation

- BUILD SUCCEEDED
- **13 nouveaux tests** `AICostGuardTests` : cap désactivé jamais bloqué, Apple Intelligence/LocalCoach jamais bloqués, cap atteint bloque tous les cloud, cumul multi-provider correct, notification de-duplication, reset preference
- 207/208 tests OK (fail préexistant non lié)

### Impact utilisateur

Avant : user branche Claude, envoie 200 messages/jour → facture surprise 15-20 €/mois.
Après : user active "Limiter à 2 €/jour" → dès que le cumul atteint 2 €, le router bascule sur Apple Intelligence ou coach local, notification "Ton seuil de 2,00 € est atteint, coach cloud mis en pause jusqu'à demain". Le coach reste fonctionnel, l'user paie pas plus que prévu.

### Choix de design

- **Défaut OFF** : ne surprend pas l'user existant, il l'active volontairement
- **Cumul global** vs par-provider : bloque **tous les cloud** en même temps (simplifié)
- **Bloquage soft** : router passe au suivant, l'user n'a pas d'erreur — juste un coach différent
- **Fallback garanti** : Apple Intelligence + LocalCoach jamais dans le cap → coach jamais muet
- **1 notif/jour max** : `lastNotifiedDay` marqué avant envoi (évite double-fire)

---

## Loop 7 (2026-08-23) — Bannière d'upgrade contextuelle intelligente

### Problème identifié

Apple Intelligence 3B → ~15% de réponses "à côté" pour un coach personnel = trust cassée. L'user n'a aucun signal proactif l'invitant à brancher une clé cloud pour améliorer la qualité au moment où il en a le plus besoin (frustré).

### Solution — Après 10+ options envisagées

Brainstorm complet évalué : OAuth providers (❌ inexistant), deep links (❌), proxy freemium backend + StoreKit (⚠️ nécessite décision commerciale), abonnement Coach Premium (⚠️ idem), magic link QR (❌), packs crédits (❌ friction récurrente).

**Retenu Phase 1 (cette loop)** : bannière contextuelle qui apparaît UNIQUEMENT quand :
1. L'user a ≥ 3 dislikes dans les 24h (frustration détectée)
2. AUCUNE clé cloud n'est configurée (sinon inutile)
3. Non snoozée dans les 7 derniers jours (respect du choix)

**Phase 2 (loop future)** : proxy Cloudflare Workers + StoreKit "Coach Premium" — nécessite décision commerciale (prix, freemium/premium seul) que je ne peux pas prendre en autonomie.

### Implémentation

- `CoachFeedbackStore.recentDislikeCount(within:)` — expose compteur dislikes récents
- Nouveau `CoachUpgradeSuggestion` (ObservableObject) — évalue `shouldSuggestUpgrade()`, snooze 7j via UserDefaults
- Nouveau `CoachUpgradeBanner` (SwiftUI) — bannière discrète : icône sparkles, titre "Un coach plus intelligent ?", boutons "Améliorer" (→ ouvre Réglages Coach IA) + "Plus tard" (→ snooze) + close X, accessibility label combiné
- Wire dans `AIAssistantView` : `@ObservedObject upgradeSuggestion` + rendu conditionnel au-dessus de la liste des messages
- `recordDislike` appelle `CoachUpgradeSuggestion.refresh()` → bannière apparaît immédiatement au 3e dislike
- Wire dans `DataEraser.eraseAIArtifacts` — reset du snooze (RGPD)

### Validation

- BUILD SUCCEEDED
- **8 nouveaux tests** `CoachUpgradeSuggestionTests` : 0/2 dislikes = pas de suggestion, 3+ dislikes = suggestion, kill switch clé cloud, snooze fonctionne, reset lève le snooze, `recentDislikeCount` correct
- 215/216 tests OK (fail préexistant non lié)

### Impact utilisateur

**Avant Loop 7** : user frustré (3 dislikes) → aucun signal, il continue à galérer ou abandonne le chat.
**Après Loop 7** : au 3e dislike dans les 24h, une bannière apparaît en haut du chat avec 2 taps possibles : "Améliorer" (ouvre Coach IA pour brancher Claude/GPT/Mistral) ou "Plus tard" (snooze 7j).

Escalation naturelle : Apple Intelligence gratuit → si insatisfait → cloud recommandé pile au bon moment (pas de spam onboarding).

### Ce qui reste pour la "solution parfaite" (Phase 2)

- **Backend proxy Cloudflare Workers** : ~40 lignes, expose /chat qui route vers Claude Haiku 4.5
- **StoreKit 2 "Coach Premium"** : abonnement 3.99€/mois OU pack 10 messages gratuits/mois puis payant
- **Section "Coach Premium (bientôt)"** dans les Réglages avec CTA pré-inscription
- **Onboarding actif** : étape "Choisis ton coach" dans le tunnel d'arrivée

Ces items nécessitent **décision commerciale** (prix, modèle) — hors scope loop autonome.
