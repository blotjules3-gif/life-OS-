# Questions de configuration — Modules LifeOS
# Adapte les notifications à la vraie vie de l'utilisateur

Ce fichier définit, pour chaque module, les questions précises à poser
et les clés UserDefaults qu'elles renseignent pour piloter les notifications.

---

## RÈGLE GÉNÉRALE

Ne jamais envoyer de notification pour un module non actif.
Ne jamais utiliser d'heure hardcodée — toujours lire les clés ci-dessous.
Si une clé est absente (= question jamais posée), ne pas envoyer la notif correspondante.

---

## MODULE : SOMMEIL (sleep)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "À quelle heure tu te lèves normalement ?" | `wakeupHour` / `wakeupMinute` | Int | Pas de notif matin |
| "À quelle heure tu veux te coucher ?" | `bedHour` / `bedMinute` | Int | Pas de notif coucher |
| "Combien d'heures de sommeil tu vises ?" | `sleep_target_hours` | Int | 8 |
| "Tu veux qu'on te rappelle d'aller te coucher ?" | `notif_sleep_bedtime_enabled` | Bool | false |
| "Tu veux un bilan le matin après ton réveil ?" | `notif_sleep_morning_enabled` | Bool | false |

**Notifications déclenchées :**
- `sleep_bedtime` → `bedHour:bedMinute - 30min` (si `notif_sleep_bedtime_enabled`)
- `sleep_morning` → `wakeupHour:wakeupMinute + 20min` (si `notif_sleep_morning_enabled`)

---

## MODULE : FITNESS (fitness)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu t'entraînes plutôt le matin, midi ou le soir ?" | `fitness_timing` | String (morning/noon/evening) | Pas de notif |
| "À quelle heure exactement ?" | `sportHour` | Int | Pas de notif |
| "Quels jours de la semaine ?" (multiple) | `fitness_days` | String ("1,3,5") | Pas de notif |
| "Tu veux un rappel avant ta séance ?" | `notif_fitness_enabled` | Bool | false |
| "Combien de minutes avant ?" | `notif_fitness_advance_min` | Int | 15 |

**Notifications déclenchées :**
- `fitness_reminder` → `sportHour:00 - notif_fitness_advance_min` les jours dans `fitness_days` uniquement

---

## MODULE : NUTRITION (nutrition)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "À quelle heure tu prends ton petit-déjeuner ?" | `nutrition_breakfast_hour` | Int | Pas de notif |
| "À quelle heure tu manges le midi ?" | `nutrition_lunch_hour` | Int | Pas de notif |
| "À quelle heure tu dînes ?" | `nutrition_dinner_hour` | Int | Pas de notif |
| "Tu pratiques le jeûne intermittent ?" | `nutrition_fasting_enabled` | Bool | false |
| "Tu veux noter tes repas pour suivre tes calories ?" | `notif_nutrition_log_enabled` | Bool | false |
| "À quelle heure du soir tu veux faire le point ?" | `notif_nutrition_review_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `nutrition_breakfast` → `nutrition_breakfast_hour:00 - 10min` (si `notif_nutrition_log_enabled`)
- `nutrition_lunch` → `nutrition_lunch_hour:00 - 10min` (si `notif_nutrition_log_enabled`)
- `nutrition_dinner` → `nutrition_dinner_hour:00 - 10min` (si `notif_nutrition_log_enabled`)
- `nutrition_review` → `notif_nutrition_review_hour:00` (si `notif_nutrition_log_enabled`)

> Règle : si `nutrition_fasting_enabled` = true, supprimer `nutrition_breakfast`

---

## MODULE : MENTAL / BIEN-ÊTRE (mind)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu préfères méditer/te recentrer le matin ou le soir ?" | `mind_session_timing` | String (morning/evening) | Pas de notif |
| "À quelle heure ?" | `mind_session_hour` | Int | Pas de notif |
| "Tu as des moments de stress récurrents dans ta journée ?" | `mind_stress_time` | String (morning/noon/afternoon/evening) | Pas de notif |
| "Tu veux un check-in humeur quotidien ?" | `notif_mind_mood_enabled` | Bool | false |
| "À quelle heure tu veux faire ton check-in humeur ?" | `mind_mood_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `mind_session` → `mind_session_hour:00` (si défini)
- `mind_mood` → `mind_mood_hour:00` (si `notif_mind_mood_enabled`)
- `mind_stress` → heure correspondant à `mind_stress_time` (si défini) — 12h=noon, 17h=afternoon...

---

## MODULE : PRODUCTIVITÉ (productivity)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "À quelle heure tu commences ta journée de travail ?" | `productivity_start_hour` | Int | Pas de notif |
| "Tu veux un point sur tes priorités en début de journée ?" | `notif_productivity_morning_enabled` | Bool | false |
| "Tu veux un bilan de tes todos en fin de journée ?" | `notif_productivity_evening_enabled` | Bool | false |
| "À quelle heure tu termines ta journée ?" | `productivity_end_hour` | Int | Pas de notif |
| "Tu veux un rappel pour tes habitudes quotidiennes ?" | `notif_habits_enabled` | Bool | false |
| "À quelle heure tu veux qu'on te rappelle tes habitudes ?" | `notif_habits_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `productivity_morning` → `productivity_start_hour:00 + 5min` (si `notif_productivity_morning_enabled`)
- `productivity_evening` → `productivity_end_hour:00` (si `notif_productivity_evening_enabled`)
- `habits_reminder` → `notif_habits_hour:00` (si `notif_habits_enabled`)

---

## MODULE : FINANCES (finance)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Quel jour du mois tu reçois ton salaire ?" | `finance_salary_day` | Int (1-31) | Pas de notif |
| "Tu veux un rappel mensuel pour faire ton bilan budget ?" | `notif_finance_monthly_enabled` | Bool | false |
| "Tu veux un rappel hebdomadaire pour noter tes dépenses ?" | `notif_finance_weekly_enabled` | Bool | false |
| "Quel jour de la semaine ?" | `finance_review_weekday` | Int (1=lun, 7=dim) | Pas de notif |
| "À quelle heure ?" | `finance_review_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `finance_salary` → le `finance_salary_day` de chaque mois à 9h00 (si `notif_finance_monthly_enabled`)
- `finance_weekly` → chaque `finance_review_weekday` à `finance_review_hour` (si `notif_finance_weekly_enabled`)

---

## MODULE : INVESTISSEMENT (invest)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux un rappel pour tes investissements réguliers (DCA) ?" | `notif_invest_dca_enabled` | Bool | false |
| "Quel jour du mois ?" | `invest_dca_day` | Int (1-31) | Pas de notif |
| "Tu veux suivre l'évolution de ton portfolio chaque semaine ?" | `notif_invest_weekly_enabled` | Bool | false |
| "Quel jour ?" | `invest_review_weekday` | Int | Pas de notif |
| "À quelle heure ?" | `invest_review_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `invest_dca` → le `invest_dca_day` à 9h00 (si `notif_invest_dca_enabled`)
- `invest_weekly` → chaque `invest_review_weekday` à `invest_review_hour` (si `notif_invest_weekly_enabled`)

---

## MODULE : CARRIÈRE (career)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu es en recherche d'emploi active ?" | `career_job_searching` | Bool | false |
| "Combien de candidatures par semaine tu vises ?" | `career_applications_target` | Int | 0 |
| "Tu veux un rappel hebdomadaire pour tes candidatures ?" | `notif_career_weekly_enabled` | Bool | false |
| "Quel jour ?" | `career_review_weekday` | Int | Pas de notif |
| "Tu veux un rappel pour les relances (J+7) ?" | `notif_career_followup_enabled` | Bool | false |

**Notifications déclenchées :**
- `career_weekly` → chaque `career_review_weekday` à 9h00 (si `notif_career_weekly_enabled` && `career_job_searching`)

---

## MODULE : APPRENTISSAGE (learning)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux te former combien de minutes par jour ?" | `learning_daily_min` | Int | 0 |
| "Tu préfères apprendre le matin ou le soir ?" | `learning_timing` | String (morning/evening) | Pas de notif |
| "À quelle heure ?" | `learning_session_hour` | Int | Pas de notif |
| "Tu veux un rappel quotidien pour ta session d'apprentissage ?" | `notif_learning_enabled` | Bool | false |

**Notifications déclenchées :**
- `learning_daily` → `learning_session_hour:00` (si `notif_learning_enabled`)

---

## MODULE : CYCLE MENSTRUEL (cycle)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux être prévenue avant tes règles ?" | `notif_cycle_pms_enabled` | Bool | false |
| "Combien de jours avant tu veux être prévenue ?" | `cycle_pms_advance_days` | Int | 3 |
| "Tu veux un rappel pour tracker ton cycle chaque jour ?" | `notif_cycle_daily_enabled` | Bool | false |
| "À quelle heure ?" | `cycle_track_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `cycle_daily` → `cycle_track_hour:00` (si `notif_cycle_daily_enabled`)
- `cycle_pms` → J-`cycle_pms_advance_days` avant les règles prévues (si `notif_cycle_pms_enabled`)

---

## MODULE : MAISON (home)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux un rappel hebdomadaire pour le ménage ?" | `notif_home_cleaning_enabled` | Bool | false |
| "Quel jour ?" | `home_cleaning_weekday` | Int | Pas de notif |
| "À quelle heure ?" | `home_cleaning_hour` | Int | Pas de notif |
| "Tu veux un rappel pour les courses ?" | `notif_home_groceries_enabled` | Bool | false |
| "Quel jour tu fais tes courses ?" | `home_groceries_weekday` | Int | Pas de notif |

**Notifications déclenchées :**
- `home_cleaning` → chaque `home_cleaning_weekday` à `home_cleaning_hour` (si `notif_home_cleaning_enabled`)
- `home_groceries` → chaque `home_groceries_weekday` à 10h00 (si `notif_home_groceries_enabled`)

---

## MODULE : ADMIN (admin)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux être rappelé pour tes démarches admin ?" | `notif_admin_enabled` | Bool | false |
| "Quel jour de la semaine pour ton session admin ?" | `admin_session_weekday` | Int | Pas de notif |
| "À quelle heure ?" | `admin_session_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `admin_session` → chaque `admin_session_weekday` à `admin_session_hour` (si `notif_admin_enabled`)

---

## MODULE : CORPS / LOOKSMAXX (looks)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu as une routine beauté/soin le matin ?" | `looks_has_morning_routine` | Bool | false |
| "À quelle heure tu veux qu'on te rappelle ?" | `looks_morning_hour` | Int | Pas de notif |
| "Tu as une routine soin le soir ?" | `looks_has_evening_routine` | Bool | false |
| "À quelle heure ?" | `looks_evening_hour` | Int | Pas de notif |

**Notifications déclenchées :**
- `looks_morning` → `looks_morning_hour:00` (si `looks_has_morning_routine` && défini)
- `looks_evening` → `looks_evening_hour:00` (si `looks_has_evening_routine` && défini)

---

## MODULE : SOCIAL (social)

| Question | Clé UserDefaults | Type | Défaut si absent |
|---|---|---|---|
| "Tu veux qu'on te rappelle de garder contact avec ton réseau ?" | `notif_social_enabled` | Bool | false |
| "Combien de fois par semaine ?" | `social_contact_frequency` | Int (1-7) | 1 |
| "Quel jour de la semaine ?" | `social_contact_weekday` | Int | Pas de notif |

**Notifications déclenchées :**
- `social_reminder` → chaque `social_contact_weekday` à 18h00 (si `notif_social_enabled`)

---

## RÉSUMÉ — Toutes les clés UserDefaults de notifications

```
notif_sleep_bedtime_enabled     Bool
notif_sleep_morning_enabled     Bool
notif_fitness_enabled           Bool
notif_fitness_advance_min       Int   (défaut: 15)
notif_nutrition_log_enabled     Bool
notif_nutrition_review_hour     Int
notif_mind_mood_enabled         Bool
notif_productivity_morning_enabled  Bool
notif_productivity_evening_enabled  Bool
notif_habits_enabled            Bool
notif_habits_hour               Int
notif_finance_monthly_enabled   Bool
notif_finance_weekly_enabled    Bool
notif_invest_dca_enabled        Bool
notif_invest_weekly_enabled     Bool
notif_career_weekly_enabled     Bool
notif_learning_enabled          Bool
notif_cycle_pms_enabled         Bool
notif_cycle_daily_enabled       Bool
notif_home_cleaning_enabled     Bool
notif_home_groceries_enabled    Bool
notif_admin_enabled             Bool
notif_social_enabled            Bool
```

**Règle d'or :** si `notif_{module}_*_enabled` est absent ou false → aucune notification pour ce module.
