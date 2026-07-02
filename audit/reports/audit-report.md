# LifeOS — Rapport d'audit (2026-07-02)

## Scores par dimension
| Dimension | /10 | Justification |
|---|---|---|
| Architecture & code | 7 | Couches propres (actor API, orchestrator stateless, executor avec audit), erreurs typées, 0 force unwrap sauf 1. Mais double vérité schéma DB, mismatch sport/fitness, chemin AI/ fragile. |
| Polish UI | 7 | ConcentricRectangle, stagger, contentTransition numericText, reduceMotion respecté. Tailles fixes sans Dynamic Type. |
| UX & navigation | 6 | 4 tabs clairs, onboarding riche. Mais chat pris en otage par un ping réseau, permission notifs sans contexte, écran de config serveur exposé en prod. |
| Performance | 6 | @Query avec predicates en init, LazyVStack. Mais 4 écrans montés en permanence avec toutes leurs @Query actives (MainTabView ZStack opacity). |
| Cohérence visuelle | 6 | Theme.card/bg/radius suivis ; des dizaines de Color(hex:) répétées inline au lieu de tokens nommés. |
| Erreurs & états | 5 | Retry premier-lancement exemplaire, AgentAPIError typé. Mais wipe silencieux du store, crash URL!, insights qui crash, retry LLM sur toute exception. |
| Dette technique | 5 | God files 1 300-1 500 l. (Onboarding, Profile, Home, Crypto), 5 fichiers de tests pour 31 500 lignes, migrations à deux vérités. |
| Produit / promesse | 4 | Sur les piliers du spec : notifs contextuelles ✓ (excellent), energy score ✓, mémoire user_notes ✓ ; insights ✗ (crash M1), coach proactif ✗ (Celery jamais lancé B4), interdiction « IA » ✗ (7 violations M4), prompt amputé en prod (M2). |
| Accessibilité | 2 | 8 accessibilityLabel dans toute l'app, zéro Dynamic Type. |
| Sécurité & données | 1 | Secrets prod + PAT GitHub publiés dans le repo, identité spoofable par device_id, store local effaçable sans consentement, LLM qui écrit des UserDefaults arbitraires. |

## Verdict (3 phrases)
LifeOS est le squelette bien architecturé d'un excellent produit — le prompt coach, l'executor d'outils et les notifications contextuelles sont d'un niveau rare pour un projet à deux — mais son cœur promis (coach proactif, insights comportementaux) est mort en production sans que personne ne le voie : Celery ne tourne pas, les insights crashent, le prompt est amputé de ses fichiers. La sécurité est indéfendable : les clés de prod, la clé Mistral et un PAT GitHub sont publiés dans l'historique git, et n'importe qui peut lire les conversations santé d'un utilisateur avec son seul device_id. Tant que B1-B4 ne sont pas réglés, chaque nouvel utilisateur est un risque juridique et chaque feature est construite sur un backend qui ne fait pas ce que le code croit faire.

## Réponses Phase 2 (reconstruction produit)
- **Pourquoi installer ?** Un compagnon de vie unique (17 modules : sommeil, sport, cycle, finances, médical) avec un vrai coach conversationnel qui configure l'app pour toi. Différenciation réelle vs Habit trackers.
- **Pourquoi revenir chaque jour ?** Energy score matinal, briefing du jour, habitudes, réveil intégré, notifs contextuelles. La boucle existe et elle est bonne — quand les notifs sont acceptées (cf. M6).
- **Pourquoi rester ?** La mémoire (user_notes + insights) devrait rendre le coach plus pertinent chaque semaine — c'est le pilier « jumeau comportemental », aujourd'hui cassé (M1, B4). C'est LA rétention long terme et elle ne fonctionne pas.
- **Pourquoi payer ?** Rien n'est monétisé ni monétisable actuellement ; le coût Mistral par utilisateur est réel dès aujourd'hui (facturation sans revenu, aggravé par le retry M10).
- **Pourquoi recommander ?** Aucune boucle virale ; le partage n'existe nulle part.
