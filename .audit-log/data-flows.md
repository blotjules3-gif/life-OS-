# Cartographie des flux de données LifeOS

Date : 2026-07-13
But : donner à Jules + son associé les faits exhaustifs pour trancher A/B/C (voir plan d'action privacy).

## 1. Vue d'ensemble

L'iPhone envoie des données à un backend FastAPI sur Railway. Le backend relaie certaines de ces données à Mistral (LLM) et persiste tout dans un Postgres.

```
iPhone ── HTTPS ── Railway (FastAPI + Postgres) ── HTTPS ── Mistral SAS (Paris, FR)
```

## 2. Endpoints AgentAPI (17 call sites)

### 2.1 Conversationnel — envoie `user_context` (données personnelles)

| Endpoint | Fichier client | Contenu envoyé |
|----------|----------------|----------------|
| `POST /api/v1/chat` | AIAssistantView × 3, ModuleChatView × 1, DailyBriefingView × 2, ShortcutsHomeView × 1 | message + user_context complet + device_id + apns_token |
| `POST /api/v1/chat/stream` | AIAssistantView × 1 | idem, streamé SSE |
| `POST /api/v1/chat/report` | CoachReportAlerts × 1 | message signalé + reason + device_id + conversation_id |

**Total : 9 call sites conversationnels.**

### 2.2 Métadata — lecture seule (device_id uniquement)

| Endpoint | Fichier client | Contenu envoyé |
|----------|----------------|----------------|
| `GET /api/v1/goals` | DailyBriefingView | device_id |
| `GET /api/v1/challenges` | DailyBriefingView, AIAssistantView | device_id |
| `GET /api/v1/energy/insights` | DailyBriefingView | device_id |
| `GET /api/v1/energy/score` | ProfileView | device_id |
| `GET /api/v1/config` | RemoteConfig | (rien) |

### 2.3 Mesures loguées — envoie état santé du jour

| Endpoint | Fichier client | Contenu envoyé |
|----------|----------------|----------------|
| `POST /api/v1/energy/checkin` | SleepCheckSheet, DailyBriefingView | sleep_quality, sleep_hours, mood, fatigue, water_ml, habits_done/total, sport_minutes + device_id |

## 3. Contenu détaillé de `user_context`

Généré par `UserContextBuilder.build()` (Services/UserContextBuilder.swift), envoyé à chaque message chat, taille max 19 500 caractères.

### 3.1 Toujours inclus si renseignés
- Date/heure locale
- Prénom (userName)
- Genre (userGender)
- Profil de vie (lifeProfile — étudiant/salarié/…)
- Modules actifs (activeModules — CSV)

### 3.2 Si utilisatrice a un cycle
- Phase du cycle (menstruelle/folliculaire/ovulation/lutéale)
- Jour du cycle + jours avant les règles
- Fenêtre ovulation (booléen)
- Fenêtre SPM (booléen)

### 3.3 Progression du jour
- Kcal / objectif kcal
- Protéines g / objectif
- Eau ml / objectif
- Habitudes faites / restantes (noms des 6 premières)
- Streak moyen d'habitudes
- Score d'énergie
- Sommeil : durée, qualité, dernière nuit

### 3.4 Profil sportif
- Poids kg
- Taille cm
- Niveau muscu (débutant/intermédiaire/avancé)
- Bench / Squat / Deadlift 1RM
- Années d'entraînement
- Fréquence hebdo cible
- Ratios force/poids

### 3.5 Engagement app
- Jours consécutifs
- Jours actifs cumulés

### 3.6 Sport récent (7 derniers jours)
- Résumé fitness
- Exos travaillés
- PR récents

### 3.7 Bloc expertise coach ciblé
- Un ou plusieurs blocs parmi : workout, nutrition, sleep, mind, productivity, cycle, longevity, looks, cardio, learning
- Sélectionnés par matching sur le message utilisateur
- Contenu = règles + citations scientifiques (Auteur Année)

## 4. Persistance côté Railway (Postgres)

Tables déclarées dans `backend/app/models/db.py` :

| Table | Contenu | Contient des données perso ? |
|-------|---------|------------------------------|
| `users` | device_id, name, gender, apns_token, user_notes (mémoire long terme), timestamps | **OUI** |
| `module_configs` | config par module (JSONB) | Oui (préférences) |
| `goals` | title, description, target, current, priority, dates | Oui |
| `conversations` | title (=1ers chars du 1er message) | Oui (contenu conversation) |
| `messages` | role, content de chaque message user + assistant | **OUI (échanges bruts)** |
| `tool_executions` | outils appelés par l'agent | Metadata |
| `sport_logs` | séances loguées | Oui |
| `nutrition_logs` | repas logués | Oui |
| `mobility_logs` | trajets | Oui |
| `finance_logs` | opé financières | **OUI (finance)** |
| `life_challenges` | challenges en cours | Oui |
| `daily_checkins` | sleep, mood, fatigue, water, habits, sport par jour | **OUI (santé)** |
| `scheduled_notifications` | push à envoyer | Metadata |
| `habit_snapshots` | snapshots habitudes | Oui |

**14 tables, la majorité contient des données personnelles ou de santé.**

Rétention : aucune limite définie côté serveur — les données persistent jusqu'à suppression manuelle. **Aucun endpoint DELETE user existant**.

## 5. Sous-traitant LLM

- **Provider** : Mistral AI (mistralai==1.1.0)
- **Modèle** : `mistral-large-latest`
- **Endpoint** : SDK officiel `mistralai.Mistral(api_key=...).chat.complete_async` — appel vers api.mistral.ai
- **Contenu envoyé à Mistral** : le prompt système + user_context + historique conversation (20 derniers messages) + message courant
- **Localisation** : Mistral SAS, siège Paris, hébergement UE — RGPD-compliant sur le papier
- **DPA** : à vérifier / signer si option A retenue
- **Rétention Mistral** : selon leur T&C — par défaut ils n'entraînent pas sur les API prompts, mais à confirmer

## 6. Sous-traitant hosting

- **Provider** : Railway (railway.app)
- **Localisation** : US/EU au choix, actuellement pas vérifié quelle région
- **Postgres** : hébergé chez Railway
- **DPA** : à vérifier

## 7. Ce que dit la privacy actuelle (`docs/privacy.html`)

- L.50 : « Pas de compte, pas de serveur, pas de publicité, pas de trackers. Tout ce que vous saisissez reste stocké localement sur votre iPhone »
- L.56 : « LifeOS fonctionne entièrement hors ligne et sur votre appareil. Nous n'exploitons aucun serveur applicatif et n'avons techniquement aucun accès à vos données »
- L.61 : « Vos données sont stockées localement via SwiftData »

**Contradiction totale avec les 14 tables + 9 endpoints conversationnels ci-dessus.**

## 8. Récapitulatif décisionnel

| Option | Backend Railway | LLM | Privacy à réécrire | Effort |
|--------|-----------------|-----|--------------------|--------|
| A — Assumer le cloud | Reste | Mistral | Oui, disclosure complet | ~2 sem + juridique |
| B — 100% local rule-based | À éteindre | `LocalCoach` (règles) | Non | ~2 j |
| C — 100% local LLM | À éteindre | Apple Intelligence (iOS 26+) + fallback `LocalCoach` | Non | ~1 sem |

Recommandation d'audit : **C** (garde le pitch marketing "100% local", garde la qualité LLM sur devices récents, coût OpEx zéro, RGPD hors sujet).

## 9. Ce qui doit être décidé

À trancher par Jules + associé avant Phase 2 :

1. **Option A, B ou C ?**
2. Si B ou C : que faire des données actuellement en Postgres Railway ? (probable : dump + purge)
3. Si C : accepter la contrainte iOS 26+ pour la fonction coach LLM (fallback règles sur < iOS 26) ?
4. Si A : budget juridique pour DPA Mistral + Railway + rewrite privacy par un juriste ?
