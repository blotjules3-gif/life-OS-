# Questions de configuration — Modules LifeOS
# Chaque clé de notification a sa propre question. Rien n'est hardcodé.

## RÈGLE FONDAMENTALE

Pour chaque notification, deux questions distinctes :
1. L'heure de l'événement (repas, séance, coucher…) → contexte pour le coaching
2. L'heure exacte de la notification → posée séparément, jamais calculée automatiquement

Si la question de notification n'a pas été posée → clé absente → notification désactivée.

---

## MODULE : SOMMEIL (sleep)

### Questions sur l'événement
| Question | Clé | Type |
|---|---|---|
| "À quelle heure tu te lèves normalement ?" | `wakeupHour` / `wakeupMinute` | Int |
| "À quelle heure tu veux te coucher ?" | `bedHour` / `bedMinute` | Int |
| "Combien d'heures de sommeil tu vises ?" | `sleep_target_hours` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un bilan le matin après ton réveil ?" | `notif_sleep_morning_enabled` | Bool |
| "À quelle heure tu veux ce bilan matin ?" | `notif_sleep_morning_hour` / `notif_sleep_morning_minute` | Int |
| "Tu veux un rappel pour aller te coucher ?" | `notif_sleep_bedtime_enabled` | Bool |
| "À quelle heure tu veux ce rappel de coucher ?" | `notif_sleep_bedtime_hour` / `notif_sleep_bedtime_minute` | Int |

**Notifications :**
- `sleep_morning` → `notif_sleep_morning_hour:notif_sleep_morning_minute` (si enabled)
- `sleep_bedtime` → `notif_sleep_bedtime_hour:notif_sleep_bedtime_minute` (si enabled)

---

## MODULE : FITNESS (fitness)

### Questions sur l'événement
| Question | Clé | Type |
|---|---|---|
| "Tu t'entraînes le matin, midi ou le soir ?" | `fitness_timing` | String |
| "À quelle heure ta séance commence ?" | `sportHour` | Int |
| "Quels jours de la semaine ?" | `fitness_days` | String ("1,3,5") |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel avant ta séance ?" | `notif_fitness_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_fitness_hour` | Int |
| "Ce rappel s'applique à quels jours ?" | `notif_fitness_days` | String ("1,3,5") |

**Notifications :**
- `fitness_reminder` → `notif_fitness_hour:00` les jours dans `notif_fitness_days` (si enabled)

---

## MODULE : NUTRITION (nutrition)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu pratiques le jeûne intermittent ?" | `nutrition_fasting_enabled` | Bool |
| "À quelle heure commence ta fenêtre alimentaire ?" | `nutrition_fasting_start_hour` | Int |
| "À quelle heure se termine ta fenêtre alimentaire ?" | `nutrition_fasting_end_hour` | Int |
| "À quelle heure tu prends ton petit-déjeuner ?" | `nutrition_breakfast_hour` | Int |
| "À quelle heure tu manges le midi ?" | `nutrition_lunch_hour` | Int |
| "À quelle heure tu dînes ?" | `nutrition_dinner_hour` | Int |
| "Tu prends des compléments alimentaires ?" | `nutrition_supplements_enabled` | Bool |
| "Certains compléments se prennent le matin ?" | `supplement_morning_enabled` | Bool |
| "Certains compléments se prennent le soir ?" | `supplement_evening_enabled` | Bool |
| "Certains compléments se prennent à un repas précis ?" | `supplement_meal_linked` | Bool |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour noter ton petit-déjeuner ?" | `notif_nutrition_breakfast_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_nutrition_breakfast_hour` | Int |
| "Tu veux un rappel pour noter ton déjeuner ?" | `notif_nutrition_lunch_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_nutrition_lunch_hour` | Int |
| "Tu veux un rappel pour noter ton dîner ?" | `notif_nutrition_dinner_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_nutrition_dinner_hour` | Int |
| "Tu veux un bilan calories en fin de journée ?" | `notif_nutrition_review_enabled` | Bool |
| "À quelle heure tu veux ce bilan ?" | `notif_nutrition_review_hour` | Int |
| "Tu veux un rappel pour tes compléments du matin ?" | `notif_supplement_morning_enabled` | Bool |
| "À quelle heure tu veux ce rappel compléments matin ?" | `notif_supplement_morning_hour` | Int |
| "Tu veux un rappel pour tes compléments du soir ?" | `notif_supplement_evening_enabled` | Bool |
| "À quelle heure tu veux ce rappel compléments soir ?" | `notif_supplement_evening_hour` | Int |

**Notifications :**
- `nutrition_breakfast` → `notif_nutrition_breakfast_hour:00` (si enabled, si pas jeûne)
- `nutrition_lunch` → `notif_nutrition_lunch_hour:00` (si enabled)
- `nutrition_dinner` → `notif_nutrition_dinner_hour:00` (si enabled)
- `nutrition_review` → `notif_nutrition_review_hour:00` (si enabled)
- `supplement_morning` → `notif_supplement_morning_hour:00` (si enabled)
- `supplement_evening` → `notif_supplement_evening_hour:00` (si enabled)

---

## MODULE : MENTAL / BIEN-ÊTRE (mind)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu préfères méditer le matin ou le soir ?" | `mind_session_timing` | String |
| "À quelle heure tu fais ta session ?" | `mind_session_hour` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour ta session bien-être ?" | `notif_mind_session_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_mind_session_hour` | Int |
| "Tu veux un check-in humeur quotidien ?" | `notif_mind_mood_enabled` | Bool |
| "À quelle heure tu veux faire ton check-in humeur ?" | `notif_mind_mood_hour` | Int |

**Notifications :**
- `mind_session` → `notif_mind_session_hour:00` (si enabled)
- `mind_mood` → `notif_mind_mood_hour:00` (si enabled)

---

## MODULE : PRODUCTIVITÉ (productivity)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "À quelle heure tu commences ta journée de travail ?" | `productivity_start_hour` | Int |
| "À quelle heure tu termines ta journée ?" | `productivity_end_hour` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un point sur tes priorités en début de journée ?" | `notif_productivity_morning_enabled` | Bool |
| "À quelle heure tu veux ce rappel matin ?" | `notif_productivity_morning_hour` | Int |
| "Tu veux un bilan de tes todos en fin de journée ?" | `notif_productivity_evening_enabled` | Bool |
| "À quelle heure tu veux ce bilan soir ?" | `notif_productivity_evening_hour` | Int |
| "Tu veux un rappel pour tes habitudes ?" | `notif_habits_enabled` | Bool |
| "À quelle heure tu veux voir tes habitudes ?" | `notif_habits_hour` | Int |

**Notifications :**
- `productivity_morning` → `notif_productivity_morning_hour:00` (si enabled)
- `productivity_evening` → `notif_productivity_evening_hour:00` (si enabled)
- `habits_reminder` → `notif_habits_hour:00` (si enabled)

---

## MODULE : FINANCES (finance)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Quel jour du mois tu reçois ton salaire ?" | `finance_salary_day` | Int (1-31) |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un bilan budget mensuel le jour de ton salaire ?" | `notif_finance_monthly_enabled` | Bool |
| "À quelle heure tu veux ce bilan mensuel ?" | `notif_finance_monthly_hour` | Int |
| "Tu veux un bilan budget hebdomadaire ?" | `notif_finance_weekly_enabled` | Bool |
| "Quel jour de la semaine ?" | `finance_review_weekday` | Int (1=lun, 7=dim) |
| "À quelle heure tu veux ce bilan ?" | `notif_finance_weekly_hour` | Int |

**Notifications :**
- `finance_monthly` → `finance_salary_day` à `notif_finance_monthly_hour:00` (si enabled)
- `finance_weekly` → chaque `finance_review_weekday` à `notif_finance_weekly_hour:00` (si enabled)

---

## MODULE : INVESTISSEMENT (invest)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu investis régulièrement chaque mois (DCA) ?" | `invest_dca_enabled` | Bool |
| "Quel jour du mois tu veux investir ?" | `invest_dca_day` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour ton investissement mensuel ?" | `notif_invest_dca_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_invest_dca_hour` | Int |
| "Tu veux une revue portfolio hebdomadaire ?" | `notif_invest_weekly_enabled` | Bool |
| "Quel jour de la semaine ?" | `invest_review_weekday` | Int |
| "À quelle heure tu veux cette revue ?" | `notif_invest_weekly_hour` | Int |

**Notifications :**
- `invest_dca` → `invest_dca_day` à `notif_invest_dca_hour:00` (si enabled)
- `invest_weekly` → chaque `invest_review_weekday` à `notif_invest_weekly_hour:00` (si enabled)

---

## MODULE : CARRIÈRE (career)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu es en recherche d'emploi active ?" | `career_job_searching` | Bool |
| "Combien de candidatures par semaine tu vises ?" | `career_applications_target` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel hebdomadaire pour tes candidatures ?" | `notif_career_weekly_enabled` | Bool |
| "Quel jour de la semaine ?" | `career_review_weekday` | Int |
| "À quelle heure tu veux ce rappel ?" | `notif_career_weekly_hour` | Int |

**Notifications :**
- `career_weekly` → chaque `career_review_weekday` à `notif_career_weekly_hour:00` (si enabled && job_searching)

---

## MODULE : APPRENTISSAGE (learning)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu préfères apprendre le matin ou le soir ?" | `learning_timing` | String |
| "À quelle heure tu fais ta session ?" | `learning_session_hour` | Int |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel quotidien pour ta session ?" | `notif_learning_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_learning_hour` | Int |

**Notifications :**
- `learning_daily` → `notif_learning_hour:00` (si enabled)

---

## MODULE : CYCLE MENSTRUEL (cycle)

### Questions sur les événements
*(cycle calculé depuis les données de tracking — pas de question heure d'événement)*

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux tracker ton cycle chaque jour ?" | `notif_cycle_daily_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_cycle_daily_hour` | Int |
| "Tu veux être prévenue avant tes règles ?" | `notif_cycle_pms_enabled` | Bool |
| "Combien de jours avant tu veux être prévenue ?" | `cycle_pms_advance_days` | Int |
| "À quelle heure tu veux cette alerte ?" | `notif_cycle_pms_hour` | Int |

**Notifications :**
- `cycle_daily` → `notif_cycle_daily_hour:00` (si enabled)
- `cycle_pms` → J-`cycle_pms_advance_days` à `notif_cycle_pms_hour:00` (si enabled)

---

## MODULE : MAISON (home)

### Questions sur les événements
*(pas d'heure d'événement fixe — les questions de notif suffisent)*

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel hebdomadaire pour le ménage ?" | `notif_home_cleaning_enabled` | Bool |
| "Quel jour de la semaine ?" | `home_cleaning_weekday` | Int |
| "À quelle heure tu veux ce rappel ?" | `notif_home_cleaning_hour` | Int |
| "Tu veux un rappel pour faire les courses ?" | `notif_home_groceries_enabled` | Bool |
| "Quel jour tu fais tes courses ?" | `home_groceries_weekday` | Int |
| "À quelle heure tu veux ce rappel ?" | `notif_home_groceries_hour` | Int |

**Notifications :**
- `home_cleaning` → chaque `home_cleaning_weekday` à `notif_home_cleaning_hour:00` (si enabled)
- `home_groceries` → chaque `home_groceries_weekday` à `notif_home_groceries_hour:00` (si enabled)

---

## MODULE : ADMIN (admin)

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel hebdomadaire pour l'admin ?" | `notif_admin_enabled` | Bool |
| "Quel jour de la semaine ?" | `admin_session_weekday` | Int |
| "À quelle heure tu veux ce rappel ?" | `notif_admin_hour` | Int |

**Notifications :**
- `admin_session` → chaque `admin_session_weekday` à `notif_admin_hour:00` (si enabled)

---

## MODULE : CORPS / LOOKS (looks)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu as une routine soin le matin ?" | `looks_has_morning_routine` | Bool |
| "Tu as une routine soin le soir ?" | `looks_has_evening_routine` | Bool |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour ta routine matin ?" | `notif_looks_morning_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_looks_morning_hour` | Int |
| "Tu veux un rappel pour ta routine soir ?" | `notif_looks_evening_enabled` | Bool |
| "À quelle heure tu veux ce rappel ?" | `notif_looks_evening_hour` | Int |

**Notifications :**
- `looks_morning` → `notif_looks_morning_hour:00` (si enabled && has_morning_routine)
- `looks_evening` → `notif_looks_evening_hour:00` (si enabled && has_evening_routine)

---

## MODULE : SOCIAL (social)

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour garder contact avec ton réseau ?" | `notif_social_enabled` | Bool |
| "Quel jour de la semaine ?" | `social_contact_weekday` | Int |
| "À quelle heure tu veux ce rappel ?" | `notif_social_hour` | Int |

**Notifications :**
- `social_reminder` → chaque `social_contact_weekday` à `notif_social_hour:00` (si enabled)

---

## MODULE : MÉDICAL (medical)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu prends des médicaments régulièrement ?" | `medical_medications_enabled` | Bool |
| "Certains médicaments se prennent le matin ?" | `medical_med_morning_enabled` | Bool |
| "Certains médicaments se prennent le midi ?" | `medical_med_noon_enabled` | Bool |
| "Certains médicaments se prennent le soir ?" | `medical_med_evening_enabled` | Bool |
| "Tu as des rendez-vous médicaux réguliers ?" | `medical_appointments_regular` | Bool |
| "Tu suis tes constantes (tension, poids, glycémie…) ?" | `medical_vitals_tracking` | Bool |
| "À quelle fréquence tu mesures tes constantes ?" | `medical_vitals_frequency` | String (daily/weekly/monthly) |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour tes médicaments du matin ?" | `notif_medical_morning_enabled` | Bool |
| "À quelle heure ce rappel matin ?" | `notif_medical_morning_hour` | Int |
| "Tu veux un rappel pour tes médicaments du midi ?" | `notif_medical_noon_enabled` | Bool |
| "À quelle heure ce rappel midi ?" | `notif_medical_noon_hour` | Int |
| "Tu veux un rappel pour tes médicaments du soir ?" | `notif_medical_evening_enabled` | Bool |
| "À quelle heure ce rappel soir ?" | `notif_medical_evening_hour` | Int |
| "Tu veux un rappel pour mesurer tes constantes ?" | `notif_medical_vitals_enabled` | Bool |
| "À quelle heure ce rappel constantes ?" | `notif_medical_vitals_hour` | Int |
| "Tu veux une alerte avant tes RDV médicaux ?" | `notif_medical_appointment_enabled` | Bool |
| "Combien d'heures avant le RDV tu veux l'alerte ?" | `notif_medical_appointment_advance_h` | Int |

**Notifications :**
- `medical_morning` → `notif_medical_morning_hour:00` (si enabled && medical_med_morning_enabled)
- `medical_noon` → `notif_medical_noon_hour:00` (si enabled && medical_med_noon_enabled)
- `medical_evening` → `notif_medical_evening_hour:00` (si enabled && medical_med_evening_enabled)
- `medical_vitals` → `notif_medical_vitals_hour:00` (si enabled, à la fréquence définie)
- `medical_appointment` → calculé depuis la date du prochain RDV − `notif_medical_appointment_advance_h`h

---

## MODULE : MOBILITÉ (mobility)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu as une voiture / moto / vélo ?" | `mobility_has_vehicle` | Bool |
| "Quel type de trajet tu fais régulièrement ?" | `mobility_commute_type` | String (car/transit/bike/walk) |
| "À quelle heure tu pars le matin ?" | `mobility_departure_hour` | Int |
| "Tu fais le plein régulièrement ?" | `mobility_fuel_tracking` | Bool |
| "Quand est le prochain contrôle technique ?" | `mobility_ct_date` | String (date) |
| "Quand expire ton assurance ?" | `mobility_insurance_expiry` | String (date) |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour partir à l'heure le matin ?" | `notif_mobility_departure_enabled` | Bool |
| "À quelle heure ce rappel départ ?" | `notif_mobility_departure_hour` | Int |
| "Tu veux un rappel pour faire le plein ?" | `notif_mobility_fuel_enabled` | Bool |
| "Quel jour de la semaine ce rappel carburant ?" | `mobility_fuel_weekday` | Int |
| "À quelle heure ce rappel carburant ?" | `notif_mobility_fuel_hour` | Int |
| "Tu veux une alerte avant le contrôle technique ?" | `notif_mobility_ct_enabled` | Bool |
| "Combien de jours avant tu veux l'alerte CT ?" | `mobility_ct_advance_days` | Int |

**Notifications :**
- `mobility_departure` → `notif_mobility_departure_hour:00` chaque jour (si enabled)
- `mobility_fuel` → chaque `mobility_fuel_weekday` à `notif_mobility_fuel_hour:00` (si enabled)
- `mobility_ct` → `mobility_ct_advance_days` jours avant la date CT (si enabled, date ponctuelle)

---

## MODULE : VOYAGE (travel)

### Questions sur les événements
| Question | Clé | Type |
|---|---|---|
| "Tu as un voyage prévu bientôt ?" | `travel_upcoming` | Bool |
| "Tu pars combien de fois par an en voyage ?" | `travel_frequency` | Int |
| "Tu prépares ta valise en avance ou au dernier moment ?" | `travel_packing_style` | String (advance/last_minute) |

### Questions sur les notifications
| Question | Clé | Type |
|---|---|---|
| "Tu veux un rappel pour préparer ta valise ?" | `notif_travel_packing_enabled` | Bool |
| "Combien de jours avant le départ ce rappel ?" | `travel_packing_advance_days` | Int |
| "Tu veux un rappel la veille du départ ?" | `notif_travel_departure_eve_enabled` | Bool |
| "À quelle heure ce rappel veille de départ ?" | `notif_travel_departure_eve_hour` | Int |
| "Tu veux un rappel pour vérifier les documents (passeport, billets) ?" | `notif_travel_docs_enabled` | Bool |
| "Combien de jours avant le départ ?" | `travel_docs_advance_days` | Int |

**Notifications :**
- `travel_packing` → `travel_packing_advance_days` jours avant départ (ponctuelle, date du voyage)
- `travel_docs` → `travel_docs_advance_days` jours avant départ (ponctuelle)
- `travel_departure_eve` → veille du départ à `notif_travel_departure_eve_hour:00` (ponctuelle)
