# LifeOS — Roadmap (2026-07-02)

Priorisation : Impact × Confiance ÷ Effort.

## 30 jours — colmater la coque
| # | Initiative | Impact | Effort | ROI |
|---|---|---|---|---|
| 1 | **B1** : rotation Mistral + INTERNAL_API_KEY + SECRET_KEY + révocation PAT, untrack `backend/.env`, purge historique git, remote sans PAT, supprimer le fallback Configuration.swift:32 | Sécurité existentielle | 0,5-1 j | ★★★★★ |
| 2 | **B4** : lancer worker + beat sur Railway (2 services, même image) → le coach proactif prend vie | Cœur produit | 0,5 j | ★★★★★ |
| 3 | **M1** : fix comparaison datetime behavioral_insights.py:43 + test | Insights réparés | 15 min | ★★★★★ |
| 4 | **M2** : COPY AI/ dans l'image Docker (ou déplacer dans backend/app/ai/) | Coach prod = coach testé | 30 min | ★★★★★ |
| 5 | **B3** : remplacer le wipe silencieux par backup du store + alerte utilisateur | Confiance données | 0,5 j | ★★★★ |
| 6 | **M4** : purger le mot « IA » des 7 emplacements (renommer « Ton coach ») | Positionnement spec | 1 h | ★★★★ |
| 7 | **M6** : pré-prompt notifs contextuel (après création de la 1re habitude, pas au welcome) + supprimer la notif aveugle +5 s | Opt-in ×1,7 | 0,5 j | ★★★★ |
| 8 | **M5** : ouvrir le chat sans ping (historique local toujours accessible, bandeau offline) | Friction quotidienne | 1 h | ★★★★ |
| 9 | **M8/M7** : garde URL non-force-unwrap + allowlist de clés updateConfig | Crash-loop + intégrité | 1 h | ★★★ |
| 10 | **M3/M10** : fitness au lieu de sport ; retry LLM sur erreurs transitoires uniquement | Correctifs backend | 1 h | ★★★ |

## 90 jours — tenir la promesse « jumeau »
- **B2** : vraie identité par appareil — secret généré à l'install (Keychain), enregistré une fois, signé par requête. Migration douce des users existants.
- **M11** : Alembic — une seule vérité de schéma, migrations auto au deploy.
- **M9** : ServerConfigView derrière `#if DEBUG`.
- Insights v2 : une fois M1 fixé et le beat vivant, brancher les insights dans le briefing du matin (le pilier différenciant, enfin réel).
- Purge `ScheduledNotification` envoyées > 30 j (tâche beat).
- Tests : energy score, execute(action:), EngagementTracker, insights — les 4 zones où un bug est resté invisible.
- **M12** : passe accessibilité sur les 20 contrôles principaux.

## 180 jours — rétention et différenciation
- Historique energy score → graphes de tendance + corrélations affichées (les données `DailyCheckin` existent déjà).
- Détection de désengagement croisée serveur (EngagementTracker remonte au backend → le coach relance par push, maintenant vivant).
- Partage : carte hebdo « bilan de semaine » exportable en image — première boucle virale.
- Résumé de conversation côté serveur pour dépasser la fenêtre des 20 messages.

## 365 jours — plateforme
- Monétisation : coach illimité + insights avancés en abonnement (le coût Mistral par utilisateur l'exige de toute façon).
- Multi-device (l'identité B2 propre le permet), export de données (RGPD).
- Découper les God files (Onboarding 1 556 l., Profile 1 325 l.) au rythme des features, pas avant.
