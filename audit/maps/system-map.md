# LifeOS — Carte système (audit 2026-07-02)

## Inventaire
| Élément | Localisation | Taille | État |
|---|---|---|---|
| App iOS (SwiftUI) | `LifeOS/` | 92 fichiers, 26 578 l. | Active, branche `jules` |
| Entry point | `LifeOSApp.swift` (254 l.) | schéma SwiftData ~50 entités | Wipe silencieux si migration échoue |
| Tabs | `Core/MainTabView.swift` (506 l.) | 4 écrans montés en permanence (opacity) | — |
| Onboarding | `Core/OnboardingView.swift` (1 556 l.) | 9 étapes, profils de vie, contexte hormonal | — |
| Accueil | `Core/ShortcutsHomeView.swift` (1 273 l.) | 18 raccourcis, energy badge, bilan hebdo | — |
| Assistant | `Shared/AIAssistantView.swift` (1 079 l.) | chat + 8 AIAction exécutées localement | Titre « Assistant IA » (violation spec) |
| Modules | `Modules/` (20 fichiers) | Crypto 1 262 l. (port RiskCrypto), Productivity 722, Nutrition 642… | — |
| Services | `Services/` (10 fichiers, 1 641 l.) | AgentAPI (actor), ContextualNotifications (25+ notifs), EngagementTracker, WeeklyModuleSuggester | Propres |
| Widgets / Live Activity | `LifeOSWidget/`, AlarmLiveActivity | réveil + habitudes (App Group) | — |
| Tests iOS | `LifeOSTests/` (4 fichiers) | Alarm, Calendar, ImageStore | Cœur non testé |
| Backend | `backend/app/` | 64 fichiers, ~5 000 l. | FastAPI + SQLAlchemy async + Mistral |
| Agent | `core/agents/orchestrator.py` (269 l.) | boucle 12 itérations max, dédup outils | Solide |
| Prompt système | `core/llm/prompts.py` (632 l.) | connaissance 17 modules, garde-fous santé, format 2 phrases | Fichiers AI/*.md absents du conteneur |
| Outils | `core/tools/` (23 outils) | executor avec timeout 10 s, audit ToolExecution, guardrails finance | Solide |
| DB | `models/db.py` (13 tables) | users, configs, goals, conversations, challenges, checkins, notifs | `create_all` au boot + SQL manuels |
| Tâches | `tasks/celery_app.py` | beat 5 min (push APNs) + daily 7h (habit analyzer) | **Jamais lancé en prod** |
| Déploiement | `railway.json` | `startCommand: uvicorn` uniquement | Ni worker ni beat |
| Tests backend | `tests/test_orchestrator.py` | 1 fichier | Couverture minimale |

## Flux de données
```
iOS ──X-API-Key + device_id──> FastAPI /api/v1/chat
        └─> get_or_create_user(device_id)  ← identité = device_id spoofable
        └─> AgentOrchestrator ──> Mistral (mistral-large-latest, 12 iter max)
                └─> 23 outils (goals, config, logs, challenges, mémoire user_notes)
                └─> actions (create_todo, add_module, schedule_reminder…) → exécutées LOCALEMENT sur iOS
iOS ──/energy/checkin──> score énergie calculé serveur (DailyCheckin)
iOS ──HealthKit──> pas, sommeil (HealthService/HealthRepository)
CryptoModule ──> worker Cloudflare RiskCrypto (Configuration.swift:42)
FoodSearch ──> OpenFoodFacts (public)
```

## Notifications — 3 systèmes parallèles
1. **Locales contextuelles** (`ContextualNotifications.swift`, 426 l.) : 25+ notifs conditionnées par modules actifs + réglages horaires. Fonctionne.
2. **Locales via actions agent** (`schedule_reminder` → UNNotification locale). Fonctionne si l'app reçoit la réponse.
3. **Push serveur APNs** (`ScheduledNotification` + Celery beat 5 min + `habit_analyzer` quotidien) : **chaîne morte en production** — railway.json ne lance que uvicorn. Les lignes s'accumulent en base, rien ne part.

## Identité & auth
- Une seule clé API partagée (`X-API-Key`) pour tous les clients — comparée à `settings.internal_api_key` (`dependencies.py`).
- Identité utilisateur = `device_id` fourni par le client (identifierForVendor) — aucun secret par utilisateur.
- `apns_token` remonté à chaque /chat (AgentAPI.swift:240) et stocké sur le User.

## Persistance
- **iOS** : SwiftData (~50 @Model), UserDefaults (config modules, notifs, engagement), App Group `group.lifeos.app` (widgets), SecureStore non utilisé pour la clé API (UserDefaults override possible via ServerConfigView).
- **Serveur** : PostgreSQL (Railway) — 13 tables, migrations SQL manuelles 001→004 **mais** `Base.metadata.create_all` au boot (main.py:94).

## Points forts constatés
- 0 `try!`/`as!`, 0 TODO, erreurs typées, actor AgentAPI propre, retry premier-lancement bien conçu.
- Prompt système riche : garde-fous médicaux/finance réels, format court imposé, co-décision.
- Executor outils : timeout, audit en base, guardrails (modules valides, durées défis 7-90 j, disclaimer finance).
- reduceMotion respecté, @Query avec #Predicate en init (perf), pilier « notifications contextuelles » du spec réellement implémenté.
