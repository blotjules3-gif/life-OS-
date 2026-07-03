# LifeOS — Audit moteur IA (2026-07-03)

Mission : audit complet de l'architecture LLM du coach, puis exécution des améliorations à plus fort impact.
Contrainte structurante : **Railway est deploy-blocked** (pas d'auth GitHub) — les fixes backend sont livrés « deploy-ready », les fixes iOS sont actifs dès le prochain build.

---

## Phase 1-2 — Carte d'architecture (FAITS)

### Chaîne d'une requête chat
```
iOS (2 surfaces)                       Backend FastAPI (Railway)                 LLM
─────────────────                      ─────────────────────────                 ───
AIAssistantView (coach général)   →    POST /api/v1/chat (X-API-Key)
ModuleChatView (config module)         ├─ verify_api_key
        │                              ├─ get_or_create_user(device_id)
AgentAPI.chat()                        ├─ résolution conversation (UUID)
├─ UserContextBuilder.build()          ├─ historique : SELECT 20 messages   →   AgentOrchestrator.run
│  (snapshot temps réel ≤2000 car.)    ├─ module_config si module           →   ├─ build_system_prompt (~57 KB)
├─ timeout chat 90 s                   ├─ persist user Message              →   ├─ get_tools_for_module (16-24 outils)
└─ OfflineCoach si URLError            └─ persist assistant Message         →   └─ boucle ≤12 itérations
                                                                                    └─ Mistral large, temp 0.3,
                                                                                       max_tokens 500, timeout 30 s,
                                                                                       3 retries transitoires,
                                                                                       PAS de streaming
```

### Couches mémoire (4)
| Couche | Source | Injection |
|---|---|---|
| Snapshot temps réel | `UserContextBuilder.swift` (iOS) | Automatique, chaque requête |
| Historique conversation | Postgres `messages` | Automatique, 20 messages |
| Mémoire long terme | `User.user_notes` (JSONB) via `remember_user_info` | **Uniquement si le LLM appelle `get_user_context`** |
| Insights comportementaux | `behavioral_insights.py` (30 j de DailyCheckin, max 4) | **Uniquement via `get_user_context`** |

### Composition du prompt système (par requête, par itération)
- `SYSTEM_PROMPT_BASE` : ~550 lignes (prompts.py:24-575)
- `PROBLEMES_SOLUTIONS.md` : 16,5 KB — `QUESTIONS_MODULES.md` : 18,8 KB — `INSTRUCTIONS_CUSTOM.md` : 2,2 KB
- Snapshot utilisateur + config module
- **Total ≈ 57 KB ≈ 14-15 k tokens**, relu du disque à chaque requête (`_load_ai_file`, prompts.py:12-17, aucun cache)
- - 24 définitions d'outils (definitions.py, 578 lignes) quand `module=None` (cas du coach général)

---

## Phase 3-5 — Constats (preuves fichier:ligne)

### P0-1 — L'historique charge les 20 plus ANCIENS messages
- **Problème** : `chat.py:59-64` — `.order_by(Message.created_at.asc()).limit(20)`.
- **Preuve** : FAIT, lu dans le code. Aggravé par `aiConversationID` jamais tourné côté iOS (AIAssistantView.swift:93, @AppStorage, remis à "" seulement sur 404).
- **Impact** : au-delà de 20 messages, le coach ne voit plus JAMAIS les échanges récents — il répond avec le contexte des premiers jours. C'est le défaut n°1 de « connexions » perçu par l'utilisateur.
- **Solution** : `desc().limit(20)` + `reversed()`. Effort : 2 lignes. Gain : mémoire de conversation réellement récente.

### P0-2 — La mémoire long terme n'est jamais injectée
- **Problème** : `user_notes` + insights ne parviennent au LLM que s'il décide d'appeler `get_user_context` (meta_tools.py:handle_get_user_context — seul chemin).
- **Impact** : soit la mémoire est ignorée, soit elle coûte une itération LLM complète (~2-4 s + ~15 k tokens re-envoyés).
- **Solution** : injecter `user_notes` (cap 20) + insights (max 4) directement dans le prompt système (chat.py → orchestrator → build_system_prompt). Effort : ~40 lignes. Gain : personnalisation systématique + suppression d'un aller-retour.

### P1-3 — 37,5 KB relus du disque à chaque requête
- **Problème** : `prompts.py:12-17` — `read_text` sans cache, 3 fichiers, à chaque `build_system_prompt`.
- **Solution** : cache mémoire avec invalidation mtime. Effort : 10 lignes. Gain : I/O éliminée, latence p50 réduite.

### P1-4 — Conversation serveur jamais tournée (iOS)
- **Problème** : AIAssistantView.swift:93 — l'ID vit pour toujours ; la conversation Postgres grossit sans borne et fige le bug P0-1.
- **Solution iOS (déployable SANS Railway)** : rotation quotidienne de `aiConversationID`. La mémoire long terme (user_notes, par user) survit à la rotation. Effort : ~8 lignes.

### P2-5 — Aucune télémétrie tokens
- `wrapper.py` ne logge pas `response.usage` → coût Mistral invisible. Solution : log structuré prompt/completion tokens. Effort : 5 lignes.

### P2-6 — `/health` dupliqué
- `main.py:141-144` et `:161-163` — le second écrase le premier. Nettoyage trivial.

### P2/P3 — Constats documentés, non implémentés ici
| Constat | Preuve | Reco |
|---|---|---|
| Pas de streaming — l'utilisateur attend la réponse complète | wrapper.py (complete_async), chat.py (JSON unique) | SSE `/chat/stream` (90 j) |
| Pire cas 12 itérations × 30 s = 360 s > timeout iOS 90 s | config.py (12, 30) vs Configuration.swift (chatTimeout 90) | Réduire à 6 itérations ou budget temps global |
| `module=None` → 24 outils envoyés | definitions.py:575-576 | Par design pour le coach général — assumé, à réévaluer si coût |
| `Message.tool_call/tool_result` colonnes jamais remplies par le flux | db.py vs chat.py | Persister les tool calls (debug) |
| Prompt ~15 k tokens × N itérations, pas de prompt caching Mistral | mesure wc -c | Compresser QUESTIONS_MODULES (chargement par module) — 90 j |
| `create_all` sans Alembic | main.py startup | Dette connue (registre) |

### Phase 4 — Innovation (jugées à valeur mesurable)
- **Mémoire hiérarchique consolidée** : résumer les conversations closes dans `user_notes` (batch nocturne) — dépend du beat Celery (bloqué Railway).
- **Proactivité** : `schedule_followup` existe déjà ; le vrai levier est le beat, pas le code.
- **Knowledge graph** : rejeté — aucune valeur mesurable au volume actuel de données vs coût.

---

## Phase 6 — Plan d'action

| Prio | Action | Où | Déployable |
|---|---|---|---|
| P0 | Fix historique (20 récents) | chat.py | deploy-ready |
| P0 | Injection mémoire long terme + insights dans le prompt | chat.py, orchestrator.py, prompts.py | deploy-ready |
| P1 | Cache mtime des fichiers AI/*.md | prompts.py | deploy-ready |
| P1 | Rotation quotidienne de conversation | AIAssistantView.swift | **build iOS immédiat** |
| P2 | Log usage tokens | wrapper.py | deploy-ready |
| P2 | /health dédupliqué | main.py | deploy-ready |
| 30 j | Itérations 12→6, persist tool calls, purge conversations | config, chat.py | après déploiement |
| 90 j | Streaming SSE, chargement des .md par module, consolidation mémoire nocturne | backend | après déploiement |

## Phase 7-8 — Exécution & validation
Voir registers.md (ligne F13) : implémentation + tests + résultats avant/après.
