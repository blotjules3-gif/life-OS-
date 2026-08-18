---
description: ship — Plan de bataille complet pour amener LifeOS à l'App Store (5 phases, exécution autonome)
argument-hint: [phase0|phase1|phase2|phase3|phase4|phase5|all]
---

# ship — Prépare LifeOS à shipper

Mode autonome multi-phases. Exécute tout ce qui reste pour passer LifeOS de "prototype avancé" à "app soumissable App Store et présentable investisseur".

**Argument :** `/ship phase0|phase1|phase2|phase3|phase4|phase5|all` — défaut = `phase0`

**Différence avec `/perfect`** : `/ship` intègre les découvertes de nos discussions (audit factuel, chat coach, migrations sûres) et priorise dans un ordre d'exécution différent basé sur ce qui débloque le plus vite.

---

## Contexte : ce qui est DÉJÀ fait (ne pas refaire)

### Fondations techniques
- `LifeOS/Services/AppLogger.swift` — logger `os.Logger` 9 catégories
- `LifeOS/Services/AppStorageKeys.swift` — 161 clés + 263 sites adoptés (1 seul littéral restant, le registre lui-même)
- `LifeOS/Services/DataEraser.swift` — 3 fonctions (erase / eraseAndKeepOnboarding / exportBackup)
- `LifeOS/Services/SentryConfig.swift` — structure prête, activation en 4 étapes
- `LifeOS/Services/ModuleUsageTracker.swift` — mesure usage réel des 15 modules
- `LifeOS/Services/LifeSignalSyncer.swift` — 3 syncers (Mood + Sleep + Nutrition)
- `UserContextBuilder` enrichi avec 7 insights cross-modules
- 30+ migrations `print` / `catch print` / `try? save` vers `AppLog` structuré
- 64 fonts safes migrées + 15 couleurs sémantiques
- Migration bulk @AppStorage → AppStorageKeys (263 sites)

### App Store readiness partielle
- `LifeOS/PrivacyInfo.xcprivacy` — manifest privacy complet
- `LifeOS/Info.plist` — NSPrivacyPolicyURL + NSTermsOfServiceURL + toutes les usage descriptions
- `LifeOS/Core/DataDeletionSheet.swift` — écran suppression compte + export JSON (créé, PAS branché)
- `LifeOS/Core/FAQView.swift` — 18 questions in-app (créée, PAS branchée)
- `docs/appstore/description-fr.md` — copie App Store complète
- `docs/observability/SENTRY_SETUP.md` — guide setup Sentry

### UI / composants
- `LifeOS/Shared/LifeStatusTile.swift` — tuile Home unifiée (créée, PAS utilisée)

### Qualité
- 45 tests unitaires (+18 dans les récentes sessions)
- CI GitHub Actions (`.github/workflows/ios-ci.yml`)
- 61 accessibility labels

### Ce que le chat sait déjà faire
- Streaming token par token
- Voice input + Speech recognition
- Analyse photo (Vision)
- Actions structurées (8 types : createTodo, createHabit, updateConfig, addModule…)
- Fallback offline (OfflineCoach + LocalCoach)
- Rotation quotidienne des conversations
- Détection intent Add rapide
- Bannière serveur down

---

## PHASE 0 — Brancher ce qui existe (30 min, à faire EN PREMIER)

Trois fichiers ont été créés mais ne sont pas atteignables par l'utilisateur.

### 0.1 Brancher `DataDeletionSheet` dans `ProfileView`
Ajouter une entrée "Mes données" qui présente `DataDeletionSheet()` en sheet.
Emplacement : section "Compte" ou "Confidentialité".

### 0.2 Brancher `FAQView` dans `ProfileView`
Ajouter une entrée "Aide et support" qui pousse `FAQView()` via NavigationLink.

### 0.3 Brancher `SentryConfig.start()` dans `AppDelegate`
Dans `application(_:didFinishLaunchingWithOptions:)`, appeler `SentryConfig.start()`.
No-op tant que le SDK Sentry n'est pas ajouté — aucun risque.

### 0.4 Vérifier build + tests
```bash
xcodebuild build && xcodebuild test
```

---

## PHASE 1 — App Store submissable (1 weekend)

### 1.1 Screenshots App Store (4h)
Créer 6 screenshots par taille dans `docs/appstore/screenshots/` :
- Format 6.9" : 1290 × 2796 px (iPhone 17 Pro Max)
- Format 6.7" : 1290 × 2778 px (iPhone 16 Pro Max)

Ordre suggéré (voir `docs/appstore/description-fr.md` section Screenshots) :
1. Home unifiée (état de vie + énergie)
2. Coach avec insight cross-modules visible
3. Écran habitudes + streak
4. Widget habits sur écran d'accueil
5. Sport hub avec courbe progression
6. Écran suppression données (rassure sur privacy)

**Méthode** : utiliser `xcrun simctl` pour capturer sur simulateur iPhone 17 Pro Max, puis ajouter overlay marketing (Figma ou Canva).

### 1.2 Héberger politique de confidentialité + CGU publiquement (30 min)
- Créer un repo GitHub Pages `lifeos-legal`
- Push `docs/privacy.html` et `docs/terms.html`
- Vérifier que `NSPrivacyPolicyURL` dans Info.plist pointe vers la bonne URL publique

### 1.3 Compte Apple Developer (1h humain)
- 99€/an sur developer.apple.com
- Configurer bundle ID `com.blotjules.lifeos`
- Créer App dans App Store Connect
- Ajouter les 6 screenshots + copie de `docs/appstore/description-fr.md`

### 1.4 Vérifier icône App Store (30 min)
- Icône 1024×1024 PNG SANS canal alpha
- Vérifier tous les slots dans Assets.xcassets/AppIcon.appiconset
- Test dans TestFlight interne

### 1.5 Build release + upload TestFlight (1h)
```bash
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -sdk iphoneos -configuration Release archive -archivePath build/LifeOS.xcarchive
```
Puis Xcode → Organizer → Distribute → App Store Connect.

---

## PHASE 2 — Chat coach v2 + i18n (2-3 semaines)

Note : cette phase combine deux gros chantiers. L'i18n a été ajoutée ici parce
qu'elle bloque l'usage de l'app par les utilisateurs iPhone anglais (mélange
FR/EN chaotique aujourd'hui).

### 2.1 Mémoire long terme (4h) — LE VRAI MOAT

Le modèle `MemoryEntry` existe dans `Models_Life.swift:94` mais n'est jamais utilisé. C'est la seule différence entre "chatbot IA" et "coach personnel".

**Créer `LifeOS/Services/MemoryExtractor.swift`** :
- Après chaque message user, analyse via heuristiques (Regex FR : "j'aime", "je veux", "mon objectif", "j'habite", "je bosse chez", …)
- Créer `MemoryEntry` avec category correcte (préférence / objectif / habitude / fait)
- Dédup avant insert (fetch existing par content similarity)

**Enrichir `UserContextBuilder.build()`** :
- Ajouter section "Ce que le coach sait de l'utilisateur" avec les MemoryEntry pinnées ou récentes (max 10)
- Format : "- L'utilisateur t'a dit : [content]"

**Créer `LifeOS/Core/MemoryHubView.swift`** :
- Liste des memories groupées par catégorie
- Bouton pin/unpin, edit, delete
- Ajout manuel
- Accessible depuis Profile → "Mémoire du coach"

**Backend** : l'action `remember_user_info` est déjà déclarée dans `backend/app/main.py:68`. Vérifier qu'elle est bien gérée côté iOS via `execute(action:)`.

### 2.2 Chips de réponse rapide (2h)

Aujourd'hui, après un message coach, l'user doit taper. 60% des messages appellent une réponse binaire.

**Options d'implémentation** :

Option A (safe) — détection heuristique côté iOS :
- Après réception d'un message assistant, analyser : question ouverte (contient "?") + patterns ("tu veux", "on regarde", "je te propose")
- Générer 2-3 chips depuis dictionnaire : `["Oui", "Pas maintenant", "Explique"]`

Option B (mieux) — backend renvoie les chips :
- Ajouter clé `suggestions: [String]` dans le JSON de réponse backend
- Modèle demande explicitement des suggestions dans son prompt système
- Frontend affiche les chips

**Créer `LifeOS/Shared/ChatQuickReplies.swift`** — composant réutilisable.
Brancher sous chaque message assistant dans `AIAssistantView`.

### 2.3 Message d'accueil ultra contextualisé (3h)

Trouver `triggerWelcome()` dans `AIAssistantView.swift` (~ligne 283).

**Actuellement** : probablement générique.

**Cible** : utilise les 7 insights `crossModuleInsights` du `UserContextBuilder` pour construire un premier message qui DÉMONTRE la valeur immédiatement.

Exemple d'output :
> "Salut Jules. Nuit 5h30 hier, séance muscu prévue tout à l'heure, tu es à 42% de tes protéines. Tu veux qu'on regarde comment prioriser aujourd'hui ?"

Envoyer avec 3 chips : `[Oui, prioriser] [Explique] [Non merci]`.

### 2.4 Rendu markdown dans les messages (2h)

Actuellement les messages sont probablement en plain text.

Utiliser `AttributedString(markdown:)` disponible depuis iOS 15 :
- Bold : `**text**`
- Italic : `*text*`
- Listes : `- item`
- Liens : `[text](url)`

Vérifier dans `MessageCell` du chat, wrapper le `Text` en `Text(AttributedString(markdown: msg.text))`.

Attention : `AttributedString(markdown:)` throws — fallback sur plain text si parse fail.

### 2.5 Retry auto avec backoff (1h)

Aujourd'hui, si le serveur foire une fois → user doit re-envoyer.

Dans `send()` de `AIAssistantView` : wrapper l'appel réseau dans un helper `retryWithBackoff(attempts: 3, delays: [1, 3, 7])`. Log chaque retry via `AppLog.net.warning`.

### 2.6 Suggestions contextuelles dynamiques (3h)

Actuellement `shouldShowSuggestions(at:)` existe (ligne 1332) mais probablement basique.

Enrichir : selon l'heure du jour + le contexte cross-module, proposer 3 sujets d'entrée dans le chat :
- Matin : "Comment va ton énergie ?" / "Ton plan du jour" / "Ta séance de ce soir"
- Midi : "Ton apport protéines" / "Ta prochaine pause" / "Focus après-midi"
- Soir : "Bilan de ta journée" / "Prépare ta nuit" / "Ton humeur"

### 2.7 Extraction 321 `Text("...")` FR hardcodés (2h)

Chercher tous les `Text("<phrase française>")` dans `LifeOS/**/*.swift` et les
remplacer par `Text(String(localized: "clé.stable"))`. Ajouter chaque nouvelle
clé dans `LifeOS/Localizable.xcstrings` avec la valeur FR source.

Convention de nommage : `<module>.<contexte>.<action>` (ex. `chat.input.placeholder`,
`fitness.hub.title`). Skip les strings d'un seul caractère et les emoji.

Vérifier après : `grep -rE 'Text\("[A-Z][a-zà-ÿ]{4,}' LifeOS --include="*.swift" | wc -l`
doit tendre vers 0.

### 2.8 Traduction 1068 clés EN (3h)

`Localizable.xcstrings` a 1134 clés dont 66 seulement traduites en EN.

Étapes :
1. Extraire les clés non traduites via script Python.
2. Envoyer par batch de 50 à une API de traduction (préférer un LLM pour respecter
   le ton coach de tutoiement).
3. Injecter les traductions dans le xcstrings via script.
4. Marquer `state: "translated"`.
5. Review humaine sur 50 termes techniques.

### 2.9 Sélecteur de langue dans les réglages (1h)

Dans `ProfileView.swift` section Réglages, ajouter une entrée "Langue" qui présente
un sheet `LanguagePickerSheet.swift` :
- Toggle "Automatique (langue système)" — ON par défaut
- Si OFF : picker Français / English
- Persistance via `AppStorageKeys.appLanguage`
- Application immédiate via `UserDefaults.standard.set([code], forKey: "AppleLanguages")`
  + alerte "Redémarre l'app pour appliquer"

### 2.10 Vérifier la détection auto (30 min)

Vérifier que :
- Sur iPhone FR : app 100% FR
- Sur iPhone EN : app 100% EN (après 2.7 + 2.8)
- Sur autre langue : fallback FR

---

## PHASE 3 — UX visible refonte (3 semaines)

### 3.1 Nouvelle HomeView avec LifeStatusTile (6h)

`LifeStatusTile.swift` existe (fait précédemment) mais n'est utilisé nulle part. Créer `LifeOS/Core/HomeView.swift` qui remplace `ShortcutsHomeView` dans `MainTabView`.

Structure :
- `LifeOS/Core/Home/HomeView.swift` (racine)
- `Home/Home+HeroEnergy.swift` (EnergyScore en héros animé)
- `Home/Home+LifeStatusGrid.swift` (6 tuiles agrégeant 15 modules via `LifeStatusTile`)
- `Home/Home+CoachCTA.swift` (bouton "Parler à ton coach" gros et visible)
- `Home/Home+NextMoment.swift` (prochaine fenêtre d'action via `ContextualNotifications`)
- `Home/Home+HabitsRow.swift` (habitudes du jour, horizontal scroll)

Archiver `ShortcutsHomeView.swift` (renommer `.swift.archived`, garder pour référence).

### 3.2 Refonte onboarding 3 écrans (8h)

Remplacer `OnboardingView.swift` (1597 lignes) + `IntakeHubView` par 3 écrans :

- `LifeOS/Core/Onboarding/OnboardingRouter.swift` (flow)
- `Onboarding/StepIdentity.swift` : prénom + objectif principal (5 choix)
- `Onboarding/StepModules.swift` : 3 modules pré-cochés (décision inversée)
- `Onboarding/StepNotifications.swift` : permission notifs en contexte

Direct dans la Home après ces 3 étapes. `IntakeHubView` supprimé — le setup module se fait au fur et à mesure via un empty state dans chaque hub.

### 3.3 Découpe `AIAssistantView.swift` (4h)

1708 lignes → 4 fichiers :
- `LifeOS/Shared/AIAssistant/AIAssistantViewModel.swift` (déjà séparé dans le code, extraire)
- `AIAssistant/AIAssistantInputBar.swift` (input + voice + waveform)
- `AIAssistant/AIAssistantMessageCells.swift` (rendus messages user/assistant/streaming)
- `AIAssistantView.swift` reste (body principal)

Vérifier compil + tests après chaque extraction.

### 3.4 60 fps profiling + fixes (3h)

Lancer Instruments Time Profiler sur les 4 scrolls principaux :
- HomeView (nouvelle)
- Chat (avec 50+ messages)
- Fitness hub
- BubbleCategoriesView

Identifier frames > 16ms. Fixer :
- LazyVStack au lieu de VStack sur les listes
- Cache d'images `AsyncImage`
- Éviter computed properties coûteuses dans les body

Documenter dans `docs/perf-report.md`.

---

## PHASE 4 — Qualité invisible (2 semaines)

### 4.1 +30 tests supplémentaires (6h)
Cibles :
- `MemoryExtractorTests` (10 patterns d'extraction)
- `DataEraserTests` (erase all / erase keep onboarding / export)
- `LifeSignalSyncerTests` (sync moods, sleeps, kcal)
- `UserContextBuilderTests` (crossModuleInsights avec cas variés)
- `NotificationManagerTests` (schedule, cancel, weekly bilan)
- `EnergyScoreTests` (variations d'input)

Objectif : passer de 45 à 75+ tests, coverage > 45% sur `Services/`.

### 4.2 Sentry activation avec DSN (1h)
Suivre `docs/observability/SENTRY_SETUP.md`. Nécessite compte Sentry (gratuit).

### 4.3 Prompt caching Mistral (2h)
Dans le backend, activer prompt caching sur les blocs `CoachExpertise` (15k chars fixes par persona). Économie 50-70% sur les tokens répétés.

Fichier : `backend/app/modules/*/tools.py` + `backend/app/core/prompts.py`.

### 4.4 Rate limit user-based backend (2h)
Actuellement `device_id`. Un user avec 2 devices contourne. Migrer sur `user_id` dans `backend/app/dependencies.py` + middleware.

### 4.5 (déplacé en Phase 2.7)
Extraction 321 Text() FR — cf. Phase 2.7.

### 4.6 (déplacé en Phase 2.8)
Traduction 1068 clés EN — cf. Phase 2.8.

---

## PHASE 6 — Chat IA next-level (3-4 semaines)

Objectif : passer du "chat coach v2" au "meilleur chat IA que ton user ait vu".
Simple pour l'usage courant, puissant quand il faut, respectueux des limites.

Prérequis : Phase 2 (chat coach v2) validée en runtime.

### 6.1 Trackers personnalisés dynamiques (6h) — LE PLUS DEMANDÉ

Nouveau modèle SwiftData `CustomTracker` avec champs dynamiques :
- `name` (ex : "Peptides BPC-157")
- `unit` (ex : "mg", "prises", "gouttes")
- `targetDaily`, `targetWeekly` (Double optionnels)
- `category` (santé, sport, alimentation, autre)
- `iconName`, `colorHex`
- `notes`
- `createdAt`, `isArchived`

+ `CustomTrackerEntry` : `date`, `value: Double`, `note: String`.

Nouvelle action AI : `create_tracker` avec extraction des champs depuis le
message user. Ex : "Traque ma prise de peptides BPC-157, 250 mcg matin et soir"
→ crée le tracker + 2 rappels + entrée initiale.

Écran `TrackerListView` + `TrackerDetailView` accessibles depuis Profil.
Le hub Custom apparaît dans Categories en dessous des 15 modules.

### 6.2 Recherche web (4h) — SE RENSEIGNER

Créer `LifeOS/Services/WebResearcher.swift` qui appelle un endpoint backend
`/research?query=...` (à ajouter dans `backend/app/api/v1/`). Le backend
utilise Brave Search API ou Serper (~$0.005/req).

Détection intent : "renseigne-toi sur X", "qu'est-ce que X", "explique-moi X".
Résultat inséré dans le contexte avant la réponse coach :
- 3 sources (titre + URL + extrait)
- Le coach synthétise en 3-4 lignes + cite les sources en fin

Affichage : chips "sources" cliquables sous la réponse coach.

### 6.3 Limites et guardrails définis par l'user (3h)

Nouvel écran `CoachPreferencesView` dans Profil :
- **Sujets à éviter** (chips à ajouter/retirer)
- **Ton préféré** : strict / bienveillant / expert / motivant
- **Longueur réponses** : courte / moyenne / détaillée
- **Emojis** : oui / non
- **Tutoiement** : oui / vouvoiement

Persisté via `AppStorageKeys.coachTone`, `coachLength`, `coachTopicsToAvoid`, etc.

Injection systématique dans le prompt système via `UserContextBuilder` :
```
Préférences user :
- Ton : bienveillant
- Longueur : courte (2-3 phrases max)
- Éviter : viande, vouvoiement
```

### 6.4 Multi-modes ponctuels (2h)

Sélecteur de mode inline dans l'input du chat (icône 🎚️ à côté du micro) :
- **Coach** (défaut, tout venant)
- **Expert** (technique, chiffres, sources)
- **Motivation** (bref, punchy, urgent)
- **Analyse** (bilan structuré, sections)

Persisté par conversation seulement. Modifie temporairement le prompt système.

### 6.5 Guardrails médicaux + finance + légal (2h)

Détection heuristique côté iOS de topics sensibles :
- Doses médicamenteuses (`X mg`, `X UI`, `mcg`)
- Décisions financières (`vendre`, `acheter`, `investir X€`)
- Questions légales (`suis-je en droit`, `mon employeur`)

Ajout systématique dans la réponse coach d'un badge "Ce n'est pas un conseil
médical / financier / légal — consulte un pro."

### 6.6 TTS pour lire les réponses (2h)

`AVSpeechSynthesizer` intégré dans `MessageRow`. Bouton "haut-parleur" sur
chaque message coach → lecture voix française (voice quality `.enhanced`
si dispo).

Toggle global "lecture auto" dans `CoachPreferencesView` : lit toutes les
réponses coach automatiquement (utile en mains libres pendant le sport).

### 6.7 Feedback loop 👍/👎 (2h)

Sur chaque message coach, 2 boutons discrets sous le message :
- 👍 "Utile"
- 👎 "Pas utile"

Stockage local via nouveau modèle `AIMessageFeedback`. Envoi au backend
optionnel (opt-in). Injection dans le contexte système : "L'user a marqué
comme peu utile 3 de tes dernières réponses — adapte ton approche."

### 6.8 Historique long + résumé (3h)

Actuellement le chat reset toutes les 24h.

Nouveau : garder les 100 derniers messages accessibles via scroll. Au-delà,
résumer les 100 précédents en 500 chars via Apple Intelligence + stocker
le résumé dans un modèle `AIConversationSummary`.

Injection du résumé de la semaine dans le contexte système :
```
Résumé de la semaine (7j) : L'user a évoqué X, s'inquiète de Y, a testé Z.
```

### 6.9 Reset conversation + historique navigable (2h)

Bouton "Nouvelle conversation" dans le menu ⋯ du chat.
Écran `ConversationHistoryView` accessible depuis Profil :
- Liste des conversations passées (groupées par jour)
- Tap → replay dans un mode read-only
- Long-press → supprimer

### 6.10 Suggestions proactives via notifications (3h)

Créer `LifeOS/Services/ProactiveCoach.swift` qui se déclenche via
`BGAppRefreshTask` :
- Analyse les données récentes (streak cassé, sommeil détérioré, séance manquée)
- Génère 1 message coach par jour max (via Apple Intelligence local)
- Envoie une notification "Ton coach te dit : ..." avec deeplink vers le chat

Toggle "Coach proactif" dans `CoachPreferencesView` (opt-in obligatoire).

### 6.11 Attachements élargis (3h)

Ajouter dans l'input :
- **Document scan** (VisionKit) — pour analyser bilans sanguins, ordonnances
- **Fichier** (`.pdf`, `.txt`) — via `.fileImporter`
- **Audio note** (30s max) — pour transcription via Speech + envoi

Chaque attachement passe par un pré-traitement (OCR pour PDF, transcription
pour audio) avant d'être injecté comme texte dans le prompt.

### 6.12 Détection intent sémantique (via Apple Intelligence local) (3h)

Remplacer `detectAddIntent` (heuristique keyword) par une vraie détection
sémantique locale :
- Prompt court à Apple Intelligence : "Extrais l'intent : `{message}`.
  Réponds JSON : `{intent, entity, module}`."
- Intents supportés : `add_task`, `add_habit`, `add_tracker`, `log_entry`,
  `search`, `advice`, `report`, `chat`.
- Si intent clair → shortcut action, si `chat` → conversation classique.

Le user ressent que le coach "comprend" plutôt qu'il "matche des mots".

---

## Estimation Phase 6

**Total ~35h de dev** (3-4 semaines de sessions dédiées).

Ordre recommandé pour ROI immédiat :
1. **6.3** (limites/ton) — 3h — impact immédiat sur tous les messages
2. **6.1** (trackers custom) — 6h — feature très demandée
3. **6.5** (guardrails) — 2h — safety avant qu'on shippe
4. **6.4** (modes) — 2h — polish rapide
5. **6.9** (reset + historique) — 2h — UX de base
6. **6.6** (TTS) — 2h — accessibilité + mains libres
7. **6.7** (feedback) — 2h — boucle d'apprentissage
8. **6.2** (web search) — 4h — nécessite backend endpoint + clé API externe
9. **6.11** (attachements) — 3h — VisionKit + fileImporter
10. **6.8** (historique long) — 3h — complexité SwiftData
11. **6.10** (proactif) — 3h — BGAppRefreshTask + notifs
12. **6.12** (intent sémantique) — 3h — dépend Apple Intelligence disponibilité

---

## PHASE 5 — Polish + growth (continu, après App Store)

### 5.1 Découpe des God files restants (12h)
Dans l'ordre :
- `ShortcutsHomeView.swift` (1630 lignes) — sera de facto remplacé par HomeView
- `OnboardingView.swift` (1597 lignes) — sera de facto remplacé
- `ProfileView.swift` (1170 lignes) → 3 fichiers

### 5.2 Migration 531 fonts custom (8h)
Décision par écran. Ne toucher que si taille = token ±1pt. Documenter les cas custom volontaires.

### 5.3 Migration 305 couleurs Core (5h)
Case-by-case avec validation visuelle. Skip les mesh gradients et dégradés custom.

### 5.4 Analytics events + funnel (3h)
Étendre `Analytics.swift` :
- `chat.message.sent`, `chat.action.executed`
- `module.opened` (avec module) — déjà via ModuleUsageTracker
- `habit.completed`, `onboarding.step.completed`, `intake.step.completed`
Créer funnel Install → Onboarding OK → Premier chat → J1 → J7.

### 5.5 App Intents étendus (4h)
Compléter `LifeOSIntents.swift` avec 10 intents Siri :
- Logger un verre d'eau
- Ajouter un repas rapide
- Commencer une séance muscu
- Voir mon énergie du jour
- Créer une habitude
- Marquer une habitude faite
- Ouvrir un module précis
- Voir mes stats de la semaine
- Parler au coach
- Enregistrer une humeur

### 5.6 Notifications riches (3h)
Enrichir `NotificationManager` :
- Actions inline (marquer fait, snooze, ouvrir module)
- Contenus dynamiques (score du jour dans le titre)
- Sons custom pour alarmes importantes

### 5.7 Widget audit (1h)
Tester chaque widget (Habits, Alarm, ChallengeStreak, EnergyScore) sur simulateur iOS 17+.

### 5.8 Dynamic Type audit (2h)
Tester chaque écran principal à la taille système la plus grande. Fixer les débordements.

### 5.9 Backup manuel utilisateur (3h)
Export JSON complet (pas juste l'aperçu de `DataEraser.exportBackup`) via `ShareLink`. Import avec merge intelligent.

### 5.10 Endpoint `/admin/usage` backend (2h)
Compteur DAU, messages/heure, latence p50/p95 Mistral, coût estimé du jour.

---

## Règles d'exécution (impératives)

### Avant toute action
1. Lire les fichiers concernés (`Read`) avant d'éditer
2. Créer les tâches via `TaskCreate` pour tracker
3. Marquer `in_progress` avant, `completed` après

### Pendant chaque item
1. Vérifier accolades après chaque édition Swift (Diff: 0)
2. Ignorer les diagnostics SourceKit faux positifs
3. Ne JAMAIS toucher au pbxproj
4. Respecter les règles CLAUDE.md :
   - Pas d'emojis dans le code ou l'UI
   - Textes UI en français, tutoiement
   - Pas de commentaires IA génériques
   - UI ne dit jamais "IA / LLM / modèle" → "ton coach"
5. Si un fichier > 500 lignes doit être créé, avertir + demander confirmation

### Après chaque item
1. `xcodebuild build` doit rester vert
2. Tests doivent rester verts (minimum en fin de phase)
3. L'auto-commit loop tourne — pas besoin de commit explicite

### Après chaque phase
1. Build + tests complets
2. Rapport court : items faits, items skippés (avec raison), bugs trouvés + fixés
3. Vérification que l'app se lance dans le simulateur

### En fin d'exécution
Rapport final structuré :
- Phase X : items faits · items skippés (avec raison)
- Bugs trouvés + corrigés
- Métriques : tests, a11y labels, tokens adoptés
- Build : SUCCEEDED / FAILED
- Runtime : app lancée OK ou non
- 3 suggestions pour la suite

---

## Contraintes hard (jamais dévier)

- Ne pas casser les tests existants
- Ne pas casser le build
- Ne pas toucher `Bubble.metal` (shader Metal)
- Ne pas modifier `Theme.swift` sauf pour AJOUTER des tokens
- Ne pas modifier les modèles SwiftData sans migration
- Ne pas commit des secrets
- Ne pas déployer le backend sans confirmation

---

## Mot d'arrêt

Si l'utilisateur écrit "stop", "STOP", "arrête", "annule", ou "fin" → arrêt immédiat.
Répondre uniquement : "Arrêté." puis lister ce qui n'a pas été fait dans la phase en cours.

---

## Estimation totale

| Phase | Durée | Objectif |
|---|---|---|
| Phase 0 | 30 min | Brancher ce qui existe |
| Phase 1 | 1 weekend | App Store submissable |
| Phase 2 | 2-3 semaines | Chat coach v2 (mémoire, chips, welcome) + i18n complète (FR/EN + sélecteur) |
| Phase 3 | 3 semaines | Refonte UX visible (Home, onboarding, découpe chat) |
| Phase 4 | 2 semaines | Qualité invisible (tests, Sentry, i18n) |
| Phase 5 | continu | Polish + growth après App Store |
| Phase 6 | 3-4 semaines | Chat IA next-level (trackers custom, web search, modes, guardrails) |
| **TOTAL avant App Store** | **~7 semaines** | Soumission possible |
| **TOTAL avec Phase 5** | **~12 semaines** | App parfaite |
| **TOTAL avec Phase 6** | **~16 semaines** | Chat IA différenciant |

---

## Argument par défaut

- `/ship` seul → **phase0** uniquement (brancher ce qui existe — 30 min, débloque tout)
- `/ship phase1` (ou phase2, phase3, phase4, phase5) → uniquement cette phase
- `/ship all` → enchaîne les 5 phases dans l'ordre sans s'arrêter sauf blocker

Pour `all` : prévenir en début que ça représente ~12 semaines de travail. Confirmer une fois puis attaquer sans re-demander.

---

## Rappel

Cette commande est **exhaustive et autonome**. Ne pas demander de confirmation à chaque item. Ne pas s'arrêter pour clarifier des choix esthétiques mineurs (utiliser le meilleur jugement). Signaler uniquement les vrais blockers.
