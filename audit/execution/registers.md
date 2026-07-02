# LifeOS — Registres (audit 2026-07-02)

## Journal de décisions
| Date | Décision | Statut |
|---|---|---|
| 2026-07-02 | Cible d'audit corrigée : LifeOS (pas RiskCrypto) | Fait |
| 2026-07-02 | Artefacts dans `LifeOS-associe/audit/` | Fait |
| 2026-07-02 | B1 : rotation + untrack **sans réécriture d'historique** (choix Jules — zéro impact associé) | Fait (côté code) |
| 2026-07-02 | Ordre Phase 10 : **sécurité d'abord** (choix Jules) | Fait |

## Journal d'exécution Phase 10 (2026-07-02)
| Item | Action | État |
|---|---|---|
| B1 | `backend/.env` untracké, PAT retiré de l'URL du remote, fallback clé prod supprimé de Configuration.swift:32 | Fait — **rotation des clés à faire par Jules (dashboards)** |
| M1 | `behavioral_insights.py:43` : comparaison datetime/str remplacée par `_days_ago` + 3 tests | Fait, tests verts |
| M2 | `AI/` déplacé dans `backend/AI/` (contexte Docker), chemin `prompts.py` ajusté, chargement vérifié | Fait |
| M3 | `habit_analyzer` : clé `sport` → `fitness` (config, template, deep link) | Fait |
| M10 | Retry LLM restreint aux erreurs transitoires (timeout, réseau, 429, 5xx, validation) | Fait |
| B4 prep | Notifications > 24 h de retard expirées au lieu d'être envoyées (anti-backlog au 1er beat) | Fait — **services Railway à créer par Jules** |
| Dette | `.venv` (7 432 fichiers) + `__pycache__` (2 977) désindexés, .gitignore complété | Fait |
| Tests | `test_orchestrator.py` réparé (FakeSettings, user_gender) — 8/8 verts | Fait |
| Push | `git push origin jules` échoue : plus de credentials après retrait du PAT | **En attente Jules (auth GitHub)** |

## Journal d'hypothèses
| Hypothèse | Confiance | Test |
|---|---|---|
| Celery worker/beat ne tournent pas sur Railway (pas de service séparé) | 90 % | Vérifier le dashboard Railway (2 services ?) — seule railway.json fait foi côté repo |
| Le repo GitHub est privé (limite l'exposition B1, ne l'annule pas) | 60 % | `gh repo view jules175/B-compagny-` |
| Le pré-prompt notifs contextuel double l'opt-in | 80 % | Mesurable après ajout d'un event minimal |
| Les users prod ont ≥ 6 check-ins → M1 crash déjà en prod | 70 % | Logs Railway : chercher TypeError behavioral_insights |
| L'associé (branche pote) n'a pas de travail en cours qui conflicte avec les fixes | 50 % | `git fetch && git log origin/pote` avant tout commit |

## Registre de risques
| Risque | Prob. | Impact | Mitigation |
|---|---|---|---|
| Exploitation des clés leakées (Mistral = facturation) | Moyenne | Critique | B1 immédiat : rotation avant tout le reste |
| Wipe du store à la prochaine évolution de schéma (50 entités, commits auto 15 min) | Élevée | Critique | B3 : backup avant migration |
| Purge d'historique git casse le workflow de l'associé | Élevée | Moyen | Coordonner avec lui ; a minima rotation + untrack sans réécriture |
| create_all vs .sql : drift de schéma au prochain ALTER | Élevée | Élevé | M11 Alembic |
| Lancer le beat (B4) déclenche un backlog de notifs accumulées | Moyenne | Moyen | Purger les `ScheduledNotification` périmées avant activation |
| Rejet App Store — accessibilité / permission notifs au launch | Faible-Moyenne | Moyen | M6, M12 |

## Registre de dette technique
1. Migrations à deux vérités (create_all + SQL manuels) — Alembic.
2. God files : OnboardingView 1 556 l., ProfileView 1 325 l., ShortcutsHomeView 1 273 l., CryptoModule 1 262 l.
3. Tests : 5 fichiers pour ~31 500 lignes ; zéro test sur energy, actions, insights.
4. Color(hex:) inline répétées au lieu de tokens Theme.
5. `ScheduledNotification` sans purge ; historique chat tronqué à 20 messages sans résumé.
6. Copy sans accents (onboarding, motivations) + emojis contraires à la règle projet.
7. Fichiers parasites à la racine (`ChatGPT Image *.png`, `build/`, `droplets`).
