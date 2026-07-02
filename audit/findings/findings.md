# LifeOS — Findings (audit 2026-07-02)

## BLOQUANT

### [B1] Secrets de production publiés sur GitHub
Fichier: `backend/.env` (tracké en git), `.git/config` (remote URL), `LifeOS/Services/Configuration.swift:32`
Problème: trois fuites simultanées, toutes poussées sur le repo `jules175/B-compagny-` :
1. `backend/.env` est versionné avec `MISTRAL_API_KEY=EYb80…`, `INTERNAL_API_KEY=82d35e070ca086f995b84718054cfac5`, `SECRET_KEY=2b60b384…` en clair.
2. Le remote git embarque un PAT GitHub en clair : `https://ghp_6nTm…@github.com/jules175/B-compagny-.git`.
3. La clé API prod est le fallback hardcodé dans le binaire iOS (`return "82d35e07…" // fallback développement local`).
Preuve: `git ls-files backend/.env` → tracké ; `git config remote.origin.url` → PAT visible ; Configuration.swift:32 à HEAD.
Impact: quiconque a (eu) accès au repo peut consommer le compte Mistral (facturation), appeler l'API prod comme n'importe quel utilisateur, et pousser du code avec le PAT. Une rotation ne suffit pas — l'historique git doit être purgé.

### [B2] Impersonation par device_id — les données santé de n'importe qui sont lisibles
Fichier: `backend/app/api/v1/endpoints/chat.py:33,142`, `energy.py:56,105,132,143`, `dependencies.py`
Problème: l'identité utilisateur = `device_id` fourni par le client, sans aucun secret par utilisateur. La seule barrière est la clé API **partagée**, qui est publique (B1).
Preuve: `get_or_create_user(session, body.device_id)` — aucun contrôle de possession ; `/chat/history/{id}?device_id=X` renvoie les conversations de X.
Impact: avec la clé leakée + un device_id deviné/intercepté : lecture des conversations (santé mentale, médical, finances), injection de faux check-ins, pollution de la mémoire `user_notes`. Pour une app qui stocke humeur, cycle menstruel et médicaments, c'est une violation RGPD en puissance.

### [B3] Perte de données silencieuse — le store SwiftData est effacé sans consentement
Fichier: `LifeOS/LifeOSApp.swift:180-188`
Problème: si la migration SwiftData échoue au lancement, l'app supprime le store + `-shm`/`-wal` (« on efface le store et on repart propre ») et repart à zéro, sans backup, sans alerte, sans consentement.
Preuve: `try? FileManager.default.removeItem(at: storeURL)` dans le catch de `buildContainer()`.
Impact: un simple changement de schéma non-migratable (fréquent avec ~50 entités et 2 devs qui commitent en auto toutes les 15 min) détruit habitudes, humeurs, repas, mesures, photos de progression de TOUS les utilisateurs à la mise à jour. Irréversible.

### [B4] La chaîne push serveur n'existe pas en production
Fichier: `backend/railway.json` (startCommand), `backend/app/tasks/celery_app.py:24-33`
Problème: le beat Celery (dispatch APNs toutes les 5 min) et le worker n'apparaissent que dans `docker-compose.yml` (local). Railway ne lance que `uvicorn`.
Preuve: `"startCommand": "sh -c 'uvicorn app.main:app …'"` — aucun process `celery worker` ni `celery beat`.
Impact: tous les check-ins promis par le coach (`schedule_followup` — « je te relance demain ») écrits dans `ScheduledNotification` **ne partent jamais** ; `analyze_habits_task` (7h quotidien) ne tourne jamais. Le pilier « coach proactif » du produit est une promesse morte côté serveur ; les lignes s'accumulent en base. Seules les notifs locales sauvent partiellement la face.

## MAJEUR

### [M1] compute_insights crash — comparaison datetime vs str
Fichier: `backend/app/services/behavioral_insights.py:43`
Problème: `r.checkin_date >= (today - timedelta(days=7)).isoformat()[:10] or (…)` compare un `datetime` à une `str` → `TypeError` dès qu'un utilisateur a ≥ 6 check-ins scorés.
Preuve: `checkin_date` est `DateTime` (db.py:203) ; `.isoformat()[:10]` est une chaîne ; l'opérande gauche du `or` s'évalue en premier.
Impact: `/energy/insights` → 500 ; l'outil `get_user_context` échoue pour les utilisateurs les plus engagés — exactement ceux dont le « jumeau comportemental » devrait apprendre. Le pilier insights est cassé pour tout utilisateur actif > 6 jours.

### [M2] Fichiers AI/*.md jamais chargés en production
Fichier: `backend/app/core/llm/prompts.py:7,10-15`, `backend/Dockerfile` (WORKDIR /app, COPY . .)
Problème: `_AI_DIR` remonte 5 parents jusqu'à la racine du repo (`…/AI`), mais l'image Docker ne contient que `backend/`. `_load_ai_file` renvoie `""` silencieusement (catch FileNotFoundError).
Preuve: dans le conteneur, le chemin résolu est `/AI` — inexistant.
Impact: `PROBLEMES_SOLUTIONS.md` (protocole diagnostic), `QUESTIONS_MODULES.md` (questions de config auxquelles le prompt fait explicitement référence dans ses exemples) et `INSTRUCTIONS_CUSTOM.md` sont absents en prod. Le coach prod se comporte différemment du coach testé en local, sans aucun signal.

### [M3] habit_analyzer cherche le module "sport" qui n'existe pas
Fichier: `backend/app/services/habit_analyzer.py:18,62`
Problème: le module s'appelle `fitness` partout (executor `_VALID_MODULES`, prompts, app iOS) mais l'analyzer teste `if "sport" in configs`.
Preuve: `_VALID_MODULES` (executor.py:107) contient `fitness`, pas `sport`.
Impact: même si le beat tournait (B4), la branche sport ne se déclencherait jamais. Double panne masquée : B4 cache M3.

### [M4] Le mot « IA » affiché partout — violation du spec maître
Fichier: `AIAssistantView.swift:571` (« Assistant IA »), `:263` (« L'IA met trop de temps à répondre »), `ShortcutsHomeView.swift:360` (« Ton assistant IA est en bas »), `:447`, `:1116` (« Analyse IA »), `ProfileView.swift:735`, `:1190`
Problème: le spec maître interdit explicitement d'afficher « IA », « intelligence artificielle », « LLM »… L'illusion du « jumeau comportemental » exige que l'assistant soit un compagnon, pas un chatbot étiqueté.
Impact: positionnement produit cassé à 7 endroits visibles, dont le titre même de l'écran principal du produit.

### [M5] Le chat est inutilisable hors-ligne — même l'historique
Fichier: `LifeOS/Core/MainTabView.swift:87-102`
Problème: `openAIAssistant()` exige un `ping()` réussi (timeout 1,5 s) avant d'ouvrir le chat. Hors-ligne : ni envoyer, ni **relire** ses conversations (stockées localement en SwiftData !).
Impact: friction majeure (métro, avion) + 1,5 s de latence artificielle à chaque ouverture quand le serveur est lent. L'historique local existe mais est pris en otage par le réseau.

### [M6] Permission notifications au premier écran + notification « aveugle » à +5 s
Fichier: `LifeOS/LifeOSApp.swift:96-107`, `LifeOS/Core/OnboardingView.swift:273-278`
Problème: la demande de permission part dans `.onAppear` du contenu — pendant l'écran de bienvenue, sans contexte. Puis l'onboarding programme à +5 s « Ton assistant t'a envoyé un message » — avant que l'utilisateur ait vu le moindre message.
Impact: opt-in effondré (~40 % vs ~70 % avec pré-prompt contextuel) ; un refus iOS est quasi définitif → les 25+ notifications contextuelles (le vrai différenciateur) meurent à l'install pour la moitié des utilisateurs.

### [M7] update_config : le LLM écrit n'importe quelle clé UserDefaults
Fichier: `LifeOS/Shared/AIAssistantView.swift:423-433`
Problème: l'action `.updateConfig` renvoyée par le serveur écrit `UserDefaults.standard.set(value, forKey: key)` sans allowlist.
Preuve: aucune validation de `key` — `onboardingDone`, `recommendedModules`, `agentAPIKey`… tout est écrasable par une sortie LLM (ou par le serveur compromis via B1/B2).
Impact: une hallucination de clé corrompt la config locale ; combiné à B2, un attaquant peut téléguider l'état de l'app d'un utilisateur.

### [M8] URL force-unwrap — crash en boucle possible via ServerConfigView
Fichier: `LifeOS/Services/Configuration.swift:57`
Problème: `URL(string: apiBaseURL)!` alors que `apiBaseURL` peut venir d'un override UserDefaults saisi à la main dans `ServerConfigView` (accessible en prod, M9).
Impact: une URL avec espace → nil → crash au premier appel réseau, à chaque lancement. Seule issue : réinstaller l'app (et perdre les données, cf. B3).

### [M9] ServerConfigView (URL + clé API éditables) accessible en production
Fichier: `LifeOS/Shared/AIAssistantView.swift` (ServerConfigView), `ProfileView.swift:1190`, `MainTabView.swift` (dot statut serveur)
Problème: un écran de debug (changer l'URL du serveur et la clé API) est exposé dans les réglages et via le dot de statut, sans flag DEBUG.
Impact: surface d'erreur utilisateur (cf. M8), fuite de la notion de « serveur » dans un produit qui vend un compagnon invisible.

### [M10] Retry LLM sur TOUTE exception
Fichier: `backend/app/core/llm/wrapper.py:82`
Problème: `retry_if_exception_type((LLMValidationError, Exception))` — tenacity retente 3× avec backoff même sur 401, clé invalide, requête malformée.
Impact: erreurs non transitoires = latence ×3 + coût API inutile ; l'utilisateur regarde « … » pendant ~15 s pour un échec certain d'avance.

### [M11] Schéma DB : create_all au boot + migrations SQL manuelles
Fichier: `backend/app/main.py:94-95`, `backend/migrations/001→004.sql`
Problème: deux sources de vérité du schéma. `create_all` ne fait que créer les tables manquantes — il ne migre rien ; les .sql ne sont appliqués que par docker-entrypoint local.
Impact: tout changement de colonne en prod = drift silencieux ou crash au premier SELECT. Pas d'Alembic alors que SQLAlchemy est déjà là.

### [M12] Accessibilité quasi absente
Fichier: app entière — 8 `accessibilityLabel` sur 92 fichiers
Problème: boutons icône-seule sans label (tab bar, raccourcis, mood emojis), pas de Dynamic Type sur les tailles fixes (`.system(size:)` partout).
Impact: VoiceOver inutilisable ; risque EAA 2025 pour une app santé/bien-être.

## MINEUR

- [m1] Copy sans accents dans l'onboarding et l'accueil (« Ou tu t'entraines ? », « Regime alimentaire ? », « Debutant », « Reessayer ») — incohérent avec le reste, accentué correctement.
- [m2] Emojis dans l'UI et les notifs (mood 😞→😄, « quand tu peux 😉 » AppDelegate, « Oui ✓ ») — contraire à la règle projet « pas d'emojis ».
- [m3] 16 `print()` de debug (dont hors `#if DEBUG`) ; 3 catch silencieux : `HealthService.swift:62`, `ShortcutsHomeView.swift:1172` (loadAIBilan), `AlarmLiveActivityManager.swift:89`.
- [m4] `ScheduledNotification` jamais purgées (sent ou expirées) — croissance infinie de la table.
- [m5] Historique de conversation limité aux 20 derniers messages (`chat.py`) sans résumé — le coach « oublie » le début d'une longue conversation ; la mémoire `user_notes` compense partiellement.
- [m6] Duplicate route `/health` (main.py:141-144 et 161-163) — la seconde est morte.
- [m7] CORS `["*"]` (config.py / .env) — sans risque immédiat (API mobile) mais inutilement ouvert avec credentials.
- [m8] Tests : 4 fichiers iOS (alarme, calendrier, images) + 1 backend (orchestrator). Rien sur : energy score, tools, AIAction execute, EngagementTracker, insights (M1 aurait été attrapé).
- [m9] `Numeric` sans précision (db.py) et `checkin_date` en `DateTime(timezone=False)` comparé à des `date` — fonctionne par accident asyncpg.
- [m10] Fichiers parasites à la racine du repo : `ChatGPT Image *.png`, `build/`, `droplets`, `.App.js.swp`-like — hygiène.

## Observations positives (à préserver)
- 0 `try!` / `as!` / TODO dans 26 578 lignes Swift ; erreurs typées `AgentAPIError` ; actor pour l'API.
- Prompt système : vrais garde-fous médicaux (TCA, diabète, cardiaque), refus formatés, co-décision, format 2 phrases.
- Executor outils : timeout 10 s, audit `ToolExecution` en base, guardrails (modules valides, défis 7-90 j, disclaimer finance auto).
- Retry premier-lancement (`firstLaunchDone` seulement après succès), dedup d'appels d'outils identiques, `with_for_update(skip_locked=True)` sur le dispatch notifs.
- EngagementTracker au ton juste (« jamais culpabilisant »), ContextualNotifications = le pilier du spec le mieux exécuté.
