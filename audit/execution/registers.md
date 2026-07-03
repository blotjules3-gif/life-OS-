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
| B3 | Migration échouée : store déplacé en backup horodaté (jamais supprimé) + alerte « Données réinitialisées » | Fait |
| M4 | 9 mentions « IA » purgées (ProfileView, ShortcutsHomeView, AIAssistantView, CareerModule) → « ton coach » | Fait |
| M5 | Le chat s'ouvre sans ping serveur (isCheckingAI/offlineToast supprimés, bandeau offline interne suffit) | Fait |
| M6 | Fausse notif « +5 s » supprimée ; pré-prompt contextuel après création des habitudes (alerte Activer/Plus tard) ; plus de demande de permission au premier launch | Fait |
| M7 | `updateConfig` : allowlist stricte de 18 clés objectifs — dev.apiBaseURL/dev.apiKey inaccessibles au serveur | Fait |
| M8 | `Configuration.baseURL` : force unwrap remplacé par fallback prod | Fait |
| M9 | `ServerConfigView` + ses 3 points d'entrée derrière `#if DEBUG` ; en release les boutons relancent un ping | Fait |
| Push | `git push origin jules` échoue : plus de credentials après retrait du PAT | **En attente Jules (auth GitHub)** |
| F1 | Bilan hebdo partageable : `WeeklyShareCard` (360×640, couleurs fixes) + ImageRenderer scale 3 + ShareLink dans WeeklyBilanView | Fait |
| F2 | Sync Apple Santé silencieuse : `HealthAutoSync.swift` (sommeil + poids au retour premier plan), `sleepHoursLastNight`/`latestBodyMass` dans HealthService, flag `healthAuthRequested`, dédup poids, priorité check-in manuel | Fait |
| F3 | Coach hors-ligne : `OfflineCoach.swift` (réponses depuis SwiftData — habitudes, eau, kcal, sommeil, streaks) branché dans le catch offline de `send()` (4 codes URLError) | Fait |
| Skills | 4 skills créés dans `~/.claude/skills/` : swiftui-lifeos, swiftui-share-image, healthkit-silent-sync, swiftdata-safe-store — enregistrés dans la table CLAUDE.md | Fait |
| F4 | Verrou Face ID/Touch ID opt-in : `AppLock.swift` (activation vérifiée par auth, verrou au passage en arrière-plan + au launch, écran opaque zIndex 10), ligne réglage dans ProfileView, `NSFaceIDUsageDescription` | Fait — build vert |
| F5 | Export JSON local : `DataExporter.swift` (19 entités mappées à la main, dates ISO 8601) + `DataExportSheet` (compteur par section, ShareLink) + ligne « Exporter mes données » | Fait — build vert |
| F6 | Siri/Raccourcis : `LocalStore.swift` (schéma extrait de LifeOSApp, container partagé app/intents) + `LifeOSIntents.swift` (LogWaterIntent, CompleteHabitIntent + HabitEntity, phrases FR) | Fait — build vert |
| F7 | Graphe de tendance (Swift Charts) dans VitalsView : ligne + aire, delta coloré (baisse de poids = vert), min/max, 30 dernières mesures — tous types de mesures | Fait — build vert |
| F8 | Audit CloudKit : **non activable en l'état** — 45 modèles sans défauts inline, 4 relations non optionnelles, capability iCloud manquante → `audit/execution/cloudkit-audit.md` | Fait (rapport) |
| F9 | Passe fluidité (2026-07-03) : `.staggered()`/`.scrollFade()` dans Theme, transitions d'onglets fondu+zoom 0.97 (MainTabView), ProgressRing spring + remplissage à l'apparition, chiffres `numericText`+monospaced (MetricRing, goalBar, objectiveRow, score hebdo), coches `symbolEffect(.replace)`, cascade d'entrée accueil 6 sections — reduceMotion respecté partout | Fait — build vert |
| Bloqué | Apple Watch (nouveau target = Xcode GUI) ; défis entre amis (backend Railway inaccessible) ; capability iCloud (Xcode GUI) | En attente Jules |

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
