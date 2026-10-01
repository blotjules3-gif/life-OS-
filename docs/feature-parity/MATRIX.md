# Matrice des fonctionnalités

Généré par `render.py`. États : **vérifié sur appareil**, **présent, test auto**, **présent, non testé**, **manquant**, **dépendance externe**.
Les outils sans matrice ne sont pas encore inventoriés fonction par fonction.

Inventoriés : 89 sur 89.

Fonctions inventoriées : présent, test auto 294, présent, non testé 356, manquant 450, dépendance externe 109. Défauts trouvés : 106, corrigés 102, partiels 4, ouverts 0.



## 🩺 Santé


### MediSûr (Medisafe)
Résumé : présent, test auto 3, présent, non testé 5, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'un traitement (nom, dosage, notes, date de fin) | présent, non testé | MedicalModule.swift:92 MedicationEditor, add() :164 |
| Fréquences 1x/2x/3x par jour, hebdo, au besoin | présent, test auto | LifeOSTests/MedicationScheduleTests.swift testThreeTimesPerDay, testWeeklyIsDet… |
| Plusieurs heures de prise personnalisées (minutes, jours précis, inte… | manquant | Editor offers only whole-hour Steppers matin/soir (MedicalModule.swift:118-121)… |
| Plan de rappels borné / futur / sans fin | présent, test auto | LifeOSTests/MedicationPlanTests.swift testWeeklyWithEndDateStaysWeekly, testDai… |
| Budget commun des 64 notifications iOS | présent, test auto | LifeOSTests/MedicationBudgetTests.swift testLongCourseUsesTheSharedBudgetNotAPe… |
| Couverture réelle des rappels affichée (refus, échec, jusqu'au…) | présent, non testé | MedicalModule.swift:278 coverageText, shown in medRow :64 |
| Activer / terminer / supprimer un traitement (rappels retirés) | présent, non testé | MedicalModule.swift:77 setActive, :83 remove -> reconcileAll :213 |
| Modifier un traitement existant | présent, non testé | MedicalModule.swift:80 menu « Modifier » -> sheet :46 MedicationEditor(editing:… |
| Journal des prises pris/sauté/reporté/manqué avec annulation | manquant | no dose event model: grep 'DoseLog/MedicationDose/DoseEvent/MedicationIntake' i… |
| Stock / renouvellement d'ordonnance | manquant | Medication model (Models_Health.swift:179) has no stock/refill/pill count field |
| Historique d'observance et rapport | manquant | no adherence computation; nothing records a taken dose |
| Export des traitements | présent, non testé | DataExporter.swift:55 (export JSON global depuis ProfileView.swift:309), pas de… |
| Profils dépendants et partage aidant | manquant | Medication has no owner/person field; no sharing code in MedicalModule.swift |
| Pièce jointe d'ordonnance | manquant | no attachment/photo field on Medication, no picker in MedicationEditor |
| Interactions / recherche médicament | dépendance externe | needs a real drug-data service (e.g. BDPM/RxNorm); no lookup code, name is free… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `MedicalModule.swift:51-75` : Medication notes (side effects, instructions) are saved but never displayed anywhere in the app, and there is no edit view, so typed info is invisible.

### Doctolink (Doctolib)
Résumé : présent, test auto 1, présent, non testé 6, manquant 3, dépendance externe 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Agenda personnel de RDV (date, spécialité, médecin, lieu) | présent, non testé | MedicalModule.swift:399 AppointmentEditor, list AppointmentsView :332 |
| Séparation à venir / passés | présent, non testé | MedicalModule.swift:337-338 |
| Rappel la veille du RDV | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testAppointmentWithin24hStillGetsARemin… |
| Suppression qui annule le rappel | présent, non testé | MedicalModule.swift:389-394 |
| Prochain RDV de suivi (date) | présent, non testé | MedicalModule.swift:427-429, shown :381 |
| Notes du RDV visibles / modifier un RDV | présent, non testé | Notes affichées MedicalModule.swift:416; tap ou « Modifier » :427-429 -> Appoin… |
| Annuaire et filtre de praticiens | dépendance externe | needs a practitioner directory API (Doctolib has no public API); specialty is a… |
| Créneaux en direct, réservation, report, annulation chez le praticien | dépendance externe | needs a practitioner booking API; nothing calls a provider |
| Confirmations de réservation | dépendance externe | needs provider booking backend |
| Liste d'attente et notifications de créneau | dépendance externe | needs provider booking backend |
| Messagerie sécurisée et téléconsultation | dépendance externe | needs provider platform + secure messaging service |
| Profils dépendants | manquant | MedicalAppointment (Models_Health.swift:206) has no person field |
| Documents et historique de consultation | manquant | no attachment field on MedicalAppointment; notes not displayed |
| Distinction RDV confirmé praticien vs entrée perso | manquant | single MedicalAppointment type, no confirmed/status field |
| Export des RDV | présent, non testé | DataExporter.swift:63 (export JSON global) |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MedicalModule.swift:441-446` : Reminder is set to exactly 24 h before; for an appointment less than 24 h away NotificationManager.schedule (NotificationManager.swift:78) silently drops it, w…
- [corrigé] `MedicalModule.swift:369-387` : Appointment notes (motif, résultats, ordonnances) are stored but never shown, and appointments cannot be edited.

### Maple Health (Apple Santé)
Résumé : présent, test auto 1, présent, non testé 4, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Saisie manuelle poids, tension, glycémie, FC | présent, non testé | MedicalModule.swift:601 VitalEditor |
| Liste filtrée par type | présent, non testé | MedicalModule.swift:471-485 |
| Graphe de tendance 30 dernières mesures, min/max/delta | présent, non testé | MedicalModule.swift:510 trendCard |
| Import HealthKit avec source par mesure | manquant | VitalsView never calls HealthService; VitalRecord (Models_Health.swift:220) has… |
| Catégories de métriques Apple Santé au-delà de 4 types | manquant | types fixed to 4 strings (MedicalModule.swift:463) |
| Unités configurables (mmol/L, lb) | manquant | unit hard-coded per type (MedicalModule.swift:611-619), glycémie always g/L |
| Plages de référence | manquant | no range/threshold anywhere in VitalsView |
| Exploration historique par période (jour/semaine/mois/année) | manquant | chart limited to last 30 points (MedicalModule.swift:507), no range selector |
| Doublons de sources / inconnu vs zéro | manquant | no dedup logic; no source field |
| Modifier une mesure | manquant | only delete via contextMenu (MedicalModule.swift:597) |
| Export / partage | présent, non testé | DataExporter.swift:51 (export JSON global), pas de partage ciblé |
| Documents cliniques, vues médicaments/cycle Apple Santé | dépendance externe | needs HealthKit clinical records entitlement + real health data |
| Couleur de tendance selon le sens (tension, glycémie, FC qui montent … | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testRisingBloodPressureIsNotGood (Vital… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MedicalModule.swift:580-582` : Any rise in blood pressure, glycemia or heart rate is coloured green as 'positive', which reads as good news for a worsening value.
- [corrigé] `MedicalModule.swift:532-549` : Blood pressure trend plots only the systolic value; diastolic (value2) is ignored in the chart and the delta.

### Mon Espace Vaccin (Mon espace santé)
Résumé : présent, test auto 1, présent, non testé 5, manquant 5, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Historique des vaccins (nom, date d'injection) | présent, non testé | MedicalModule.swift:730 VaccinationEditor, list :663 |
| Liste de vaccins courants | présent, non testé | MedicalModule.swift:740 |
| Date de rappel et section 'à prévoir sous 30 jours' | présent, non testé | Models_Health.swift:241 isDue, MedicalModule.swift:679-684 |
| Notification de rappel 30 jours avant | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testVaccineDueSoonStillGetsAReminder (M… |
| Numéro de lot | présent, non testé | saved MedicalModule.swift:752/767 but never shown in vaccRow (:700); only visib… |
| Plusieurs personnes (famille) | manquant | Vaccination model has no person field (Models_Health.swift:234) |
| Provenance: produit, dose n°, praticien, document | manquant | only name/date/lot/notes in Vaccination model |
| Calendrier vaccinal officiel versionné et rattrapage | manquant | no schedule data; reminder date is manual (MedicalModule.swift:756) |
| Modifier une vaccination | manquant | only delete (MedicalModule.swift:719-726) |
| Export | présent, non testé | DataExporter.swift:59 (export JSON global) |
| Coffre de documents santé et profil de soins | manquant | not in this tool (no document field) |
| Messagerie sécurisée et interopérabilité DMP | dépendance externe | needs authorised access to Mon espace santé / DMP |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MedicalModule.swift:769-774` : Reminder fires 30 days before the due date; if the due date is within 30 days the date is in the past and the reminder is silently never scheduled.
- [corrigé] `MedicalModule.swift:700-718` : Lot number is saved but never displayed in the app (only in the JSON export).

## 🌸 Cycle


### Floé (Flo)
Résumé : présent, test auto 4, présent, non testé 5, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Saisir la date des dernières règles et la durée du cycle | présent, non testé | CycleModule.swift:283-303 sheet, Stepper :290 |
| Jour du cycle, phase, 'règles dans N jours' | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testCycleDoesNotWrapPastItsLength, test… |
| Saisie du jour: flux, symptômes, humeur | présent, non testé | CycleModule.swift:341 saveEntry |
| Conseils par phase (énergie, sport, nutriments) | présent, non testé | CycleModule.swift:136-172 (texte statique CyclePhase) |
| Rappels règles J-3 / ovulation / SPM | présent, non testé | NotificationManager.swift:239 scheduleCycleNotifications, called by CycleContex… |
| Éditer un jour passé / calendrier historique | manquant | saveEntry always creates CycleEntry dated now (CycleModule.swift:350); no date … |
| Bornes explicites début/fin de règles | manquant | start is a single manual date; logged flow days never move it (CycleModule.swif… |
| Prédiction cycle variable avec incertitude | manquant | prediction = elapsed % manual length (CycleContext.swift:109), no use of CycleS… |
| Phases adaptées à la durée du cycle | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testOvulationFollowsCycleLength (CycleM… |
| Objectifs et modes de vie (grossesse, fertilité, périménopause) | manquant | no mode/goal setting in CycleModule.swift or CycleContext.swift |
| Contenu éducatif | manquant | only one-line phase tips; no articles |
| Partage contrôlé par l'utilisatrice | manquant | no share code in CycleModule.swift |
| Sauvegarde/restauration des entrées | présent, test auto | LifeOSTests/FullBackupTests.swift testBackupThenRestoreRebuildsEverything (Cycl… |
| Export des entrées de cycle | présent, non testé | DataExporter.swift:44 section « cycle » (date, flux, symptômes, humeur, note); … |
| Des règles saisies (>= 15 j après le début connu) déplacent le début … | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testNewPeriodMovesCycleStart, testSameP… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `CycleModule.swift:353 + CycleContext.swift:109` : Logging flow only sets the cycle start when none exists, and refresh() wraps elapsed % length, so after the first cycle the day count and 'Règles dans N jours'…
- [corrigé] `CycleContext.swift:115-121` : Phase and ovulation window are fixed at days 14-16 whatever the cycle length (21 to 45 allowed), so a 35-day cycle gets ovulation and PMS advice on the wrong d…
- [corrigé] `DataExporter.swift:15-140` : The app's data export omits CycleEntry entirely, so cycle history is missing from the user's export.

### Klue (Clue)
Résumé : présent, test auto 1, présent, non testé 3, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| 8 symptômes prédéfinis cochables | présent, non testé | CycleModule.swift:48 symptomsAll, toggles :210-232 |
| Humeur 5 niveaux | présent, non testé | CycleModule.swift:49, :238-260 |
| Flux 4 niveaux | présent, non testé | CycleModule.swift:46 |
| Liste de fréquence des symptômes récents | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testRecentSymptomsOnlyLastThreeCalendar… |
| Intensité / durée par symptôme | manquant | CycleEntry.symptoms is [String] (CycleModule.swift:10), no intensity |
| Douleur, pertes, sommeil, énergie, peau (catégories Clue) | manquant | only 8 fixed strings; no discharge/pain scale; hub subtitle 'énergie, peau' not… |
| Tags personnalisés | manquant | symptom list hard-coded, no add |
| Note libre du jour | manquant | CycleEntry.note exists but no TextField in CycleModule.swift (grep TextField 0 … |
| Recherche dans les entrées | manquant | no search in CycleSymptomsView/CycleHistoryView |
| Corrélations symptômes / phase | manquant | no phase attached to entries, no correlation code |
| Tendances et export des symptômes | manquant | no chart; CycleEntry absent from DataExporter.swift |
| Catégories selon le stade de vie | manquant | no life-stage setting |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `CycleModule.swift:372 + :388` : Section titled '3 derniers jours' counts the last 3 entries regardless of date, so symptoms from months ago are shown as recent.

### Floé Stats (Flo / Clue)
Résumé : présent, test auto 6, présent, non testé 2, manquant 7

| Fonctionnalité | État | Preuve |
|---|---|---|
| Regroupement des jours de flux en règles | présent, test auto | LifeOSTests/CycleStatsTests.swift testPeriodStartsGroupsConsecutiveDays, testOn… |
| Durée moyenne du cycle | présent, test auto | LifeOSTests/CycleStatsTests.swift testDailyLoggingStillGivesAnAverage, testOnly… |
| Cycle le plus court / le plus long | présent, test auto | LifeOSTests/CycleStatsTests.swift testShortestAndLongest |
| Régularité (écart <= 7 j) | présent, test auto | LifeOSTests/CycleStatsTests.swift testRegularWhenSpreadIsSmall |
| Données insuffisantes (pas de moyenne sur 1 cycle) | présent, test auto | LifeOSTests/CycleStatsTests.swift testSinglePeriodGivesNil, testNoDataGivesNil;… |
| Exclusion des écarts implausibles | présent, test auto | LifeOSTests/CycleStatsTests.swift testImplausibleGapIsIgnored |
| Liste des 30 dernières entrées | présent, non testé | CycleModule.swift:453-472 |
| Durée des règles | manquant | CycleStats.Summary has no period length (CycleStats.swift:16-26) |
| Distribution des durées de cycle (graphe) | manquant | no Chart in CycleHistoryView |
| Superposition des tendances de symptômes | manquant | no symptom trend code |
| Filtre par période | manquant | no date range control in CycleHistoryView |
| Corriger / supprimer une entrée | manquant | no delete or edit in CycleHistoryView (CycleModule.swift:457) |
| Export de rapport | manquant | no report; CycleEntry absent from DataExporter.swift |
| Même calcul partout (tracker, coach) | manquant | tracker uses manual cycleLengthDays (CycleModule.swift:44, CycleContext.swift:1… |
| Moyenne observée affichée sur le suivi avec bouton « Utiliser X j » | présent, non testé | CycleModule.swift:114-118; aucun test (le calcul reste différent entre suivi et… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `CycleModule.swift:44 vs CycleModule.swift:414` : Tracker and notifications use the manual Stepper length while Stats computes a different average from flow days; the two screens can show contradictory cycle l…

## 😴 Sommeil


### Sleep Circle (Sleep Cycle)
Résumé : présent, non testé 2, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| Heures de coucher pour 4/5/6 cycles avant un réveil | présent, non testé | SleepModule.swift:59 bedtimeRow |
| Heures de réveil si coucher maintenant | présent, non testé | SleepModule.swift:64 wakeRow |
| Session nocturne enregistrée (micro/mouvement) | manquant | BedtimeCalculatorView has no recording; sound events live in the separate Nuit … |
| Acquisition sommeil HealthKit | manquant | HealthService.sleepHoursLastNight (HealthService.swift:207) is never called by … |
| Hypnogramme / chronologie de la nuit | manquant | no timeline view in SleepModule.swift |
| Tendances de qualité | manquant | not in this tool; only manual 7-night stats in SleepDashboard.swift:88 (categor… |
| Notes de nuit et événements audio | manquant | not in this tool (SleepNight.note in dashboard, audio in Nuit sonore) |
| Réveil intelligent en fenêtre de sommeil léger | manquant | explicitly not done, IntegrationNotice SleepModule.swift:51 |
| Historique et export des nuits | manquant | BedtimeCalculatorView stores nothing |
| Délai d'endormissement réglable | manquant | fallAsleep fixed at 15 min (SleepModule.swift:15) |

### Pzazz (Pzizz)
Résumé : présent, test auto 3, présent, non testé 2, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Durée 20 ou 90 min | présent, non testé | SleepModule.swift:100-104 |
| Compte à rebours qui survit à une relance | présent, test auto | LifeOSTests/CountdownEngineTests.swift testSessionSurvivesProcessRestart |
| Pause / reprise | présent, test auto | LifeOSTests/CountdownEngineTests.swift testPauseFreezesAndResumeRebasesTheDeadl… |
| Arrêt | présent, test auto | LifeOSTests/CountdownEngineTests.swift testStopClearsPersistedState |
| Réveil par notification programmée au démarrage | présent, non testé | SleepModule.swift:128 scheduleAfter (works locked) |
| Durée libre configurable | manquant | Picker has only two tags 20/90 (SleepModule.swift:101-102) |
| Programmes narrés / paysages sonores | manquant | no audio playback in PowerNapView (no AVAudioPlayer/sound asset) |
| Mixage voix/son, fondu entrée/sortie | manquant | no audio engine in PowerNapView |
| Alarme de réveil progressive | manquant | only a default-sound local notification |
| Historique des siestes | manquant | no nap model; CountdownEngine state cleared on finish |
| Modes sommeil / concentration | manquant | nap only |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `SleepModule.swift:142-146` : When the nap ends with the screen open, started stays true and the button shows 'Reprendre'; tapping it no-ops engine.resume() but still schedules a 'Réveil' n…

### Rize (Rise)
Résumé : présent, non testé 2, manquant 7

| Fonctionnalité | État | Preuve |
|---|---|---|
| Rappel quotidien de décompression à heure choisie | présent, non testé | SleepModule.swift:184-188, schedule() :208 |
| Conseils mode nuit (guidance, pas un faux interrupteur) | présent, non testé | SleepModule.swift:194 checklistRow Night Shift text |
| Checklist du soir cochable | manquant | checklistRow (SleepModule.swift:214) is static text, no checked state |
| Dette de sommeil / historique | manquant | not in WindDownView; only in SleepDashboard.swift:88 (category dashboard, manua… |
| Horaire de coucher personnalisé calculé | manquant | reminder hour is a manual default 22:30 (SleepModule.swift:173-174) |
| Fenêtres d'énergie (circadien) | manquant | no energy curve code in SleepModule.swift |
| Intégration calendrier | manquant | no EventKit use in WindDownView |
| Étiquetage des prédictions et couverture des données | manquant | no prediction shown |
| Raccourcis / Focus système guidés | manquant | no Shortcuts/Focus integration, only a text line |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `SleepDashboard.swift:90 + :192` : Sleep debt counts every unlogged night as 0 h slept (full debt), treating unknown as zero.

### Awaken (Awoken)
Résumé : présent, test auto 1, présent, non testé 7, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Rêve texte + titre | présent, non testé | SleepModule.swift:291 DreamEditor |
| Note vocale enregistrée | présent, non testé | SleepModule.swift:307 -> AudioRecorder.start :342 |
| Lecture de la note vocale | présent, non testé | SleepModule.swift:283 play |
| Intensité 1-5 | présent, non testé | SleepModule.swift:317 |
| Suppression d'un rêve | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testDreamAudioFileIsRemoved (AudioRecor… |
| Modifier un rêve existant | manquant | DreamCard has no edit; DreamEditor always inserts |
| Transcription de la voix | manquant | no Speech framework use in SleepModule.swift (grep 'transcri' 0 hits) |
| Recherche et tags | manquant | DreamEntry has no tags; no search field in DreamJournalView |
| Gestion de lecture (pause, position) | manquant | play() only starts AVAudioPlayer, no stop/scrub (SleepModule.swift:283-288) |
| Rappels reality check | manquant | no notification scheduling in SleepModule dream code |
| Exercices de rêve lucide et progression | manquant | none |
| Export | présent, non testé | DataExporter.swift:39 (texte seulement, sans l'audio) |
| Sauvegarde | présent, non testé | FullBackup (Documents + base) covers dream audio; no test seeds DreamEntry |
| Fichiers audio gérés de façon transactionnelle | présent, non testé | Suppression du fichier à la suppression du rêve SleepModule.swift:288, au réenr… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `SleepModule.swift:277` : Deleting a dream removes the row but leaves its .m4a file in Documents forever.
- [corrigé] `SleepModule.swift:346-357` : Recording a second time in the editor overwrites filename and orphans the first audio file on disk.
- [corrigé] `SleepModule.swift:354-357 + :314` : AVAudioRecorder creation errors are swallowed by try?, yet isRecording and filename are set, so the UI says 'Note vocale enregistrée' and the entry points to a…

### Whoosh (Whoop / AutoSleep)
Résumé : présent, test auto 1, présent, non testé 2, manquant 6, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Lecture HRV (SDNN) Apple Santé | dépendance externe | HealthService.swift:196, needs HealthKit authorization + Apple Watch data |
| Lecture FC repos Apple Santé | dépendance externe | HealthService.swift:191, needs Apple Watch data |
| Score de récupération 0-100 | présent, non testé | SleepModule.swift:372 (fixed constants 80 ms / 40-90 bpm, weights 0.6/0.4) |
| Conseil selon le score | présent, non testé | SleepModule.swift:419 |
| Baseline personnelle longitudinale | manquant | score uses one latest sample vs population constants (SleepModule.swift:375-376) |
| Vues sommeil / effort / stress | manquant | RecoveryScoreView shows only the score and two tiles |
| Tendances | manquant | no history stored or charted |
| Date et couverture des données | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testRecoveryScoreRefusesStaleSamples (R… |
| Explication des contributions | manquant | weights not shown to the user |
| Dette de sommeil, séances, journal: corrélations | manquant | no use of SleepNight/workouts in RecoveryScoreView |
| Distinction modèle LifeOS vs score propriétaire | manquant | no label saying it is a LifeOS heuristic |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `HealthService.swift:352-361` : HRV and resting HR are the most recent sample with no date limit and no date shown, so months-old data is presented as today's recovery.
- [corrigé] `SleepModule.swift:403-404` : Empty state tells the end user to 'Active la capability HealthKit dans Xcode', a developer instruction.

## 🥗 Nutrition


### Zerø (Zero)
Résumé : présent, test auto 7, présent, non testé 4, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Protocole 16:8 / 18:6 / 20:4 / OMAD | présent, non testé | LifeOS/Modules/NutritionModule.swift:93 protocolPicker |
| Démarrer / rompre, enregistrement vérifié (erreur affichée), une seul… | présent, non testé | LifeOS/Modules/NutritionModule.swift:29 FastingView.start / activeControls |
| Corriger l'heure de début (72 h max, pas dans le futur, sans chevauch… | présent, test auto | LifeOSTests/NutritionLotTests.swift FastingStatsTests.testCorrectedStartIsNever… |
| Notification à l'objectif atteint | présent, non testé | NotificationManager.schedule |
| Historique, objectifs atteints x/y, moyenne | présent, test auto | LifeOSTests/NutritionLotTests.swift FastingStatsTests.testSummaryCountsReachedA… |
| Supprimer une entrée (menu ou fiche, confirmation) | présent, non testé | LifeOS/Modules/NutritionModule.swift:221 FastingSessionEditor |
| Widget jeûne avec le vrai début (corrigé 30 sept. : 14,5 h inventées … | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Durée personnalisée (12 à 72 h) | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6FastingTests.testCustomTargetLabel ; L… |
| Modifier début/fin d'un jeûne terminé, saisir un jeûne passé, refus d… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6FastingTests.testOverlapAndSecondActiv… |
| Graphique des 14 derniers jeûnes, série de jours avec objectif atteint | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6FastingTests.testStreakCountsConsecuti… |
| Notes par jeûne (en cours et passés) | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6FastingTests.testNotePersists ; LifeOS… |
| Zones métaboliques | dépendance externe | contenu sourcé sur les phases du jeûne (aucun texte médical inventé) |
| Santé | dépendance externe | HealthService n'expose aucune écriture de jeûne |

### Yumzio (Yazio / MyFitnessPal)
Résumé : présent, test auto 7, présent, non testé 14, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'un repas tout-ou-rien (FoodLogService) | présent, test auto | FoodLogServiceTests.testLogWritesEveryLine |
| Validation de la saisie | présent, test auto | FoodLogServiceTests.testInvalidDraftsAreRefusedBeforeAnyWrite |
| Modifier un repas, retour arrière si échec | présent, test auto | FoodLogServiceTests.testEditRecalculatesTheDayAndRevertsOnFailure |
| Supprimer un repas | présent, test auto | FoodLogServiceTests.testDeleteRemovesFromTheDay |
| Changer la date d'un repas | présent, test auto | FoodLogServiceTests.testHistoricalMealDoesNotCountToday |
| Recherche OpenFoodFacts + portion (nouvelle feuille JournalAddSheet) | présent, test auto | FoodSearch.swift:196 JournalAddSheet, portionSection; FoodJournal.line tested i… |
| Scan code-barres → journal (jour choisi, micros, hors ligne distinct … | présent, non testé | CalAIView.swift:727 lookup outcome; FoodSearch.swift:95 FoodSearchService.looku… |
| Scan: caméra refusée = message + Ouvrir les Réglages + saisie du code | présent, non testé | CalAIView.swift:572 |
| Objectifs, restant, anneaux, historique 7 jours | présent, non testé | CalAIView |
| Totaux du jour pour le coach | présent, test auto | CrossDomainToolsWireTests.testGetTodayNutrition_withFoodEntries_returnsAggregat… |
| Widget/coach: totaux d'AUJOURD'HUI même quand un jour passé est affic… | présent, non testé | CalAIView.swift:87 syncNutritionToContext; Lot6FoodLogTests.testTodayTotalsIgno… |
| Recherche: hors ligne / erreur serveur / aucun résultat / produits sa… | présent, non testé | FoodSearch.swift:72 classify, FoodSearch.swift:334; Lot6FoodLogTests.testSearch… |
| Ajout direct sur un jour passé (sélecteur de jour, part du jour affic… | présent, non testé | FoodSearch.swift:252, CalAIView.swift:688; Lot6FoodLogTests.testLineForPastDayL… |
| Navigation par jour (précédent/suivant, calendrier, bande qui suit le… | présent, non testé | CalAIView.swift:144 dayNavigator; Lot6FoodLogTests.testDayNavigationNeverGoesPa… |
| Récents (un geste pour rajouter la dernière portion) | présent, non testé | FoodSearch.swift:430; Lot6FoodLogTests.testRecentsAreDistinctAndMostRecentFirst… |
| Favoris (étoile, depuis un récent ou une ligne du journal; un geste p… | présent, non testé | FoodSearch.swift:454, FoodSearch.swift:574, FoodEntryEditor.swift:120; Lot6Food… |
| Aliments perso (nom, valeurs pour 100 g, micros facultatifs, portion … | présent, non testé | FoodEntryEditor.swift:168 CustomFoodEditor, FoodSearch.swift:471; Lot6FoodLogTe… |
| Repas enregistrés (depuis un repas du journal, ajout en un geste, sup… | présent, non testé | CalAIView.swift:476 saveMeal, FoodSearch.swift:492; Lot6FoodLogTests.testSavedM… |
| Copier la veille (toute la journée ou un repas) et copier un repas ve… | présent, non testé | CalAIView.swift:459, 465; Lot6FoodLogTests.testCopyPreviousDayKeepsTimeMealAndM… |
| Micronutriments fibres/sucres/sel: seulement ce qu'Open Food Facts ou… | présent, non testé | CalAIView.swift:270 microsRow, FoodEntryEditor micros fields; Lot6FoodLogTests.… |
| Mise en page iPad/Mac (colonne centrée max 760, champs sans largeur f… | présent, non testé | CalAIView.swift:56 |
| Recettes (ingrédients + portions d'un plat) | manquant | a custom food with per-100 g values covers a home dish; nothing yet builds one … |
| Santé (HealthKit) pour la nutrition | manquant |  |
| Objectifs ajustés au poids/activité, planning de repas | manquant |  |

### Cal Eye (Cal AI)
Résumé : présent, test auto 2, présent, non testé 4, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Analyse photo par le fournisseur de l'utilisateur (clé) | présent, non testé | FoodPhotoAnalyzer |
| Analyse sans clé intégrée à l'app | dépendance externe | serveur à décider par Theo (confidentialité App Store) |
| Reconnaissance sur l'appareil + valeurs Ciqual | présent, test auto | FoodRecognitionPipelineTests |
| Échec de reconnaissance : recherche proposée | présent, non testé | bouton Chercher un aliment |
| Portions corrigibles, une ligne de journal par aliment | présent, test auto | FoodLogService tests |
| Benchmark de vrais plats | présent, non testé | tools/calai-bench (12 photos), pas relancé |
| Côté journal: lignes photo modifiables avec micros, mise en favori, c… | présent, non testé | FoodEntryEditor.swift micros + Garder en favori; FoodJournal.recents/copyLines … |

### Yuko (Yuka)
Résumé : présent, test auto 12, manquant 3, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Scan = recherche : base universelle, codes normalisés | présent, test auto | ProductCatalogTests |
| Panne ≠ produit absent | présent, test auto | ProductCatalogTests (réponses mixtes) |
| Note 2.0 (Nutri-Score 2023 officiel, plafond 49) | présent, test auto | ProductScoreTests |
| Cosmétiques : liste de surveillance + annexes CosIng II/III | présent, test auto | CosmeticAnnexTests |
| Aliments chats et chiens : méthode Animaux 2.0 (FEDIAF par stade de v… | présent, test auto | PetFoodScoreTests, PetFoodRealCaseTests |
| Fiche animale incomplète : lecture des photos d’étiquette de la base … | présent, test auto | PetFoodRealCaseTests (OCR sur la vraie photo, timeout), simulateur 1er oct. (84… |
| Espèce et stade : indices combinés, choix manuel rangé sous le GTIN c… | présent, test auto | PetFoodRealCaseTests (alias, relance) |
| Relire et corriger l’étiquette (photo, OCR, validation) | présent, test auto | LifeOSTests/PetMergeOverrideTests.swift testFullJourneyFromEditorToDeletion, te… |
| Corpus réel de 50 aliments chat, fiches non résolues avec cause | présent, test auto | PetFoodCorpusTests, tools/yuko-bench/petfood/REPORT.md |
| Source fabricant / distributeur par GTIN | manquant | pages sans GTIN : association non prouvable |
| Objectifs perso et compatibilité | présent, test auto | ProductFitTests |
| Alternatives avec raisons | présent, test auto | ProductCatalogTests |
| Historique des scans, favoris, enrichissement photo local | présent, test auto | ProductStoreTests |
| Scan caméra et photo d'étiquette sur iPhone | dépendance externe | appareil réel |
| Envoi des photos à Open Beauty / Food Facts | manquant | stockage local seulement |
| Mesure de couverture des produits introuvables | manquant | failed_scans.txt vide |

### Fridgy (Fridgely)
Résumé : présent, test auto 4, présent, non testé 5, manquant 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajouter un article (quantité, catégorie, endroit, péremption), enregi… | présent, non testé | LifeOS/Modules/NutritionModule.swift:646 PantryEditor.save |
| Badge J-n / Périmé | présent, non testé | ExpiryBadge |
| Supprimer (enregistrement vérifié, alerte annulée) | présent, non testé | LifeOS/Modules/NutritionModule.swift:439 FridgeView.remove |
| Envoyer vers la liste de courses sans doublon (ajouté 30 sept.) | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests (règle) ; bouton non t… |
| Idées repas (8 recettes fixes) | présent, non testé | RecipeEngine |
| Partagé avec NoGaspi | présent, non testé | PantryItem |
| Modifier un article | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6PantryTests.testEditedItemKeepsNewValu… |
| Alertes de péremption (n jours avant, 9 h, refus affiché + Réglages) | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6PantryTests.testAlertDateIsBeforeExpir… |
| Tri / filtre par endroit ou catégorie | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6PantryTests.testFilterAndSortByExpiry … |
| Ajout par code-barres / ticket | manquant |  |

### Bringo (Bring!)
Résumé : présent, test auto 4, présent, non testé 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout avec quantité, rayon deviné | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests.testAisleGuess |
| Pas de doublon d'un article à acheter (quantités compatibles addition… | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests.testNoDuplicateOfAnIte… |
| Cocher, supprimer (enregistrement vérifié) | présent, non testé | ShoppingListView.save |
| Retirer les articles cochés (ajouté 30 sept.) | présent, non testé | ShoppingListView.clearChecked |
| Articles cochés → frigo, avec unité | présent, non testé | moveCheckedToFridge |
| Texte « génère depuis un plan repas » retiré (aucun générateur) | présent, non testé |  |
| Modifier un article (nom, quantité, unité, rayon perso, favori) | présent, non testé | LifeOS/Modules/NutritionModule.swift:932 ShoppingItemEditor |
| Unités (g, kg, ml, cl, L, paquet…) et fusion g/kg, ml/L | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6ShoppingTests.testCompatibleQuantities… |
| Suggestions : favoris puis récents, sans ce qui est déjà à acheter, r… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6ShoppingTests.testMemoryRecentsFavouri… |
| Regroupé par rayon (rayons perso inclus) | présent, non testé | ShoppingListView.groupedAisles |
| Plusieurs listes, liste partagée | dépendance externe | partage = compte en ligne (non livré) |

### WaterMind (WaterMinder)
Résumé : présent, test auto 4, présent, non testé 6, manquant 1, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout rapide 250/500/750 ml et quantité libre (1 à 3000 ml) | présent, non testé | HydrationView.add |
| Objectif réglable dans l'écran (ajouté 30 sept.) | présent, non testé | Stepper |
| Annuler / supprimer une prise | présent, non testé | HydrationView.remove |
| Modifier une prise (volume, boisson, heure), total et widget suivent | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6WaterTests.testEditedEntryChangesToday… |
| Historique 7 jours (ajouté 30 sept.) | présent, non testé | graphique |
| Rappels : autorisation demandée, refus affiché + Réglages (corrigé 30… | présent, non testé | requestAuthorization |
| Widget avec la vraie quantité du jour (corrigé 30 sept. : clé différe… | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Raccourci Siri | présent, non testé | LogWaterIntent |
| Types de boissons, part comptée réglée par l'utilisateur (100 % par d… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6WaterTests.testCountedFollowsUserPerce… |
| Objectif suggéré selon le poids (repère 30 à 35 ml/kg), seulement si … | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6WaterTests.testGoalSuggestionOnlyWithA… |
| Objectif selon l'activité | manquant | pas de règle sourcée retenue |
| Santé (eau) | dépendance externe | HealthService n'a ni type d'écriture dietaryWater ni fonction d'écriture (fichi… |

### SuppSafe (Medisafe)
Résumé : présent, test auto 4, présent, non testé 5, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout avec conseil de moment | présent, non testé | SupplementAdvisor |
| Rappels par identifiant stable, un par prise prévue, vérif « bien pri… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6SupplementTests.testOneNotificationPer… |
| Série de prises confirmées | présent, non testé | ConfirmationStore |
| Activer / pause, supprimer (notifications remplacées d'un coup, ancie… | présent, non testé | LifeOS/Modules/NutritionModule.swift:1385 SupplementScheduler.apply ; LifeOS/Mo… |
| Refus des notifications affiché + Réglages | présent, non testé | LifeOS/Modules/NutritionModule.swift:622 NotificationsDeniedNotice ; LifeOS/Mod… |
| Modifier un complément (nom, dose, heures, jours, stock) | présent, non testé | LifeOS/Modules/NutritionModule.swift:1703 SupplementEditor |
| Dose, stock, réassort (jours restants, rappel) | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6SupplementTests.testStockRefillAndAdhe… |
| Plusieurs prises / jours choisis | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6SupplementTests.testTimesParsingAndLeg… |
| Historique des prises (prise / sautée, 14 jours, taux), nom gardé apr… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6SupplementTests.testHistoryKeepsNameAf… |
| Interactions avec les médicaments (source réelle) | dépendance externe | base de données médicaments |

### Figue (Fig)
Résumé : présent, test auto 6, présent, non testé 2, manquant 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| 16 régimes et allergènes (dont 8 allergènes majeurs UE, ajoutés 30 se… | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testEUMajorAllergensAn… |
| Casher avec règles (corrigé 30 sept. : aucune règle avant) | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testKosherHasRules |
| Expressions sans risque ignorées (noix de coco, lait d'amande) | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testHarmlessPhrasesAre… |
| Résultat honnête : « aucun mot à risque trouvé », pas « compatible » | présent, non testé | DietProfileView |
| Profil appliqué aux produits scannés Yuko | présent, non testé | Yuko.swift |
| Profil appliqué au journal Yumzio (lecture seule : ajout de repas et … | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6DietTests.testJournalEntriesAreFlagged… |
| Allergènes perso et gravité | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6DietTests.testPersonalAllergenWithSeve… |
| Traces possibles / contamination croisée (texte « peut contenir », si… | présent, test auto | LifeOSTests/Lot6NutritionTests.swift Lot6DietTests.testMayContainIsATraceNotAnI… |
| Plusieurs profils (famille) | manquant |  |

## 💪 Sport


### Fitbot (Fitbod)
Résumé : présent, test auto 25, présent, non testé 3, manquant 2, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Semaine éditable (séance, exercices, remplacement) | présent, non testé | GymProgram.swift:344 GymDayEditor (menu de remplaçants, ajout par groupe, exclu… |
| Démarrer une séance, prescription figée au démarrage | présent, test auto | LifeOSTests/Build48DefectTests.swift testPrescriptionIsFrozenWhenTheSessionStar… |
| Progression depuis les séances TERMINÉES seulement | présent, test auto | LifeOSTests/Build48DefectTests.swift testUnfinishedOrCancelledSessionIsNotABase |
| Deux séances le même jour restent séparées | présent, test auto | LifeOSTests/Build48DefectTests.swift testTwoSessionsTheSameDayStaySeparate (con… |
| Séries typées échauffement / travail / dégressive | présent, test auto | LifeOSTests/Build48DefectTests.swift testWarmupAndDropSetsDoNotCount |
| Sauvegarde : erreur affichée, saisie gardée, aucune série fantôme | présent, test auto | LifeOSTests/Build48DefectTests.swift GymSessionSaveTests |
| Terminer / annuler (garder ou effacer les séries) | présent, test auto | LifeOSTests/Build48DefectTests.swift testFailedFinishLeavesSessionActive, testC… |
| Minuteur de repos réglable (et réglé selon l'objectif du programme, a… | présent, non testé | GymSession.swift; GymProgram.swift:525 FitbotGeneratorSheet toggle « Régler le … |
| Record personnel signalé | présent, test auto | LifeOSTests/Build48DefectTests.swift testPersonalRecordAgainstFinishedHistory |
| Alerte récupération < 48 h (séance du même jour comprise) | présent, test auto | LifeOSTests/Build48DefectTests.swift testRecoverySeesAnEarlierSessionToday (con… |
| Volume hebdo par muscle (séries de travail) | présent, test auto | StrengthProgressionTests |
| Cibles en fourchette (3×8-12), cible par défaut, pas de charge réglab… | présent, test auto | LifeOSTests/Build48DefectTests.swift testTargetRangesDefaultTargetAndMinIncreme… |
| Démonstrations d'exercices | dépendance externe | contenu absent : une démonstration (vidéo ou image, licence claire) par exercic… |
| Filtre matériel disponible (salle, haltères, poids du corps, élastiqu… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testRestrictedEquipmentNeverProposesAGymOnlyE… |
| Remplacement : même groupe musculaire, liste des remplaçants faisables | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testSubstitutionKeepsTheMuscleGroupAndRespect… |
| Exercice exclu ne revient jamais (ajout, remplacement, programme géné… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testExcludedExercisesNeverReappear; GymProgra… |
| Supersets dans le programme (paire stockée sur GymDay, voisins, netto… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift FitbotSupersetTests; GymDay.supersetsJSON |
| Supersets enchaînés dans l'écran de séance (sans repos entre les deux) | manquant | hook dans GymSessionService/GymSession non modifiables, voir notDone |
| Générateur de programme selon objectif, fréquence 2 à 6, durée, matér… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testSplitFollowsFrequency, testGoalSetsTarget… |
| Aperçu avant de remplacer la semaine, puis annulation (même après rel… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testApplyWritesIntoTheSameDaysAndUndoRestores… |
| Échec d'enregistrement du programme : semaine inchangée, aucun progra… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testFailedSaveLeavesTheWeekUntouched, testUnu… |
| Historique par semaine de programme (semaine N, séances faites / prév… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift FitbotHistoryTests; UI GymProgram.swift:180 h… |
| Programme généré → séance → prochaine charge depuis l'historique réel… | présent, test auto | LifeOSTests/Lot6FitbotTests.swift testGeneratedDayRunsAsASessionAndNewProgramme… |
| Questionnaire Sport & fitness sur le même générateur (matériel, durée… | présent, non testé | FitnessSetup.swift:114 generated |
| Parcours complet sur iPhone / iPad / Mac | manquant | non fait (pas de simulateur dans ce lot) ; écrans en Form, aucune largeur fixe … |
| Séance liée au jour de programme par identifiant, pas par titre (corr… | présent, test auto | LifeOSTests/Build49DefectTests.swift GymSessionLinkTests |
| Liste d'exercices figée pendant la séance (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testEditingTheProgrammeDoesNotChangeTheRun… |
| Reprise par identifiant, même le lendemain (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testResumeTheNextDayAfterARestDay |
| Repos gardé dans la séance, notification de fin (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testRestEndIsStoredInTheSession |
| Un seul parseur de libellé, noms historiques migrés (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift ExerciseLabelTests, testMigrationGivesHist… |
| Suppression isolée, sans rollback global (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testFailedDeleteKeepsOtherPendingChanges |

### Stepometer (Pedometer++)
Résumé : présent, test auto 3, présent, non testé 4, manquant 1, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Pas du jour lus dans Apple Santé | dépendance externe | HealthService.stepsToday ; données réelles sur appareil |
| Anneau vers l'objectif, objectif réglable et gardé | présent, non testé | FitnessModule.swift StepsView |
| Historique 7 / 30 / 90 jours (sélecteur), moyenne, objectif atteint x… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testStepSummaryAndBestDay ; FitnessModule.sw… |
| Record (plus haut jour vu par LifeOS), gardé même hors de la fenêtre … | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testStepRecordKeepsHighestEverSeen ; StepsVi… |
| Notification d'objectif atteint, une par jour, quand l'app voit l'obj… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testGoalNotificationOncePerDay ; StepsView.g… |
| Tirer pour rafraîchir | présent, non testé | .refreshable -> load(fresh: true) |
| Refus d'accès Santé : réessayer + Réglages | présent, non testé | StepsView EmptyState |
| Distance et kcal | présent, non testé | estimations fixes, sans taille ni poids, marquées approx. |
| Distance réelle, étages, calories actives de Santé | dépendance externe | HealthService ne lit ni distanceWalkingRunning ni flightsClimbed (readTypes) ; … |
| Widget de pas | manquant |  |
| Notification en arrière-plan (sans ouvrir l'app) | dépendance externe | demande HKObserverQuery + background delivery dans HealthService |
| Apple Watch | dépendance externe | pas de cible watchOS |

### Hevvy (Strong / Hevy)
Résumé : présent, test auto 5, présent, non testé 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Logger une série (type, charge, reps, effort) | présent, non testé | FitnessModule.swift WorkoutEditor |
| Corriger une série existante | présent, non testé | toucher une ligne ; pas de test d'écran |
| Suppression avec erreur visible | présent, non testé | GymSessionService.delete |
| Courbe 1RM par exercice | présent, non testé | ProgressChartCard |
| Conseil de prochaine charge (moteur partagé, séances terminées) | présent, test auto | StrengthProgressionTests |
| Records par exercice (avec groupe musculaire) | présent, non testé | StrengthView section Records + ExerciseLibrary.group |
| Routines réutilisables | présent, non testé | via le programme Fitbot (GymDay), pas de routine propre à Hevvy |
| Exercices perso avec groupe musculaire et matériel (créer, modifier, … | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testCustomExerciseNameValidation, testRenami… |
| Bibliothèque : catalogue existant par groupe + exercices perso, reche… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testSuggestionsMergeCustomAndLoggedWithoutDu… |
| Mensurations (poids, masse grasse, cou, épaules, poitrine, taille, ha… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testUnitConversionsRoundTripAndRefuseMismatc… |
| Reprendre le dernier poids d'Apple Santé dans une mesure | présent, non testé | MeasurementEditor.importWeight (HealthService.latestBodyMass) |
| Export CSV des séries (ShareLink) | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testCSVExportEscapesAndOrdersRows ; Strength… |
| Démonstrations vidéo des exercices | dépendance externe | contenu vidéo/animation original ou sous licence ; l'écran le dit |

### TabaTime (Tabata Timer)
Résumé : présent, test auto 10, présent, non testé 4, manquant 1, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Séquence complète préparation / effort / repos / cycles / retour au c… | présent, test auto | TabataSessionTests.testSequenceCoversWholeSessionInOrder |
| Réglages des intervalles persistants | présent, non testé | TabataView @AppStorage |
| 5 séances préréglées + séances du programme Sport | présent, non testé | TabataPresets, programSessions |
| Pause / reprise | présent, test auto | TabataCatchUpTests.testPausedEngineIgnoresElapsedTime |
| Étape suivante / précédente, saut sans compter l'effort | présent, test auto | TabataSessionTests.testSkipForwardToEndDoesNotCompleteAnything |
| Rattrapage arrière-plan / écran verrouillé | présent, test auto | TabataCatchUpTests.testCatchesUpAfterBackgroundGap |
| Reprise après relance | présent, test auto | TabataSessionTests.testPausedSessionResumesWhereItStoppedAfterRelaunch |
| Écriture Santé une seule fois, réessai | présent, test auto | TabataSessionTests.testHealthWrittenOnceEvenAfterRestore |
| Bouton Réessayer si Santé échoue | présent, non testé | TabataView |
| Bips, coupure du son, son en arrière-plan, écran allumé | présent, non testé | TabataSound, UIBackgroundModes audio |
| Widget Tabata avec tes vrais réglages | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Préréglages perso nommés (créer depuis les réglages actuels, modifier… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataPresetRulesAndRoundTrip ; TabataVi… |
| Historique des séances (efforts faits / total, durée active, date), u… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataLogNeedsRealEffortAndNamesFreeInte… |
| Séances Tabata comptées dans Streakz | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataAndMobilityDaysCountAsActive |
| Annonces vocales / Live Activity | manquant |  |
| Écriture Santé réelle sur appareil | dépendance externe | HealthKit sur iPhone |

### GOMOB (GOWOD / Pliability)
Résumé : présent, test auto 5, présent, non testé 5, dépendance externe 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| 3 routines de mobilité intégrées (identifiants stables) | présent, non testé | FitnessModule.swift MobilityRoutineView.builtIn |
| Séance guidée, minuteur par exercice, enchaînement | présent, non testé | GuidedStretchView |
| Moteur de compte à rebours sur l'horloge | présent, test auto | CountdownEngineTests |
| Minuteur séparé du minuteur de focus | présent, non testé | CountdownEngine(key: "mobility") |
| Pause / reprise dans la séance | présent, non testé | GuidedStretchView.togglePause (engine.pause/resume) |
| Reprise après relance à l'exercice en cours (y compris exercice fini … | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testMobilityResumePointAfterRelaunch, testMo… |
| Son entre exercices (son système, suit le bouton silencieux), réglable | présent, non testé | GuidedStretchView.advance AudioServicesPlaySystemSound ; @AppStorage mobility.s… |
| Routines perso (créer, modifier, supprimer, étapes ordonnées avec dur… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testMobilityRoutineValidationAndReorder, tes… |
| Historique des séances (une fois par tentative, durée réellement fait… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testSessionsAreRecordedOncePerRun ; GuidedSt… |
| Écriture Santé de la séance de mobilité | dépendance externe | HealthService.WorkoutKind n'a que strength/hiit ; il faut un cas flexibility (f… |
| Démonstrations (vidéo / animation) | dépendance externe | contenu vidéo original ou sous licence |
| Évaluation de mobilité / programme adaptatif | dépendance externe | bibliothèque de mouvements structurée et tests d'évaluation validés |
| Prise en compte dans Streakz | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataAndMobilityDaysCountAsActive |

### Streakz (Streaks)
Résumé : présent, test auto 6, présent, non testé 1, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Série en semaines selon un objectif hebdo réglable (1 à 7 jours) : le… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testWeeklyTargetKeepsStreakOverRestDays ; St… |
| Série de jours consécutifs | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataAndMobilityDaysCountAsActive |
| Meilleure série (jours et semaines) | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testBestDayStreak, testWeeklyTargetKeepsStre… |
| Muscu, Tabata et mobilité comptés (avant : séries muscu seules) | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testTabataAndMobilityDaysCountAsActive |
| Calendrier / heatmap 18 semaines, lundi en haut, intensité = types d'… | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testHeatmapShapeMondayFirstAndFutureFlag ; S… |
| Rappel quotidien à l'heure choisie, refus montré + Réglages | présent, test auto | LifeOSTests/Lot6FitnessTests.swift testReminderComponents ; StreaksView.schedul… |
| Jours actifs, compteurs par type | présent, non testé | StreaksView |
| Santé comptée (workouts d'autres apps) | manquant | HealthService.workoutsThisWeek ne donne qu'un total, pas les dates |
| Habitudes perso (moteur Habitly partagé) | manquant | Habitly existe, pas relié |
| Widget de série | manquant |  |

## ✨ Apparence


### Umaxx (Umax)
Résumé : présent, test auto 6, présent, non testé 3, manquant 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Détection des points du visage (Vision, sur l'appareil) | présent, non testé | FaceAnalysis.swift:21 FaceAnalyzer.analyze (VNDetectFaceLandmarksRequest); test… |
| Écart de symétrie compensé pour la tête penchée | présent, test auto | LifeOSTests/FaceGeometryTests.swift testHeadTiltIsNotAsymmetry |
| Contrôle de pose: refus si tête tournée > 12° | présent, test auto | LifeOSTests/FaceGeometryTests.swift testTurnedHeadIsNotMeasured |
| Pas de mesure sans axe médian détecté | présent, test auto | LifeOSTests/FaceGeometryTests.swift testNoAxisMeansNoNumber |
| Ratios: écartement des yeux, tiers, FWHR | présent, test auto | LifeOSTests/FaceGeometryTests.swift testRatiosDoNotChangeWithTilt |
| Mesures expliquées, sans note de beauté | présent, test auto | LifeOSTests/FaceGeometryTests.swift testMetricTextMakesNoBeautyClaim |
| Reprendre / changer de photo | présent, non testé | FaceAnalysis.swift:143 PhotosPicker 'Changer de photo', run() resets results Fa… |
| Glisser-déposer un portrait (Mac) | présent, non testé | FaceAnalysis.swift:159 onDesktopImageDrop |
| Guidage de capture (caméra, gabarit de cadrage) | manquant | no AVCaptureSession / camera in FaceAnalysis.swift; only PhotosPicker + fileImp… |
| Contrôle lumière / netteté / expression | manquant | grep 'brightness/blur/smile/exposure' in FaceAnalysis.swift and Services/FaceGe… |
| Analyses sauvegardées et datées, comparaison dans le temps | manquant | metrics held in @State only FaceAnalysis.swift:111; no SwiftData model for face… |
| Export / suppression des résultats par l'utilisateur | manquant | nothing is persisted, no ShareLink/export in FaceAnalysis.swift |
| Plans et suivi de progression façon Umax | manquant | grep 'plan/programme/progress' in FaceAnalysis.swift 0 hits |
| Fichier illisible ou photo non chargée signalé comme tel (pas « aucun… | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testFileErrorsDoNotBlameTheFace (FaceAnal… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `FaceAnalysis.swift:169` : When a Finder file cannot be read (and on importer failure line 171) the screen says 'Aucun visage net détecté', blaming the face for a file error.
- [corrigé] `FaceAnalysis.swift:177` : If loadTransferable fails on iOS nothing happens and no message is shown: the user tapped a photo and gets silence.

### TrueSkin (TroveSkin)
Résumé : présent, test auto 2, présent, non testé 3, manquant 8, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Profil peau en 3 étapes (type, préoccupations, traitement) | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testSavedProfileRoundTripsThroughTheEdito… |
| Routine matin / soir générée selon le profil | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testEveryConcernChangesTheRoutine, testTr… |
| Étapes numérotées dans un ordre fixe | présent, non testé | LooksModule.swift:125 routineCard (order comes from engine, not editable) |
| Modifier / réordonner les étapes de routine | manquant | amRaw/pmRaw (LooksModule.swift:12-13) are defaults never written by any screen;… |
| Cocher la routine faite aujourd'hui | présent, non testé | LooksModule.swift:52 doneAMDate/donePMDate (only last date kept, no history) |
| Rappels matin 8h et soir 22h | présent, non testé | LooksModule.swift:57 Toggle -> NotificationManager.scheduleDaily (hours fixed) |
| Catalogue structuré de produits et ingrédients | manquant | no product model in LooksModule.swift; grep 'ingredient/ingrédient/SkinProduct'… |
| Suivi d'usage et date d'expiration (PAO) des produits | manquant | grep 'expir/PAO/opened' in LooksModule.swift 0 hits |
| Planning par jour (ex. rétinol 2×/semaine) | manquant | frequency only appears as text inside a step label LooksModule.swift:168-169; n… |
| Historique / série de routines faites | manquant | done state is a single date string per slot LooksModule.swift:15-16 |
| Journal de peau | manquant | grep 'journal/diary' in LooksModule.swift 0 hits |
| Comparaison photo de la peau à conditions constantes | manquant | only a NavigationLink to the generic photo grid LooksModule.swift:69; no side-b… |
| Suivi des déclencheurs possibles | manquant | grep 'trigger/déclencheur' in LooksModule.swift 0 hits |
| Compatibilité entre produits (règles sourcées) | dépendance externe | needs a sourced ingredient interaction rule set (dermatology source/licence); n… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `LooksModule.swift:184` : Profile editor state starts empty (selectedType, concerns, treatment) instead of the saved profile, so 'Modifier' then save wipes previous concerns and treatme…
- [corrigé] `LooksModule.swift:139` : Concerns 'rides', 'pores', 'teint terne', 'rougeurs' and the saved treatment name (skinTreatment, line 306) are never read by SkinRoutineEngine: the user's cho…
- [corrigé] `LooksModule.swift:61` : Reminder text is hardcoded 'Nettoyant + sérum + SPF' even when the generated routine is different (e.g. micellar water for sensitive skin).

### Progrez (Progress)
Résumé : présent, test auto 3, présent, non testé 4, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'une photo depuis la photothèque | présent, non testé | LooksModule.swift:352 PhotoPickerButton -> ProgressPhoto |
| Stockage local des fichiers photo | présent, test auto | LifeOSTests/ImageStoreTests.swift testSaveLoadRoundtrip |
| Grille datée, la plus récente d'abord | présent, non testé | LooksModule.swift:322 @Query sort date reverse |
| Suppression d'une photo (fiche + fichier) | présent, non testé | LooksModule.swift:344 contextMenu; ImageStore.delete covered by LifeOSTests/Ima… |
| Sauvegarde complète (photos incluses dans Documents) | présent, test auto | LifeOSTests/FullBackupTests.swift testBackupThenRestoreRebuildsEverything (gene… |
| Catégorie Visage / Peau / Corps | présent, non testé | Picker Catégorie à l'ajout LooksModule.swift:456 (insert :419 avec la catégorie… |
| Comparaison côte à côte / curseur avant-après | manquant | grep 'slider/compare/comparaison' in LooksModule.swift 0 hits |
| Guide de pose / calque d'alignement | manquant | no camera capture or overlay in ProgressPhotoGalleryView LooksModule.swift:320 |
| Mesures corporelles liées aux photos | manquant | ProgressPhoto has only date/filename/category/note Models_Life.swift:7 |
| Note par photo | manquant | ProgressPhoto.note never set or shown in LooksModule.swift |
| Chronologie / timelapse | manquant | no timeline view; grid only LooksModule.swift:332 |
| Album privé verrouillé | manquant | grep 'LAContext/FaceID' in LooksModule.swift 0 hits |
| Export / partage d'une photo | manquant | no ShareLink or export in ProgressPhotoGalleryView |
| Ouvrir une photo en plein écran | manquant | grid cells have no tap action LooksModule.swift:333-345 |
| Date de prise de vue lue dans l'EXIF (repli date d'import, date futur… | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testCaptureDateIsReadFromPhotoMetadata, t… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LooksModule.swift:352` : Every photo is saved with category default 'Visage' (shown on the tile, line 341) and date = import time, so body photos are mislabelled and older photos get t…

### Mewing Klub (Mewing Club)
Résumé : présent, test auto 1, présent, non testé 3, manquant 7

| Fonctionnalité | État | Preuve |
|---|---|---|
| Consigne de posture (texte) | présent, non testé | LooksModule.swift:371 |
| Minuteur de séance qui survit à la fermeture | présent, test auto | LifeOSTests/CountdownEngineTests.swift testSessionSurvivesProcessRestart (Count… |
| Démarrer / arrêter une séance de 3 min | présent, non testé | LooksModule.swift:377 |
| Durée de séance réglable | manquant | hardcoded engine.start(seconds: 180) LooksModule.swift:378 |
| Rappels posture toutes les 2 h (9h-19h) | présent, non testé | LooksModule.swift:384 |
| Horaires de rappel personnalisables | manquant | fixed stride(from: 9, through: 19, by: 2) LooksModule.swift:387 |
| Séances guidées multi-étapes / exercices | manquant | single timer, no exercise list in MewingPostureView LooksModule.swift:359 |
| Illustrations / vidéos d'instruction | manquant | no image or video asset referenced in MewingPostureView |
| Historique des séances | manquant | onFinish only resets 'started' LooksModule.swift:378; nothing saved |
| Progression / niveaux | manquant | grep 'level/niveau' in LooksModule.swift 0 hits |
| Statistiques de complétion / série | manquant | no session record exists to compute them |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LooksModule.swift:362` : 'started' is local @State while CountdownEngine restores a running timer: reopening the screen shows 'Démarrer' over a running dial, onFinish is nil, and tappi…

### Wearing (Whering / Acloset)
Résumé : présent, non testé 4, manquant 8, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'une pièce (nom, catégorie, couleur, chaleur, photo) | présent, non testé | LooksModule.swift:474 WardrobeEditor |
| Grille de la garde-robe | présent, non testé | LooksModule.swift:438 |
| Suppression d'une pièce et de sa photo | présent, non testé | LooksModule.swift:444 |
| Tenue du jour selon le niveau de chaleur choisi | présent, non testé | LooksModule.swift:459 OutfitEngine.suggest; grep OutfitEngine LifeOSTests 0 hits |
| Météo réelle / localisation | dépendance externe | needs WeatherKit entitlement or a weather API; today the user picks Froid/Doux/… |
| Détourage automatique (fond retiré) | manquant | grep 'VNGenerateForegroundInstanceMask/removeBackground' in LooksModule.swift 0… |
| Recherche / tags / filtres | manquant | WardrobeItem has no tags Models_Life.swift:17; no searchable in WardrobeView |
| Modifier une pièce | manquant | WardrobeEditor only inserts LooksModule.swift:495; no edit path |
| Tenues enregistrées et calendrier | manquant | no Outfit model; grep 'Outfit' only OutfitEngine |
| Historique de port / coût par port | manquant | WardrobeItem has no price or wear-count fields Models_Life.swift:17-26 |
| Valise / capsule | manquant | grep 'capsule/valise/packing' 0 hits |
| Accessoires dans la tenue proposée | manquant | OutfitEngine iterates only Haut/Bas/Chaussures/Veste LooksModule.swift:463 |
| Proposer une autre tenue | manquant | OutfitEngine picks the deterministic min LooksModule.swift:467; no shuffle/rege… |
| Inspiration / partage | dépendance externe | needs a social/sharing backend |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LooksModule.swift:487` : The photo file is written as soon as it is picked; tapping Annuler (line 493) never deletes it, leaving orphan files in Documents.

## 🧠 Mental


### Breathwerk (Breathwrk)
Résumé : présent, non testé 4, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| 3 techniques: Box 4-4-4-4, Cohérence 5-5, 4-7-8 | présent, non testé | MindModule.swift:12 Pattern |
| Durée de séance 1 à 20 min | présent, non testé | MindModule.swift:44 Stepper |
| Cercle animé + libellé de phase | présent, non testé | MindModule.swift:46-52 |
| Vibration à chaque changement de phase | présent, non testé | MindModule.swift:78 Haptics.tap() |
| Bibliothèque recherchable / programmes | manquant | 3 hardcoded enum cases MindModule.swift:13-15; no search |
| Phases et rondes configurables | manquant | phases hardcoded in Pattern.phases MindModule.swift:18 |
| Guidage audio / voix | manquant | grep 'AVSpeech/AVAudio' in MindModule.swift 0 hits |
| Historique des séances | manquant | stop() saves nothing MindModule.swift:72 |
| Rappels | manquant | grep scheduleDaily in BreathingView 0 hits |
| Favoris | manquant | grep 'favori' in MindModule.swift 0 hits |
| Progression / statistiques | manquant | no session record exists |
| Respect de 'Réduire les animations' | manquant | grep accessibilityReduceMotion in MindModule.swift 0 hits; scale animation alwa… |

### Headplace (Headspace / Calm)
Résumé : présent, test auto 2, présent, non testé 1, manquant 7, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Minuteur de méditation basé sur l'horloge | présent, test auto | LifeOSTests/CountdownEngineTests.swift testRemainingIsDerivedFromTheClockNotACo… |
| Choix de durée 3/5/10/15/20 min | présent, non testé | MindModule.swift:98 |
| Notification de fin de séance | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testMeditationEndAlertIsScheduledForTheRe… |
| Méditations guidées audio | dépendance externe | needs a licensed narrated content catalogue; none in repo |
| Programmes / parcours | dépendance externe | needs content catalogue |
| Histoires du soir | dépendance externe | needs licensed sleep story catalogue |
| Musique | dépendance externe | needs licensed music catalogue |
| Recherche par thème / niveau / durée | manquant | no catalogue, no search in MeditationView MindModule.swift:89 |
| Métadonnées narrateur / langue | manquant | no content model |
| Favoris | manquant | grep 'favori' in MindModule.swift 0 hits |
| Téléchargements hors ligne / reprise de lecture | manquant | no audio playback in MeditationView |
| Recommandation du jour | manquant | grep 'recommand' in MindModule.swift 0 hits |
| Historique / progression / série | manquant | onFinish saves nothing MindModule.swift:106 |
| Cloche de début / fin | manquant | no AVAudio in MindModule.swift; only a notification |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MindModule.swift:92` : Same restore mismatch as Mewing: after leaving and returning, 'started' is false while the engine runs, onFinish is nil so the end is never handled.
- [corrigé] `MindModule.swift:106` : The 'Séance terminée' notification is scheduled inside onFinish, which only runs from the in-app 1 s timer; with the phone locked no end signal is ever deliver…

### Endlo (Endel)
Résumé : présent, test auto 1, présent, non testé 6, manquant 7

| Fonctionnalité | État | Preuve |
|---|---|---|
| 4 sons générés sur l'appareil (blanc, rose, brun, océan) | présent, non testé | Soundscape.swift:58 NoiseEngine.nextSample; grep NoiseEngine LifeOSTests 0 hits |
| Volume | présent, non testé | Soundscape.swift:257 Slider -> NoiseEngine.volume Soundscape.swift:40 |
| Minuteur de sommeil 15/30/45/60 min | présent, non testé | Soundscape.swift:283 armTimer |
| Changer de son sans couper | présent, non testé | Soundscape.swift:133 |
| Lecture écran verrouillé | présent, non testé | Soundscape.swift:94 category .playback + Info.plist UIBackgroundModes audio |
| Message si l'audio échoue | présent, non testé | Soundscape.swift:171 errorCard |
| Lecture persistante en quittant l'écran | manquant | onDisappear stops the sound Soundscape.swift:168 |
| Mix par mode (focus, sommeil, détente) à plusieurs couches | manquant | one NoiseKind at a time Soundscape.swift:41 |
| Fondus d'entrée / de sortie | manquant | stop() calls engine.stop() at once Soundscape.swift:125 |
| Programmation de séances | manquant | grep 'schedule' in Soundscape.swift 0 hits |
| Préréglages enregistrés | manquant | selected/volume/timer are @State only Soundscape.swift:143-147 |
| Entrées adaptatives (heure, activité, rythme) | manquant | grep 'Calendar/CMMotion/HealthKit' in Soundscape.swift 0 hits |
| Contrôles 'À l'écoute' / écran verrouillé | manquant | grep MPNowPlayingInfoCenter/MPRemoteCommandCenter in LifeOS 0 hits |
| Gestion des interruptions audio (appel) | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testCallWhilePlayingPausesHonestly, testE… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `Soundscape.swift:89` : No AVAudioSession interruption observer: after a call the system stops the engine but isPlaying stays true, so the UI shows playing while silent and the sleep …
- [corrigé] `Soundscape.swift:102` : The real-time render block reads self.kind and mutates filter state while the main thread writes kind (toggle line 133) with no synchronization: a data race on…

### Daylia (Daylio)
Résumé : présent, test auto 1, présent, non testé 6, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| Humeur 1-5 + note + gratitude | présent, non testé | MindModule.swift:136-149 MoodJournalView |
| Plusieurs entrées par jour | présent, non testé | MindModule.swift:147 inserts a new MoodEntry each save |
| Historique (20 dernières) + humeur moyenne | présent, non testé | MindModule.swift:170-171 |
| Supprimer une entrée | présent, non testé | MindModule.swift:180 |
| Saisie par Siri / Raccourcis | présent, non testé | LifeOSIntents.swift:105 LogMoodIntent |
| Export JSON des humeurs | présent, non testé | DataExporter.swift:26, reached via ProfileView.swift:309 DataExportSheet |
| Sauvegarde complète restaurable | présent, test auto | LifeOSTests/FullBackupTests.swift testBackupThenRestoreRebuildsEverything (gene… |
| Humeurs et activités personnalisées | manquant | MoodEntry has only date/score/note/gratitude Models_Life.swift:30-37 |
| Tags / photos | manquant | no tag or photo field on MoodEntry |
| Modifier une entrée passée / choisir la date | manquant | no edit view; new entries always date .now MindModule.swift:147 |
| Rappels quotidiens | manquant | grep 'scheduleDaily' with mood/humeur id in LifeOS 0 hits |
| Vue calendrier / année | manquant | grep 'calendar/year' in MoodJournalView 0 hits; list only |
| Filtres / recherche | manquant | no searchable/filter in MoodJournalView |
| Corrélations activité ↔ humeur | manquant | no activity data; LifeBrain only computes a 3-day mood average Core/LifeBrain.s… |
| Objectifs | manquant | grep 'goal/objectif' in MoodJournalView 0 hits |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MindModule.swift:160` : Empty state promises trends (weekday peaks, links with habits or sleep) that no code computes anywhere.
- [corrigé] `MindModule.swift:180` : One tap on the trash icon deletes an entry with no confirmation or undo.

### Opale (Opal / one sec)
Résumé : présent, test auto 1, présent, non testé 2, manquant 1, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Autorisation Temps d'écran | dépendance externe | droit Family Controls (distribution) à demander par Theo |
| Choix des apps et catégories à bloquer | dépendance externe | code prêt (FamilyActivityPicker), non exécutable sans le droit |
| Blocage immédiat pour une durée | dépendance externe | code prêt (ManagedSettings) |
| Fin du blocage appliquée par l'app, quel que soit l'écran | présent, test auto | LifeOSTests/Build48DefectTests.swift ScreenBlockExpiryTests |
| Notification à l'heure de fin | présent, non testé | NotificationManager.schedule |
| Fin en arrière-plan, app fermée (extension DeviceActivity) | dépendance externe | Extensions/LifeOSDeviceActivity préparée, hors build |
| Rapports d'usage (DeviceActivityReport) | manquant |  |
| Suivi manuel du temps d'écran | présent, non testé | MindModule.swift |

### Fabuleux (Fabulous)
Résumé : présent, test auto 1, présent, non testé 2, manquant 10

| Fonctionnalité | État | Preuve |
|---|---|---|
| Date + citation du jour | présent, non testé | MindModule.swift:263 (5 fixed quotes, rotated by day of month) |
| Priorités du jour tirées des vraies tâches | présent, test auto | LifeOSTests/AuditFixesMindTests.swift testRecurringAndOverdueTasksAppearInToday… |
| Rituel de démarrage | présent, non testé | MindModule.swift:283-288 (3 static labels, not checkable) |
| Agenda du jour (événements) | manquant | @Query events MindModule.swift:255 is never displayed |
| Un seul chemin de briefing | manquant | MorningBriefingView MindModule.swift:253 and Core/DailyBriefingView.swift:4 are… |
| Briefing lu à voix haute | manquant | no speech in MorningBriefingView; audio only exists in the other path DailyBrie… |
| Routines structurées cochables | manquant | ritual steps are plain Label views MindModule.swift:285-287 |
| Onboarding / parcours (journeys) | manquant | grep 'journey/parcours' in MindModule.swift 0 hits |
| Empilement d'habitudes | manquant | no link to Habit in MorningBriefingView |
| Programmes coachés | manquant | no programme content in MindModule.swift |
| Réflexion / bilan | manquant | no reflection input in MorningBriefingView (EveningSummaryView exists separatel… |
| Progression / séries | manquant | nothing recorded by this view |
| Préférences du briefing modifiables | manquant | no settings or AppStorage in MorningBriefingView |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `MindModule.swift:264` : Only tasks due today are shown: recurring tasks (due nil + recurringDays) and overdue tasks never appear, although TodoItem.applies(to:) exists (Models_Life.sw…

## ✅ Productivité


### Todoo (Todoist / Things)
Résumé : présent, test auto 3, présent, non testé 4, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer une tâche (titre, projet, priorité, échéance) | présent, non testé | ProductivityModule.swift:183 TodoEditor insert |
| Cocher et supprimer une tâche | présent, non testé | ProductivityModule.swift:38 toggle, :78 et :85 delete |
| Tri par priorité puis échéance | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testTodoSortPutsNearestDueFirstAt… |
| Filtre À faire / Toutes | présent, non testé | ProductivityModule.swift:29 |
| Modifier une tâche existante | manquant | TodoEditor ne fait qu'insérer (ProductivityModule.swift:183), aucune ouverture … |
| Projets imbriqués et sections | manquant | project est une simple String (Models_Life.swift:48), aucun modèle Project/Sect… |
| Sous-tâches / checklist | manquant | aucun champ parent ou checklist sur TodoItem (Models_Life.swift:42) |
| Étiquettes, filtres, recherche | manquant | pas de .searchable ni de tags dans TodoView (ProductivityModule.swift:13-102) |
| Vues Boîte de réception / Aujourd'hui / À venir | manquant | TodoView n'a que À faire/Toutes; seules les tâches datées du jour apparaissent … |
| Saisie en langage naturel (dates, priorité dans le texte) | manquant | Siri (LifeOSIntents.swift:131) et coach (IntentExecutor.swift:256) créent une t… |
| Récurrence par jours de semaine | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testCheckingRecurringTodoRollsToN… |
| Rappel de tâche | présent, non testé | seulement via l'ajout rapide AddAnythingSheet.swift:362 scheduleReminder; l'édi… |
| Ajout au calendrier | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testCalendarAddIsDeduplicated (Pr… |
| Dépendances entre tâches | manquant | aucun champ de dépendance sur TodoItem |
| Collaboration / partage | dépendance externe | nécessite comptes et serveur de synchronisation, inexistants |

Défauts trouvés en lisant le code (2 corrigés sur 3) :

- [corrigé] `ProductivityModule.swift:22` : Le tri trie le tuple (priorité, échéance) en ordre décroissant: à priorité égale, l'échéance la plus lointaine passe en premier et les tâches sans date (distan…
- [corrigé] `ProductivityModule.swift:38` : Une tâche récurrente n'a qu'un seul booléen done (Models_Life.swift:46): la cocher une fois la cache pour toujours, la récurrence ne la rouvre jamais; et la fr…
- [partiel] `ProductivityModule.swift:105` : Chaque Ajouter au calendrier crée un nouvel EKEvent sans garder son identifiant: doublons à chaque appui, et changer la tâche ne met jamais l'événement à jour. (reste : doublon évité ; mettre à jour l'ancien événement demande l'accès complet au calendrier)

### Structurd (Structured)
Résumé : présent, non testé 9, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Générer la journée en créneaux d'1 h par priorité | présent, non testé | ProductivityModule.swift:399 generate() |
| Bornes de journée réglables | présent, non testé | ProductivityModule.swift:337 steppers dayStart/dayEnd |
| Pause déjeuner sautée | présent, non testé | ProductivityModule.swift:420 (13 h fixe) |
| Créneaux enregistrés sur la tâche et rechargés | présent, non testé | ProductivityModule.swift:424 écriture blockStart/blockEnd, :391 loadSavedBlocks |
| Débordement explicite (tâches sans créneau) | présent, non testé | ProductivityModule.swift:438 message |
| Planifier demain si la journée est finie | présent, non testé | ProductivityModule.swift:410 |
| Créneaux visibles sur la frise 24 h | présent, non testé | HabitTrackerTimelineView.swift:123 blockStart |
| Durée estimée par tâche | manquant | durée fixe 1 h ProductivityModule.swift:423, aucun champ durée sur TodoItem |
| Échéances et priorités combinées | présent, non testé | generate trie priorité puis échéance la plus proche ProductivityModule.swift:62… |
| Import des plages occupées du calendrier | manquant | EventKit utilisé en écriture seule (ProductivityModule.swift:123), aucune lectu… |
| Pauses et temps de trajet | manquant | aucun paramètre de pause ou trajet hors 13 h |
| Frise glisser-déposer | manquant | HabitTrackerTimelineView.swift:267 ne gère qu'un tap pour ajouter, aucun drag |
| Découper une tâche | manquant | aucune logique de découpe |
| Blocs verrouillés et aperçu avant écriture | manquant | generate écrase les créneaux de toutes les tâches en attente ProductivityModule… |
| Tâches récurrentes planifiées | présent, non testé | Tâche récurrente placée seulement les jours où elle revient ProductivityModule.… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `ProductivityModule.swift:400` : generate trie seulement par priorité sur un @Query non trié: à priorité égale l'ordre est arbitraire, les échéances sont ignorées et les tâches récurrentes son…

### Habitly (Habitify)
Résumé : présent, test auto 4, présent, non testé 6, manquant 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer / modifier une habitude (nom, icône, couleur) | présent, non testé | ProductivityModule.swift:943 HabitEditor.save, ouvert depuis HabitTrackerTimeli… |
| Jours actifs (fréquence hebdomadaire) | présent, non testé | ProductivityModule.swift:765 + Models_Life.swift:125 isActive |
| Heure prévue sur la frise 24 h | présent, non testé | HabitTrackerTimelineView.swift:87 timelineItems |
| Cocher aujourd'hui | présent, non testé | HabitTrackerTimelineView.swift:617 toggleItemDone |
| Cocher depuis le widget interactif | présent, test auto | LifeOSTests/HabitSyncTests.swift testDoubleTapIsIdempotent |
| Instantané widget (fait aujourd'hui, archivées exclues) | présent, test auto | LifeOSTests/HabitSyncTests.swift testPublishSkipsArchivedAndReflectsDoneToday |
| Série (streak) | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testStreakSkipsInactiveDays, test… |
| Objectifs de quantité ou de durée | manquant | Habit n'a aucun champ cible/unité (Models_Life.swift:83) |
| Sauter un jour / pause / gel de série | manquant | aucun état skip; softDelete/isArchived seulement dans du code non atteint Produ… |
| Domaines d'habitudes | manquant | moduleTag rempli par objectifs/défauts mais aucun écran pour le choisir ou filt… |
| Statistiques et calendrier de complétion | manquant | aucune vue heatmap/stats d'habitude trouvée (grep heatmap, HabitStat, HabitDeta… |
| Rappel par habitude | présent, non testé | HabitReminders.schedule ProductivityModule.swift:140-161 (un rappel hebdo par j… |
| Complétion automatique HealthKit | manquant | aucun lien Habit/HealthKit trouvé |
| Habitudes proposées à activer | présent, non testé | Bannière « N habitudes proposées à activer » ProductivityModule.swift:724-726 -… |
| Sauvegarde et restauration | présent, test auto | LifeOSTests/FullBackupTests.swift testBackupThenRestoreRebuildsEverything |

Défauts trouvés en lisant le code (5 corrigés sur 5) :

- [corrigé] `ProductivityModule.swift:522` : habits_avg_streak = nombre total de complétions / habitudes, pas une série; le coach l'affiche comme « Streak moyen habitudes: X jours » (UserContextBuilder.sw…
- [corrigé] `HabitTrackerTimelineView.swift:93` : La série remonte chaque jour calendaire sans regarder activeDays: une habitude du lundi au vendredi retombe à 1 chaque lundi.
- [corrigé] `HabitTrackerTimelineView.swift:622` : Décocher retire la complétion du tableau sans ctx.delete: la ligne HabitCompletion reste orpheline en base (l'autre chemin, HabitRow.toggleToday, la supprime).
- [corrigé] `ProductivityModule.swift:508` : Les habitudes en attente (HabitDefaults.swift:32, AIAssistantView.swift:628) ne sont affichées nulle part (PendingHabitRow jamais instancié), mais une notifica…
- [corrigé] `ProductivityModule.swift:812` : L'éditeur titre HORAIRE DU RAPPEL mais save() (ligne 943) ne programme aucune notification: le rappel promis n'existe pas.

### Forêt (Forest)
Résumé : présent, test auto 2, présent, non testé 3, manquant 6, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Minuteur focus basé sur l'horloge, survit à l'arrêt | présent, test auto | LifeOSTests/CountdownEngineTests.swift testSessionSurvivesProcessRestart |
| Pause / reprise | présent, test auto | LifeOSTests/CountdownEngineTests.swift testPauseFreezesAndResumeRebasesTheDeadl… |
| Durée de focus réglable | présent, non testé | ProductivityModule.swift:981 stepper focusLen |
| Durée de pause réglable | manquant | breakLen (ProductivityModule.swift:973) n'a aucun contrôle à l'écran ni ailleurs |
| Enchaînement focus / pause automatique | présent, non testé | ProductivityModule.swift:1005 finishPhase |
| Compteur de sessions | présent, non testé | ProductivityModule.swift:986 (état de vue non sauvegardé) |
| Historique et tags de sessions | manquant | aucun modèle FocusSession; sessions est un @State (ProductivityModule.swift:970) |
| Statistiques de concentration | manquant | aucune donnée de session persistée |
| Règles d'interruption (abandon = échec) | manquant | Stop arrête simplement le moteur ProductivityModule.swift:992 |
| Arbre qui pousse et collection | manquant | aucun visuel de croissance ni récompense, seulement TimerDial |
| Alerte de fin app fermée | manquant | CountdownEngine ne programme aucune notification locale (CountdownTimer.swift:1… |
| Blocage des apps | dépendance externe | FamilyControls/DeviceActivity, entitlement Apple; IntegrationNotice Productivit… |
| Multijoueur et vrais arbres plantés | dépendance externe | nécessite serveur et partenaire de plantation |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `ProductivityModule.swift:969` : isFocus, sessions et running sont des @State de vue: le moteur persiste après relance mais l'écran affiche Démarrer, onFinish est nil donc la pause ne démarre …

### Notio (Notion / Bear)
Résumé : présent, non testé 4, manquant 10, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer / modifier une note (titre, texte, tags) | présent, non testé | ProductivityModule.swift:1074 NoteEditor.save |
| Recherche plein texte (titre, texte, tags) | présent, non testé | ProductivityModule.swift:1018 filtered + .searchable |
| Supprimer une note | présent, non testé | ProductivityModule.swift:1042 |
| Étiquettes structurées (filtrer par tag) | manquant | tags est une String CSV (Models_Life.swift:139), affichée en puces mais aucun f… |
| Markdown / texte enrichi | manquant | TextField texte brut ProductivityModule.swift:1065 |
| Pièces jointes | manquant | aucun champ fichier/image sur Note |
| Organisation imbriquée (dossiers, pages) | manquant | Note n'a ni parent ni dossier |
| Liens retour (backlinks) | manquant | aucune analyse de liens entre notes |
| Export | présent, non testé | export JSON global DataExporter.swift:78 via DataExportSheet (ProfileView.swift… |
| Historique des versions | manquant | Note n'a que created, aucune version ni date de modification |
| Bases de données typées et vues | manquant | aucun modèle de base/propriétés |
| Relations et formules | manquant | aucun |
| Modèles de pages | manquant | aucun |
| Lien note ↔ tâche | manquant | aucune relation Note/TodoItem |
| Pages collaboratives et permissions | dépendance externe | nécessite comptes et serveur |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `ProductivityModule.swift:1031` : Une note existante ouverte par NavigationLink n'est sauvée que sur OK (ligne 1070): le bouton retour jette les modifications sans prévenir (perte de données).

## 💶 Argent


### Bankino (Bankin)
Résumé : présent, test auto 5, présent, non testé 3, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer un compte (nom, type, solde) | présent, non testé | FinanceModule.swift:141 AccountEditor |
| Ajouter une opération, solde recalculé en centimes | présent, test auto | LifeOSTests/LedgerServiceTests.swift testAddEditDeleteKeepsBalanceExact |
| Supprimer une opération | présent, test auto | LifeOSTests/LedgerServiceTests.swift testAddEditDeleteKeepsBalanceExact (UI Fin… |
| Supprimer un compte et ses opérations | présent, test auto | LifeOSTests/LedgerServiceTests.swift testDeletingAnAccountRemovesItsTransactions |
| Rattachement par identifiant de compte | présent, test auto | LifeOSTests/LedgerServiceTests.swift testRenamingAnAccountKeepsItsTransactions … |
| Montant saisi validé (texte invalide = erreur) | présent, test auto | LifeOSTests/AmountInputTests.swift testInvalidTextIsAnErrorNotZero |
| Modifier une opération | manquant | unreachable: LedgerService.updateTransaction (LedgerService.swift:42) n'a aucun… |
| Virements entre comptes | manquant | aucune opération de virement liée à deux comptes |
| Rapprochement bancaire | manquant | aucun état pointé/rapproché sur Txn |
| Catégories | présent, non testé | liste fixe de 9 FinanceModule.swift:154; pas de création ni de règles automatiq… |
| Paiements récurrents | manquant | aucune opération programmée |
| Import de relevés (CSV/OFX) | manquant | aucun import trouvé |
| Recherche et historique complet | manquant | seulement les 15 dernières FinanceModule.swift:98, aucune recherche |
| Alerte découvert / dépense inhabituelle | présent, non testé | FinanceModule.swift:113 anomalyAlert |
| Connexion bancaire réelle | dépendance externe | agrégateur DSP2 agréé (contrat + compte), absent |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `FinanceModule.swift:181` : TxnEditor retrouve le compte par NOM (premier trouvé): avec deux comptes du même nom l'opération va sur le mauvais compte, contre le modèle par identifiant.
- [corrigé] `AddAnythingSheet.swift:313` : Une dépense rapide sans compte crée un Txn avec accountID nil et account "Courant"; migrateIfNeeded (LedgerService.swift:113) ne rattache que par nom exact au …

### Ynabi (YNAB)
Résumé : présent, test auto 6, présent, non testé 3, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Enveloppes avec plafond mensuel | présent, non testé | FinanceModule.swift:279 EnvelopeEditor |
| Reste / dépassement affiché | présent, test auto | LifeOSTests/EnvelopeRolloverTests.swift testWithoutCarryOverEveryMonthStartsFro… |
| Remise à zéro chaque mois | présent, test auto | Preuve mise à jour: testNewMonthResetsSpending n'existe plus; LifeOSTests/Envel… |
| Dépenses liées aux transactions | présent, test auto | LifeOSTests/EnvelopeRolloverTests.swift testBankExpensesOfTheCategoryCountButIn… |
| Argent à assigner (fonds réels) | manquant | aucun lien entre revenus/comptes et enveloppes |
| Report du disponible et du dépassement | présent, test auto | LifeOSTests/EnvelopeRolloverTests.swift testCarryOverMovesLeftoverAndOverspendT… |
| Objectifs d'enveloppe (targets) | manquant | monthlyBudget n'est qu'un plafond |
| Cartes de crédit / dettes | manquant | aucun |
| Mois futurs | manquant | une seule période courante par enveloppe |
| Historique des mois précédents | présent, test auto | LifeOSTests/EnvelopeRolloverTests.swift testEachMonthKeepsItsOwnSpending, testY… |
| Réaffectation entre enveloppes | manquant | aucun transfert entre enveloppes |
| Modifier une enveloppe | présent, non testé | Menu « Modifier » FinanceModule.swift:301 -> EnvelopeEditor(envelope:) :237/:32… |
| Rapports | manquant | aucun graphique ni rapport budget |
| Supprimer une enveloppe | présent, non testé | FinanceModule.swift:233 |
| Dépenses d'enveloppe datées, modifiables, remboursement négatif | présent, test auto | LifeOSTests/EnvelopeRolloverTests.swift testEditingAPastEntryChangesOnlyThatMon… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `FinanceModule.swift:213` : Int() tronque les euros (9,99 € affiche 9, un dépassement de 0,50 € affiche « Dépassé de 0€ » ligne 217).
- [corrigé] `Models_Life.swift:287` : rolloverIfNeeded écrase spent à 0 sans rien garder: la dépense du mois précédent est perdue. (écritures datées par enveloppe + opérations Bankino, report au choix,…)

### Pocket Money (Rocket Money)
Résumé : présent, test auto 1, présent, non testé 6, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Liste manuelle des abonnements | présent, non testé | FinanceModule.swift:372 SubscriptionEditor; ajout rapide AddAnythingSheet.swift… |
| Coût mensuel et annuel total (annuel ramené à /12) | présent, non testé | FinanceModule.swift:292 + Models_Life.swift:304 monthlyCost |
| Activer / désactiver | présent, non testé | FinanceModule.swift:316 |
| Prélèvement du jour dans l'agenda | présent, non testé | TodayAgenda.swift:156 |
| Pré-remplissage par le questionnaire Finance | présent, non testé | FinanceSetup.swift:121 |
| Signal « Oublié ? » | manquant | Badge « Oublié ? » retiré (FinanceModule.swift:470-472, fix3): aucune donnée d'… |
| Avancer la prochaine échéance | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testNextChargeDateAdvancesByCycle… |
| Détection depuis les transactions | manquant | aucun code ne lit Txn pour trouver des marchands récurrents |
| Essais gratuits | manquant | aucun champ d'essai sur Subscription |
| Changements de prix et historique des prélèvements | manquant | un seul montant, aucun historique |
| Rappel avant prélèvement | manquant | rien ne programme de notification depuis Subscription; seul le rappel générique… |
| Suivi de résiliation (demande, preuve, statut) | manquant | le bouton Résilier ouvre une recherche Google FinanceModule.swift:340, aucun st… |
| Résiliation et négociation assistées | dépendance externe | nécessite un prestataire réel de résiliation |
| Supprimer un abonnement | présent, non testé | FinanceModule.swift:320 |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `FinanceModule.swift:330` : nextDate n'est jamais avancée: « Prochain » montre une date passée et « Oublié ? » s'allume sur tout abonnement actif 2 mois après sa date de départ (dont les …

### Quadricount (Tricount)
Résumé : présent, test auto 3, présent, non testé 4, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Dépense partagée (payeur, montant, participants) | présent, non testé | FinanceModule.swift:483 SplitEditor |
| Parts au centime exact | présent, test auto | LifeOSTests/SettlementCalculatorTests.swift testTenEurosBetweenThreeLosesNothing |
| Remboursements minimaux (qui doit à qui) | présent, test auto | LifeOSTests/SettlementCalculatorTests.swift testThreeWayDebtNeedsTwoTransfers |
| Montants affichés avec les centimes | présent, test auto | LifeOSTests/SettlementCalculatorTests.swift testCentsAreShownNotTruncated |
| Solde par membre | présent, non testé | FinanceModule.swift:390 balances |
| Supprimer une dépense | présent, non testé | FinanceModule.swift:436 |
| Plusieurs groupes | manquant | SplitExpense.group toujours "Coloc" (Models_Life.swift:327), aucun choix de gro… |
| Gérer les membres | présent, non testé | Carte « Membres » FinanceModule.swift:625 (ajout :576, retrait :582, membre uti… |
| Parts inégales / pourcentages | manquant | partage égal seulement via SettlementCalculator.split |
| Multi-devises | manquant | montants en EUR fixes; ExchangeRates non utilisé dans SplitView |
| Enregistrer un remboursement | manquant | aucun type de dépense remboursement |
| Justificatifs (photos) | manquant | aucun champ fichier |
| Modifier une dépense | manquant | seulement créer et supprimer |
| Édition collaborative et historique | dépendance externe | nécessite comptes et serveur |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `FinanceModule.swift:385` : Les membres valent par défaut « Moi,Alex,Sam » et aucun écran ne permet de les changer: deux personnes inventées apparaissent dans les soldes et les remboursem…

### Kapital (Qapital)
Résumé : présent, test auto 1, présent, non testé 4, manquant 7, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Objectif (cible, déjà épargné, effort mensuel) | présent, non testé | FinanceModule.swift:557 SavingsEditor |
| Progression | présent, non testé | Models_Life.swift:315 progress, FinanceModule.swift:508 |
| Projection des mois restants | présent, test auto | LifeOSTests/AuditFixesProductivityTests.swift testSavingsWithoutMonthlyEffortIs… |
| Versement manuel de l'effort | présent, non testé | FinanceModule.swift:512 (simple compteur, pas un virement) |
| Historique des versements | manquant | current est un seul Double, aucun journal |
| Retrait | manquant | aucun bouton ni logique de retrait |
| Compte de financement lié | manquant | SavingsGoal n'a aucun lien Account |
| Épargne programmée / règles | manquant | aucune règle ni planification |
| Scénarios de prévision | manquant | une seule projection linéaire |
| Date cible | manquant | aucun champ date sur SavingsGoal |
| Modifier un objectif | manquant | seulement créer et supprimer |
| Supprimer un objectif | présent, non testé | FinanceModule.swift:520 |
| Virements automatiques réels | dépendance externe | nécessite un service de paiement / compte bancaire |
| Objectifs partagés | dépendance externe | nécessite comptes et synchronisation |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `FinanceModule.swift:510` : Avec un effort mensuel à 0, monthsLeft rend 0 (Models_Life.swift:316) et l'écran affiche « Objectif atteint » alors que l'épargne est sous la cible; le bouton …
- [corrigé] `FinanceModule.swift:507` : Int() tronque déjà épargné et cible (99,99 € affiché 99).

### Linxa (Linxo)
Résumé : présent, non testé 3, manquant 6, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Solde global des comptes saisis | présent, non testé | FinanceModule.swift:573 BankOverviewView.total |
| Totaux par type de compte | présent, non testé | FinanceModule.swift:574 totalOf |
| Entrées / sorties / net du mois | présent, non testé | FinanceModule.swift:577-581 |
| Connexion à un établissement | dépendance externe | agrégateur DSP2 agréé (Bridge, Powens, Tink...), contrat et compte |
| Cycle de consentement | dépendance externe | lié à l'agrégateur DSP2 |
| Synchro initiale et historique | dépendance externe | lié à l'agrégateur DSP2 |
| Réauthentification | dépendance externe | lié à l'agrégateur DSP2 |
| Déduplication des opérations | manquant | aucun identifiant externe ni dédoublonnage sur Txn |
| En attente → comptabilisé | manquant | aucun statut sur Txn |
| Fraîcheur du solde | manquant | aucune date de synchro sur Account |
| Santé de la connexion | manquant | aucun modèle de connexion |
| Suppression d'une connexion | manquant | aucun modèle de connexion |
| Couche de connexion partagée entre modules finance | manquant | aucun service de connexion |

## 📈 Investissement


### Finario (Finary)
Résumé : présent, test auto 2, présent, non testé 4, manquant 6, dépendance externe 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'une position (symbole, type, quantité, prix d'achat), montant… | présent, non testé | InvestModule.swift:152 (HoldingEditor); AmountInput.parse a ses propres tests (… |
| Valeur totale et plus-value latente (globale et par ligne) | présent, test auto | LifeOSTests/Build52AuditTests.swift testMixedPortfolioTotalsOnlyCountKnownCosts… |
| Répartition en anneau par symbole | présent, non testé | InvestModule.swift:37-40 (SectorMark par h.symbol, pas par classe d'actifs) |
| Cours crypto automatiques en EUR (CoinGecko, cache 60 s) | dépendance externe | PriceService.swift:40 api.coingecko.com coins/markets, sans clé, limite ~30 app… |
| Cours actions/ETF différés convertis en EUR (Yahoo chart) | dépendance externe | PriceService.swift:110-166 query1.finance.yahoo.com, point non documenté; aucun… |
| Suppression d'une position | présent, non testé | InvestModule.swift:58 contextMenu ctx.delete |
| Modifier une position existante | présent, non testé | Tap ou « Modifier » InvestModule.swift:72-74 -> HoldingEditor(holding:) :97/:17… |
| Lots de transactions (achats multiples, ventes) | manquant | Holding n'a qu'une quantité et un prix d'achat (Models_Assets.swift:6-19); aucu… |
| Dividendes et frais de courtage | manquant | grep -i 'dividend/dividende/frais' sans résultat côté portefeuille; aucun champ… |
| Plus-values réalisées | manquant | pas de vente enregistrée, donc aucun calcul réalisé (Holding.pnl = latent seule… |
| Historique de valeur du portefeuille | manquant | aucun modèle d'instantané; seul le dernier cours est stocké (currentPrice) |
| Comparaison à un indice de référence | manquant | grep -i 'benchmark/indice' sans résultat dans LifeOS |
| Classes d'actifs étendues (obligations, SCPI, livrets, fonds euros) | manquant | Picker limité à Action/ETF/Crypto (InvestModule.swift:169) |
| Import ou connexion courtier | dépendance externe | aucun import CSV ni agrégateur (grep -i 'courtier/broker' vide); demanderait un… |
| Devise du prix d'achat, convertie en euros au taux BCE du jour d'acha… | présent, test auto | LifeOSTests/Build52AuditTests.swift testCostIsConvertedAtThePurchaseDayRate, te… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `PriceService.swift:158` : cur.uppercased() transforme 'GBp' (pence, renvoyé par Yahoo pour les titres .L) en 'GBP': une action de Londres est valorisée 100 fois trop haut.
- [corrigé] `InvestModule.swift:171` : Le prix d'achat n'a pas de devise alors que le cours actuel est converti en euros: un titre américain saisi à son prix en dollars affiche une fausse plus ou mo… (devise, date et taux BCE du jour d'achat ; anciennes positions « à co…)
- [corrigé] `InvestModule.swift:89` : 'Cours à jour' s'affiche dès qu'un seul symbole est mis à jour; un symbole introuvable garde son prix manuel en silence et sa ligne semble à jour.

### Kubero (Kubera)
Résumé : présent, test auto 1, présent, non testé 2, manquant 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Actifs / passifs, patrimoine net | présent, non testé | InvestModule.swift |
| Projection avec pertes, frais, inflation, 3 scénarios | présent, test auto | FireProjectionTests |
| Capital de départ = placements (option autres actifs) | présent, non testé | startCapital |
| Historique du patrimoine dans le temps | manquant |  |
| Devises | manquant |  |
| Amortissement des dettes | manquant |  |
| Analyse de risque (volatilité, séquence des rendements) | manquant | projection déterministe seulement |

### Horizo (Horiz.io)
Résumé : présent, test auto 2, présent, non testé 5, manquant 7, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Fiche bien: valeur, loyer, charges, capital restant dû, mensualité | présent, non testé | InvestModule.swift:392-438 (PropertyEditor), modèle Models_Assets.swift:30-43 |
| Cashflow net mensuel par bien et total | présent, non testé | Models_Assets.swift:41; InvestModule.swift:335,344,362 |
| Equity nette (valeur moins capital restant dû) | présent, non testé | Models_Assets.swift:42; InvestModule.swift:345 |
| Rendement brut | présent, non testé | InvestModule.swift:364 (loyer x12 / valeur actuelle, pas prix d'achat + frais) |
| Extraction des chiffres d'une annonce collée (JSON du modèle -> fiche) | présent, test auto | LifeOSTests/ListingParserTests.swift testChargesAreNeverSilentlyDivided, testMi… |
| Prix au m² affiché depuis l'annonce | présent, test auto | LifeOSTests/ListingParserTests.swift testPricePerM2 (affichage InvestModule.swi… |
| Lecture automatique de l'annonce par IA, fiche relue avant enregistre… | dépendance externe | InvestModule.swift:447-513 appelle AIText.ask; demande une clé fournisseur IA (… |
| Suppression d'un bien | présent, non testé | InvestModule.swift:366 contextMenu |
| Modifier un bien existant | manquant | PropertyEditor ne fait qu'insérer (InvestModule.swift:434); aucune édition d'un… |
| Frais d'acquisition (notaire, agence, travaux) | manquant | aucun champ dans Property ni PropertyEditor |
| Financement et tableau d'amortissement | manquant | la mensualité est saisie à la main; aucun calcul taux/durée/amortissement |
| Vacance locative, provision travaux, taxe foncière, fiscalité locative | manquant | Property n'a que loyer/charges/crédit (Models_Assets.swift:30-43) |
| Scénarios de cashflow/rendement net | manquant | un seul calcul brut; aucun scénario |
| Baux, locataires, suivi des loyers encaissés, quittances | manquant | aucun modèle bail/locataire/loyer dans LifeOS/Models |
| Documents d'entretien liés au bien | manquant | DocVault existe ailleurs mais n'est pas relié à Property |
| Flux d'annonces authentifié (portail immobilier) | dépendance externe | seul le copier-coller est supporté; un vrai flux demanderait l'API d'un portail… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `InvestModule.swift:434` : Double(x) ?? 0: une saisie illisible (ex. '1 200' collé) devient 0 sans message et fausse le cashflow, alors que HoldingEditor refuse ce cas.

### Impôts+ (Simulateur impots.gouv)
Résumé : présent, test auto 8, présent, non testé 2, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Barème progressif 2026 (revenus 2025) | présent, test auto | LifeOSTests/FrenchTaxTests.swift testSinglePersonMiddleIncome, testTopBracket |
| Quotient familial (parts, couple jamais sous 2 parts) | présent, test auto | LifeOSTests/FrenchTaxTests.swift testMorePartsNeverIncreasesTax, testCoupleNeve… |
| Plafonnement des demi-parts | présent, test auto | LifeOSTests/FrenchTaxTests.swift testFamilyQuotientIsCapped |
| Décote des revenus modestes | présent, test auto | LifeOSTests/FrenchTaxTests.swift testDecoteWipesOutSmallTax, testDecoteAppliesT… |
| Situation célibataire / couple | présent, test auto | LifeOSTests/FrenchTaxTests.swift testCoupleePaysLessThanSingle |
| Tranche marginale (cas sans plafonnement) | présent, test auto | LifeOSTests/FrenchTaxTests.swift testSinglePersonMiddleIncome (marginalRate 0.3… |
| Taux moyen, net après IR et détail plafonnement/décote à l'écran | présent, non testé | InvestModule.swift:554-587 |
| Mention estimation simplifiée (pas le simulateur officiel) | présent, non testé | InvestModule.swift:589 |
| Cas particuliers (parent isolé case T, veuf, invalidité, 3e enfant = … | manquant | FrenchTax.Status n'a que single/couple (FrenchTax.swift:26-36); parts saisies a… |
| Revenus par catégorie (salaires avec abattement 10 %, BIC/BNC, pensio… | manquant | une seule entrée 'Revenu net imposable' (InvestModule.swift:539-541) |
| Revenus fonciers et revenus du capital (PFU) | manquant | aucun champ ni calcul dans FrenchTax.swift |
| Réductions et crédits d'impôt, charges déductibles | manquant | non pris en compte, dit à l'écran InvestModule.swift:589 |
| Versions par année fiscale | manquant | un seul barème codé en dur FrenchTax.swift:43-49 |
| Export ou partage du résultat | manquant | aucun ShareLink/export dans TaxSimulatorView (InvestModule.swift:518-604) |
| Enfants à charge -> parts (demi-part pour les 2 premiers, part entièr… | présent, test auto | LifeOSTests/AuditGlobalOct1Tests.swift testThirdChildCountsAWholePart (FrenchTa… |
| Tranche marginale quand le plafonnement s'applique (parts de base) | présent, test auto | LifeOSTests/AuditGlobalOct1Tests.swift testMarginalRateFollowsBasePartsWhenTheC… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `FrenchTax.swift:120` : Quand le plafonnement des demi-parts s'applique, l'impôt suit le barème des parts de base, mais la tranche affichée est calculée sur toutes les parts: couple, …
- [corrigé] `InvestModule.swift:547` : La consigne dit 'une demi-part par enfant', faux dès le 3e enfant (1 part entière): un couple avec 3 enfants saisira 3,5 parts au lieu de 4 et verra un impôt t…
- [corrigé] `InvestModule.swift:541` : Revenu saisi seulement au curseur de 10 000 à 200 000 € par pas de 1 000: impossible d'entrer un revenu exact, sous 10 000 ou au-dessus de 200 000.

## 💼 Carrière


### Huntly (Huntr)
Résumé : présent, test auto 1, présent, non testé 5, manquant 9

| Fonctionnalité | État | Preuve |
|---|---|---|
| Pipeline par statut avec compteurs (Repéré, Postulé, Entretien, Offre… | présent, non testé | CareerModule.swift:15-47 |
| Ajout et édition d'une candidature (entreprise, poste, statut, lien, … | présent, non testé | CareerModule.swift:58-80 |
| Ajout depuis une offre trouvée (bouton Suivre) | présent, non testé | CareerModule.swift:659,669-673 |
| Compteur d'entretiens dans le récap Carrière | présent, non testé | CategoryRecapCards.swift:206-213 |
| Supprimer une candidature | présent, non testé | Balayage CareerModule.swift:53-54 et menu contextuel -> confirmation :70 -> ctx… |
| Vue tableau (kanban, glisser entre colonnes) | manquant | liste groupée seulement; aucun drag/drop |
| Copie de la description de l'offre | manquant | JobApplication ne garde que url et notes (Models_Assets.swift:47-57) |
| Contacts liés à une candidature | manquant | aucun lien JobApplication -> Contact |
| Dates de candidature éditables et échéances | manquant | date fixée à la création, jamais éditable ni mise à jour au changement de statut |
| Tâches et rappels | manquant | aucune notification ni tâche dans CareerModule |
| CV joint / variante de CV par candidature | manquant | aucun lien au CV (CV unique en AppStorage) |
| Entretiens planifiés (date, type) | manquant | seulement un statut texte 'Entretien' |
| Statistiques de résultats (taux de réponse, conversion) | manquant | seuls des compteurs par statut |
| Capture depuis le navigateur / feuille de partage | manquant | aucune extension de partage (Extensions/ ne contient que LifeOSDeviceActivity) |
| Dédoublonnage des offres suivies | présent, test auto | LifeOSTests/AuditFixesCareerTests.swift testTrackKeyIgnoresUrlCosmetics (JobMat… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `CareerModule.swift:11` : Aucune suppression de candidature n'existe: une erreur ou un doublon reste pour toujours dans le pipeline.

### Zetty (Zety / Canva)
Résumé : présent, test auto 3, présent, non testé 3, manquant 8, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| CV structuré: identité, profil, expérience, formation, compétences | présent, non testé | CareerModule.swift:85-135 (stocké en AppStorage) |
| Export PDF A4 paginé, texte sélectionnable avec accents | présent, test auto | LifeOSTests/CVDocumentTests.swift testTextIsSelectableWithAccents, testLongExpe… |
| Sections vides retirées, CV vide détecté | présent, test auto | LifeOSTests/CVDocumentTests.swift testEmptyCVIsDetected, testTextIsSelectableWi… |
| Aperçu du PDF et partage du fichier | présent, non testé | CareerModule.swift:688-730 (CVPreviewSheet) |
| Partage en texte brut | présent, non testé | CareerModule.swift:143 |
| Adapter le profil à une offre par IA, avec relecture avant application | dépendance externe | CareerModule.swift:182-256 appelle AIText.ask; demande une clé fournisseur IA |
| Plusieurs CV | manquant | un seul jeu de clés AppStorage cv* (CareerModule.swift:86-92) |
| Réordonner les sections | manquant | ordre fixe CVDocument.swift:41 |
| Plusieurs modèles de mise en page | manquant | un seul rendu dans CVDocument.attributed |
| Export DOCX | manquant | seul CVDocument.pdf existe |
| Import d'un CV existant | manquant | aucun import PDF/LinkedIn dans CareerModule ou CVDocument |
| Versions / historique du CV | manquant | AppStorage écrasé à chaque frappe |
| Lettre de motivation | manquant | grep 'lettre de motivation/cover letter' sans résultat |
| Suite design type Canva (éditeur libre, banque d'éléments, collaborat… | manquant | aucun éditeur graphique; hors périmètre du générateur de CV |
| Réponse IA: mots-clés séparés du profil, seul le profil est appliqué | présent, test auto | LifeOSTests/AuditFixesCareerTests.swift testKeywordsAreSplitOffTheProfile, test… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `CareerModule.swift:221` : Le prompt demande de finir par une ligne 'Mots-clés à ajouter :', et le bouton copie tout le résultat dans le profil: la liste de mots-clés finit dans le CV si…

### LinkedUp (LinkedIn Learning)
Résumé : présent, test auto 1, présent, non testé 4, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Poste cible et liste de compétences, cocher acquise | présent, non testé | CareerModule.swift:261-329 |
| Progression en % par poste cible | présent, non testé | CareerModule.swift:277-280 |
| Plan d'acquisition en texte libre | présent, non testé | CareerModule.swift:287,320 |
| Supprimer une compétence | présent, non testé | CareerModule.swift:292 |
| Compétences réutilisées pour trier les offres | présent, test auto | LifeOSTests/AuditFixesCareerTests.swift testOnlyAcquiredSkillsCount (JobMatchin… |
| Modifier une compétence existante | manquant | seul le basculement acquise/non acquise existe (CareerModule.swift:282) |
| Évaluation de niveau (test de compétences) | manquant | aucun quiz ni test de niveau dans CareerModule |
| Catalogue de cours recherchable et parcours | dépendance externe | aucun contenu de cours; demanderait un fournisseur de contenu |
| Leçons et lecture vidéo | manquant | aucun lecteur ni leçon liée aux compétences |
| Quiz et exercices | manquant | aucun |
| Notes de cours | manquant | seulement le champ plan |
| Suivi de progression par leçon et certificat de fin | manquant | aucun modèle de leçon/certificat |
| Lien entre lacunes d'une offre et leçons disponibles | manquant | aucun |

### Yoodly (Yoodli)
Résumé : présent, non testé 4, manquant 8, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Banque de 8 questions d'entretien fixes | présent, non testé | CareerModule.swift:350-359 |
| Conseil par question (méthode STAR) | présent, non testé | CareerModule.swift:360-369,389-399 |
| Navigation entre questions avec remise à zéro de la réponse | présent, non testé | CareerModule.swift:473-481 |
| Réponse écrite et retour IA (structure STAR, résultat chiffré, réécri… | dépendance externe | CareerModule.swift:483-508 AIText.ask; demande une clé fournisseur IA |
| Mode texte qui ne prétend pas mesurer l'oral | présent, non testé | CareerModule.swift:426-430 (réponse écrite seulement, aucun score de diction) |
| Configuration poste / entreprise / scénario | manquant | questions codées en dur, aucun paramètre |
| Questions de relance (vraie conversation) | manquant | un seul aller-retour par question |
| Enregistrement audio et transcription | manquant | aucun AVAudioRecorder/SFSpeech dans CareerModule |
| Réécoute de l'enregistrement | manquant | aucun |
| Métriques de diction (débit, mots parasites, pauses) | manquant | aucun |
| Grille d'évaluation structurée avec note | manquant | retour en texte libre seulement |
| Historique des séances | manquant | état @State perdu en quittant l'écran |
| Comparaison des progrès dans le temps | manquant | aucun historique, donc aucune comparaison |

### Welcome to the Djob (Welcome to the Jungle)
Résumé : présent, test auto 2, présent, non testé 5, manquant 7, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Offres réelles d'un flux public (Arbeitnow) | dépendance externe | CareerModule.swift:531 arbeitnow.com/api/job-board-api, sans clé, surtout Allem… |
| Recherche texte (poste, techno, ville, entreprise) | présent, non testé | CareerModule.swift:561-570 |
| Filtre télétravail | présent, non testé | CareerModule.swift:564,615 |
| Tri par correspondance avec les compétences suivies (étoile) | présent, test auto | LifeOSTests/AuditFixesCareerTests.swift testOnlyAcquiredSkillsCount, testWholeW… |
| Ouvrir l'offre | présent, non testé | CareerModule.swift:656 |
| Suivre l'offre dans les candidatures | présent, non testé | CareerModule.swift:669-673 |
| Rafraîchir et réessayer après erreur | présent, non testé | CareerModule.swift:586,598 |
| Filtres lieu, type de contrat, salaire, entreprise | manquant | job_types décodé mais jamais utilisé; aucun champ salaire (CareerModule.swift:5… |
| Explication de la pertinence | manquant | seulement un nombre d'étoiles |
| Recherches sauvegardées et alertes | manquant | aucune persistance de recherche ni notification |
| Dédoublonnage | manquant | aucun, ni dans le flux ni au suivi |
| Pagination | manquant | une seule page chargée (CareerModule.swift:531-537) |
| Gestion des offres expirées | manquant | aucun champ date/expiration lu |
| Fiches entreprise | manquant | aucune |
| Catalogue Welcome to the Jungle | dépendance externe | aucune API WTTJ; le flux Arbeitnow n'est pas leur catalogue |
| Message d'erreur selon la cause (réseau, code HTTP, format changé) | présent, test auto | LifeOSTests/AuditFixesCareerTests.swift testErrorMessagesNameTheRealCause (JobS… |

Défauts trouvés en lisant le code (4 corrigés sur 4) :

- [corrigé] `CareerModule.swift:552` : Le tri prend toutes les SkillGap, y compris les compétences NON acquises, et l'écran du hub dit 'selon tes compétences': des offres sont mises en avant pour de…
- [corrigé] `CareerModule.swift:558` : Correspondance par sous-chaîne: la compétence 'go' compte pour 'Google', 'java' pour 'JavaScript', donc des étoiles fausses.
- [corrigé] `CareerModule.swift:670` : 'Suivre' insère sans vérifier l'url: chaque appui crée un doublon dans Huntly, et Huntly ne permet pas de supprimer.
- [corrigé] `CareerModule.swift:678` : Toute erreur (décodage, HTTP non 200) est affichée 'vérifie ta connexion': un changement de format de l'API se lit comme une panne réseau.

## 📚 Apprentissage


### Trilingo (Duolingo)
Résumé : présent, test auto 7, présent, non testé 2, manquant 4, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Questionnaire obligatoire (langue, objectif, niveau, temps, rappel) | présent, non testé | Trilingo.swift:35 |
| Cours structurés Tatoeba (21 langues depuis le français, jours/unités… | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testBundledCoursesAreHonest |
| Test de placement adaptatif (paliers, arrêt au premier échec) | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testPlacementStopsAtFirstFailedLevel + te… |
| Séance du jour: lecture, écriture (étiquettes), écoute (dictée/choix) | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testFirstSessionIntroducesNewSentencesInS… |
| Répétition espacée par compétence (boîtes 1 à 120 jours) | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testIntervalsGrow + testSimulated180Days |
| Carnet d'erreurs et séance de reprise des erreurs | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testWrongAnswerGoesToNotebookAndComesBack… |
| Correction tolérante (accents, casse, ponctuation, langues sans espac… | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testAnswerCheckingIgnoresAccentsCaseAndPu… |
| Rappel quotidien sur 7 jours, sauté si séance faite | présent, test auto | LifeOSTests/TrilingoEngineTests.swift testRemindersSkipTodayWhenDoneAndNeverDup… |
| Série de jours (streak) et compétences acquises | présent, non testé | TrilingoEngine.swift:44 affiché Trilingo.swift:250 et :314; aucun test sur stre… |
| Exercice oral au micro (reconnaissance vocale) | dépendance externe | micro + SFSpeechRecognizer sur appareil réel, TrilingoStore.swift:140 |
| Audio humain Tatoeba | dépendance externe | réseau audio.tatoeba.org, TrilingoStore.swift:116; sinon voix de l'appareil |
| Retour de prononciation | manquant | aucune analyse phonétique; seule la similarité texte du transcript (Trilingo.sw… |
| Notes de grammaire et liste de vocabulaire | manquant | grep grammar/grammaire: rien; le champ TrilingoDay.words existe dans les donnée… |
| Points de contrôle d'unité | manquant | grep checkpoint: rien dans Modules/Trilingo.swift ni Services/Trilingo |
| XP, ligues, amis, coeurs, matières non linguistiques, autres langues … | manquant | aucun code; seul source = fra (TrilingoProfile.source), message 'pas de synchro… |

Défauts trouvés en lisant le code (4 corrigés sur 5) :

- [corrigé] `TrilingoStore.swift:158` : Le tap micro est posé avant engine.start(); si start lève une erreur, stopListening ne retire le tap que si le moteur tourne (ligne 171), donc le prochain appu…
- [corrigé] `TrilingoStore.swift:116` : Une phrase avec audio Tatoeba passe uniquement par AVPlayer réseau, sans erreur ni repli sur la voix de l'appareil: hors ligne 'Écouter' reste muet et les dict…
- [partiel] `Trilingo.swift:207` : Les choix du placement ne filtrent que le tid, or les cours embarqués ont des phrases sources en double (47 en fra-eng, 428 en fra-heb): la bonne réponse peut … (reste : doublons retirés à l'écran ; le moteur peut encore en produire)
- [corrigé] `Trilingo.swift:181` : Après 'Refaire le test de niveau', un résultat plus bas affiche 'Tu commences au jour X' mais nextItem est gardé (TrilingoEngine.swift:173), donc la séance rep…
- [corrigé] `TrilingoStore.swift:83` : Le rappel porte route=trilingo mais NotificationDelegate (AppDelegate.swift:141) ne lit jamais cette clé: toucher le rappel n'ouvre pas la séance.

### Anko (Anki)
Résumé : présent, test auto 12, présent, non testé 1, manquant 2, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer une carte recto/verso dans un paquet | présent, test auto | LearningModule.swift:262 FlashcardEditor; LifeOSTests/Lot6LearningTests.swift t… |
| Liste des paquets avec nombre de cartes (total et à réviser, sous-paq… | présent, non testé | LearningModule.swift:176 deckRow |
| Compteur de cartes dues et lancement de révision (global ou par paque… | présent, test auto | Models_Learning.swift:305 CardScheduling.sessionCards; Lot6LearningTests testSu… |
| Révision avec planification SM-2 (À revoir / Correct / Facile), dates… | présent, test auto | Models_Learning.swift:288 SM2 (now/calendar injectables); Lot6LearningTests tes… |
| Modifier, supprimer ou parcourir les cartes | présent, test auto | LearningModule.swift:371 CardBrowserView (tap = modifier, glisser = supprimer l… |
| Paquets: créer, renommer, supprimer (cartes déplacées vers Général ou… | présent, test auto | Models_Learning.swift:443 DeckOps; LearningModule.swift:240 commitDeck; Lot6Lea… |
| Hiérarchie de paquets (Parent::Enfant, comme Anki) | présent, test auto | Models_Learning.swift:399 DeckTree; Lot6LearningTests testDeckTree_hierarchy |
| Migration unique des cartes existantes vers un paquet objet, sans per… | présent, test auto | Models_Learning.swift:498 DeckMigration (lancée à l'ouverture de FlashcardsView… |
| Cartes texte à trous ({{c1::...}}) et inversées générées depuis une n… | présent, test auto | Models_Learning.swift:138 Cloze, :178 NoteFactory, :218 CardFace; Lot6LearningT… |
| Images et audio sur les cartes | manquant | Flashcard reste texte seul; pas de stockage média par carte |
| Étiquettes et recherche (texte, tag:mot, is:suspendue) | présent, test auto | Models_Learning.swift:244 CardTags, :260 CardSearch; Lot6LearningTests testTags… |
| Import/export CSV et texte tabulé (export Anki en texte brut), .apkg … | présent, test auto | Models_Learning.swift:569 FlashcardCSV; LearningModule.swift:643 AnkoImportExpo… |
| Suspendre, enterrer jusqu'à demain, réapprendre dans la séance, annul… | présent, test auto | Models_Learning.swift:348 ReviewQueue, :385 ReviewUndo, CardReview log; Learnin… |
| Statistiques (dues aujourd'hui, révisions par jour sur 14 j, réussite… | présent, test auto | Models_Learning.swift:725 CardStats; LearningModule.swift:597 CardStatsView; Lo… |
| Réglages de planification (limites par jour, pas d'apprentissage) | manquant | SM-2 fixe, aucun écran de réglages |
| Synchronisation | dépendance externe | exige un compte et un service de synchronisation (ou CloudKit activé dans le st… |

### Headwave (Headway)
Résumé : présent, test auto 3, présent, non testé 4, dépendance externe 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Notion du jour (8 fiches en dur, rotation par jour, libellé honnête) | présent, non testé | LearningModule.swift:799 todayCard |
| Mes notions: saisir titre, explication et source, modifier, supprimer | présent, test auto | LearningModule.swift:725 MicroLearningView + FlashcardEditor (mode notion); Mod… |
| Garder la notion du jour dans mes notions | présent, test auto | LearningModule.swift:799 todayCard; NotionStore.exists testé dans testNotions_a… |
| Répétition espacée des notions (même moteur et même progression qu'An… | présent, test auto | notions = Flashcard du paquet Notions, ReviewSession; Lot6LearningTests testSus… |
| Historique des notions passées et recherche | présent, non testé | LearningModule.swift:725 liste triée par date + searchable (CardSearch testé) |
| Écoute audio d'une notion (synthèse vocale) | présent, non testé | LearningModule.swift:825 CoachSpeech.toggle |
| Sources par fiche | présent, non testé | champ Flashcard.source saisi par l'utilisateur, affiché dans notionRow; les 8 f… |
| Catalogue cherchable de contenus | dépendance externe | exige un contenu éditorial original ou sous licence |
| Programmes structurés | dépendance externe | exige un catalogue éditorial |
| Surlignages enregistrés | dépendance externe | sans texte de leçon à surligner (catalogue absent); les surlignages de livres e… |
| Quiz et récapitulatifs | dépendance externe | exige un contenu éditorial et des questions validées |
| Recommandations personnalisées | dépendance externe | rien à recommander sans catalogue |
| Téléchargements hors ligne | dépendance externe | sans objet sans catalogue; les notions sont locales donc hors ligne |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LearningModule.swift:163` : L'écran promet une nouvelle notion chaque jour alors que seules 8 fiches tournent en boucle.

### Blinklist (Blinkist)
Résumé : présent, test auto 6, présent, non testé 3, dépendance externe 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Saisir un résumé (titre, auteur, note, idées clés, collections) | présent, non testé | LearningModule.swift:1213 BookEditor |
| Liste des résumés et suppression (avec ses passages) | présent, test auto | LearningModule.swift:848 BookSummariesView; Models_Learning.swift:898 BookOps.d… |
| Résumé généré par ton coach | dépendance externe | clé fournisseur requise (AIText.isConfigured), LearningModule.swift:1134 |
| Distinguer résumé du coach et résumé de l'utilisateur (marque conserv… | présent, test auto | BookSummaryOrigin; BookEditor.save remet la marque; Lot6LearningTests testCoach… |
| Modifier un résumé existant | présent, non testé | LearningModule.swift:1213 BookEditor(book:), ouvert depuis BookDetailView |
| Navigation par chapitre / idée clé (sommaire qui défile au chapitre) | présent, test auto | LearningModule.swift:960 BookDetailView; Models_Learning.swift:898 BookOps.outl… |
| Surlignages de l'utilisateur (avec page), modifier, réordonner, suppr… | présent, test auto | BookPassage + LearningModule.swift:1079 BookPassageEditor; BookOps.move testé d… |
| Collections (filtre par puces) | présent, test auto | Models_Learning.swift:878 BookCollections; LearningModule.swift:911 collectionC… |
| Recherche (titre, auteur, idées, passages) | présent, test auto | BookOps.matches; Lot6LearningTests testBooks_outlineSearchCollectionsMigration |
| Idée ou surlignage vers flashcard Anko (paquet Livres::Titre) | présent, non testé | LearningModule.swift:1072 contextMenu Créer une flashcard |
| Métadonnées sourcées (ISBN, couverture, éditeur) | dépendance externe | exige une API de catalogue de livres |
| Résumés édités et version audio | dépendance externe | exige un catalogue éditorial sous licence et une production audio |
| Découverte et catalogue | dépendance externe | exige un catalogue éditorial |
| Téléchargements | dépendance externe | sans objet sans catalogue; les notes sont locales |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LearningModule.swift:288` : Le résumé écrit par l'IA est enregistré comme un BookSummary ordinaire, sans marque d'origine, avec la note par défaut 4 (Models_Assets.swift:91) affichée ★★★★…

### Coursia (Coursera)
Résumé : présent, test auto 6, présent, non testé 1, manquant 1, dépendance externe 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Plusieurs programmes créés par l'utilisateur | présent, test auto | LearningModule.swift:1308 SkillPlanView, :1541 CourseEditor; Lot6LearningTests … |
| Hiérarchie programme / module / leçon avec lien et notes | présent, test auto | Course, CourseModule, CourseLesson; LearningModule.swift:1397 CourseDetailView,… |
| Progression par programme et reprise de la prochaine leçon | présent, test auto | CourseOps.progress / next; Lot6LearningTests testCourses_progressNextReorderAnd… |
| Échéances avec rappel (permission demandée, refus affiché avec accès … | présent, test auto | CourseOps.reminderDate/deadlineLabel; LearningModule.swift:21 LearningReminderT… |
| Supprimer ou réordonner programmes, modules et leçons | présent, test auto | CourseOps.moved/renumber/delete; LearningModule.swift:1331 et :1469 onMove; Lot… |
| Reprise unique de l'ancien plan (AppStorage) en programme, sans perte | présent, test auto | Models_Learning.swift:843 SkillPlanMigration; LearningModule.swift:1379; Lot6Le… |
| Leçon vers flashcard Anko (paquet Cours::Titre) | présent, non testé | LearningModule.swift:1517 contextMenu Créer une flashcard |
| Lecture de médias (vidéo, lecture) | manquant | le lien s'ouvre dans le navigateur (CourseOps.url testé), aucun lecteur intégré |
| Évaluations et projets notés | dépendance externe | exige un système d'évaluation et de correction |
| Discussion et retours | dépendance externe | exige un serveur et des comptes |
| Certificats vérifiables | dépendance externe | exige des établissements partenaires et un service de vérification |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `LearningModule.swift:362` : Les jalons sont identifiés par leur texte: deux jalons identiques partagent l'état fait et un id ForEach (ligne 344), et aucun jalon ne peut être supprimé.

## 🏠 Maison


### NoGaspi (NoWaste)
Résumé : présent, test auto 1, présent, non testé 6, manquant 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Stock unique partagé avec le frigo (pas de 2e base) | présent, non testé | HomeModule.swift:13 lit PantryItem, saisi par NutritionModule.swift:386 |
| Produits triés par date de péremption | présent, non testé | HomeModule.swift:14 |
| Badge J-n / Aujourd'hui / Périmé | présent, non testé | NutritionModule.swift:374 |
| Emplacement (frigo, placard, congélateur) | présent, non testé | NutritionModule.swift:398 |
| Marquer consommé (supprime l'article) | présent, non testé | HomeModule.swift:29 |
| Courses cochées rangées dans le frigo | présent, non testé | NutritionModule.swift:523 |
| Journal consommé / gaspillé | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testAntiWasteLog_countsAndUndo (AntiW… |
| Scan code-barres à l'entrée en stock | manquant | seuls créateurs de PantryItem: NutritionModule.swift:406 et :526, aucun scan |
| Gestion par lots | manquant | PantryItem a une seule date et une quantité texte |
| Rappels avant péremption | manquant | aucun NotificationManager.schedule sur PantryItem.expiry |
| Analyse du gaspillage et du coût | manquant | aucun prix ni historique |
| Partage avec le foyer | manquant | aucun compte ni sync |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `HomeModule.swift:29` : 'Consommé' supprime l'article du frigo partagé sans trace ni annulation: impossible de distinguer consommé et jeté, donc aucune donnée pour un bilan anti-gaspi.

### SuperCuisto (SuperCook)
Résumé : présent, test auto 1, présent, non testé 1, manquant 9

| Fonctionnalité | État | Preuve |
|---|---|---|
| Suggestions depuis le frigo | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testRecipeMatching_wholeWordsAndLigat… |
| Pourcentage d'ingrédients disponibles | présent, non testé | HomeModule.swift:54 |
| Catalogue de recettes substantiel | manquant | 8 recettes codées en dur (NutritionModule.swift:416-424) |
| Ingrédients manquants affichés | manquant | la vue liste tous les ingrédients sans marquer les manquants (HomeModule.swift:… |
| Instructions pas à pas | manquant | Recipe n'a que name et ingredients |
| Filtres régime, allergènes, temps, difficulté | manquant | aucun champ |
| Substitutions | manquant | aucune |
| Ajustement des portions | manquant | aucune quantité |
| Favoris | manquant | aucun |
| Ajout des manquants à la liste de courses / plan repas | manquant | aucun lien depuis LeftoverRecipesView |
| Sources des recettes vérifiées | manquant | aucune source |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `NutritionModule.swift:429` : Correspondance par sous-chaîne dans les deux sens: 'pomme' compte comme 'pomme de terre', et 'œuf' saisi avec ligature ne correspond pas à 'oeuf'.

### Sweepo (Sweepy)
Résumé : présent, test auto 2, présent, non testé 3, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Tâche avec fréquence et personne assignée | présent, non testé | HomeModule.swift:106 |
| Marquer fait et calcul de la prochaine échéance | présent, non testé | HomeModule.swift:91, Models_Assets.swift:106 |
| Tri par échéance, retard en rouge | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testChoreDueLabel_usesCalendarDays (C… |
| Tâches dues dans l'agenda du jour | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testMaintenanceNeverDone_isDue (Today… |
| Ajout rapide | présent, non testé | AddAnythingSheet.swift:325 |
| Pièces | manquant | Chore n'a pas de pièce |
| Niveau de propreté / urgence et effort | manquant | aucun champ |
| Rotation entre membres | manquant | assignee est un texte libre fixe |
| Membres du foyer et invitations | dépendance externe | exige comptes et serveur partagé; rien dans le code |
| Notifications par personne | manquant | aucune notification pour Chore |
| Historique des tâches faites et points | manquant | lastDone écrasé à chaque fois |
| Sauter, reporter, mode vacances | manquant | aucune action |
| Modifier une tâche | manquant | seulement ajout et suppression |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `HomeModule.swift:103` : L'écart en jours est calculé depuis maintenant, pas depuis le début de journée: une tâche en retard de moins de 24 h affiche 'Aujourd'hui', une tâche due demai…

### 12pets (11pets)
Résumé : présent, test auto 1, présent, non testé 6, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Plusieurs animaux (nom, espèce) | présent, non testé | HomeModule.swift:190 |
| Soins datés: gamelle, vétérinaire, vaccin, anti-puces | présent, non testé | HomeModule.swift:209 |
| Rappel par soin | présent, non testé | HomeModule.swift:226 (seul l'identifiant est testé: LifeOSTests/ReminderIDsTest… |
| Rappels annulés à la suppression de l'animal | présent, non testé | HomeModule.swift:180 |
| Soins du jour dans l'agenda | présent, non testé | TodayAgenda.swift:179 |
| Soins récurrents | manquant | unreachable: PetCare.recurringDays existe (Models_Assets.swift:123) mais aucun … |
| Modifier ou supprimer un soin | manquant | aucune action sur un PetCare dans PetCard |
| Dossier médical, médicaments | manquant | aucun modèle |
| Poids et mesures | manquant | aucun champ |
| Photos et documents | manquant | aucun |
| Aidants partagés | dépendance externe | exige comptes partagés; rien dans le code |
| Export pour le vétérinaire | manquant | aucun export |
| Lien avec la note des aliments (Yuko) | manquant | PetProfile de Yuko non relié à Pet |
| Supprimer un soin (rappel annulé) | présent, non testé | Menu contextuel HomeModule.swift:248 -> removeEvent :266-268 (cancel ReminderID… |
| Date par défaut dans le futur, avertissement si le rappel ne peut pas… | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testPetEventDefaultDate_isInTheFuture… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `HomeModule.swift:226` : La date par défaut est maintenant et 'Me rappeler' est activé: NotificationManager.schedule ignore en silence toute date passée (NotificationManager.swift:78),…

### HomeZen (HomeZada)
Résumé : présent, test auto 1, présent, non testé 2, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| Entretien récurrent avec intervalle | présent, non testé | HomeModule.swift:270 |
| Marquer fait, prochaine date, retard | présent, non testé | HomeModule.swift:256 et :252 |
| Entretiens dus dans l'agenda du jour | présent, test auto | LifeOSTests/AuditFixesLearningTests.swift testMaintenanceNeverDone_isDue (Today… |
| Note par entretien | manquant | unreachable: Maintenance.note jamais saisi ni affiché |
| Rappels notifications | manquant | aucun NotificationManager pour Maintenance |
| Propriétés, pièces, équipements | manquant | aucun modèle |
| Numéros de série, garanties, notices | manquant | aucun champ (DocVault d'Admin non relié) |
| Prestataires et historique d'intervention | manquant | lastDone écrasé, pas d'historique |
| Reçus et inventaire photo | manquant | aucun |
| Projets et budgets | manquant | aucun |
| Valeur du bien et rapports de dépenses | manquant | aucun |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `TodayAgenda.swift:186` : Un entretien jamais fait (lastDone nil, cas 'Fait aujourd'hui' décoché) n'apparaît jamais dans l'agenda, alors que les tâches ménagères jamais faites y apparai…

## 🚗 Mobilité


### Fuelo (Fuelio)
Résumé : présent, test auto 4, présent, non testé 5, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Véhicules: ajout et suppression | présent, non testé | MobilityModule.swift:82 (VehicleEditor) + :55 (suppression avec annulation des … |
| Saisie d'un plein (litres, prix/L, kilométrage) | présent, non testé | MobilityModule.swift:112 FuelEditor, ajout :134 |
| Validation des montants saisis (litres, prix) | présent, test auto | LifeOSTests/AmountInputTests.swift testInvalidTextIsAnErrorNotZero (AmountInput… |
| Consommation moyenne plein à plein (L/100 km) | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testZeroOdometerFillDoesNotBreakAverage,… |
| Coût carburant du mois | présent, non testé | MobilityModule.swift:46 monthCost |
| Échéances assurance et révision avec rappel J-7 | présent, non testé | MobilityModule.swift:61 tuiles, :103 rappels |
| Révision due affichée dans l'agenda du jour | présent, non testé | TodayAgenda.swift:192 |
| Historique des pleins (liste, modifier, supprimer un plein) | manquant | aucun ForEach sur vehicle.fuelLogs dans LifeOS: les pleins ne sont jamais listé… |
| Pleins partiels | manquant | FuelLog (Models_Assets.swift:154) n'a pas de champ plein partiel/complet |
| Plusieurs carburants et recharge électrique | manquant | FuelLog n'a que liters/pricePerL, pas de type d'énergie ni kWh |
| Validation du kilométrage (croissant) | manquant | FuelEditor ne compare pas au plein précédent; vide = 0 accepté (MobilityModule.… |
| Catégories de dépenses et historique d'entretien | manquant | aucun modèle d'entretien ou de dépense véhicule (grep Models_Assets.swift) |
| Suivi des trajets et du kilométrage | manquant | aucun lien Vehicle <-> trajets; TripCO2View est séparé |
| Import / export des données | manquant | aucun export CSV ni import dans MobilityModule.swift |
| Prix des stations | dépendance externe | nécessite un flux de prix carburant (ex: prix-carburants.gouv.fr), rien de bran… |
| Kilométrage obligatoire (vide ou 0 refusé) | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testEmptyOrZeroOdometerIsRejected (FuelM… |
| Rappels assurance / révision suivent le renommage du véhicule | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testVehicleRenameCancelsOldNameReminders… |

Défauts trouvés en lisant le code (1 corrigés sur 2) :

- [partiel] `MobilityModule.swift:118` : Un kilométrage laissé vide devient 0 et est enregistré; trié par odomètre, ce plein devient le premier et la conso affichée (:43) est fausse, très basse. (reste : kilométrage rendu obligatoire, un plein sans kilométrage ne peut pas être stocké)
- [corrigé] `PoleSetups.swift:425` : Le questionnaire Mobilité renomme le véhicule et change la date d'assurance sans annuler ni reposer le rappel (IDs dérivés du nom): l'ancien rappel survit et l…

### CityMappr (Citymapper)
Résumé : présent, non testé 5, manquant 5, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Saisie manuelle d'un trajet (mode + km) | présent, non testé | MobilityTools.swift:94 inputCard, :163 add |
| Estimation CO₂ par mode (ADEME, expliquée) | présent, non testé | MobilityTools.swift:24 gPerKm, mention :78 |
| Coût estimé par trajet | manquant | Tarifs €/km inventés supprimés (fix6, MobilityTools.swift:86 tuile « Distance c… |
| Totaux CO₂ et coût du mois | présent, non testé | MobilityTools.swift:58-62, :87 |
| Historique des trajets | présent, non testé | MobilityTools.swift:138 tripList |
| Supprimer un trajet | présent, non testé | Bouton poubelle visible MobilityTools.swift:148 + menu contextuel :154 -> remov… |
| Recherche de lieux | manquant | aucun MKLocalSearch / géocodage dans MobilityTools.swift |
| Carte | manquant | aucun import MapKit dans MobilityTools.swift |
| Itinéraires multimodaux avec heures de départ/arrivée | dépendance externe | nécessite un moteur d'itinéraires transport (Citymapper/Navitia/GTFS), absent |
| Départs en temps réel et perturbations | dépendance externe | nécessite flux GTFS-RT / API opérateur, absent |
| Guidage étape par étape | dépendance externe | nécessite fournisseur d'itinéraires, absent |
| Trajets enregistrés (domicile/travail) | manquant | aucun favori ni trajet type dans MobilityTools.swift |
| Préférences d'accessibilité | manquant | aucun réglage accessibilité/mobilité réduite |
| Tarifs réels | dépendance externe | nécessite données tarifaires opérateurs; les €/km sont inventés |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `MobilityTools.swift:156` : .swipeActions est posé sur des lignes d'un VStack dans un ScrollView, pas dans une List: aucun trajet ne peut être supprimé.
- [corrigé] `MobilityTools.swift:30` : Le « Coût ce mois » vient de tarifs €/km écrits en dur (0,25 voiture, 0,15 avion…) sans source ni mention, affichés comme une valeur réelle.

### Park Maps (Google Maps)
Résumé : présent, non testé 6, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Mémoriser la position GPS de la voiture | présent, non testé | MobilityTools.swift:295 saveButton, :311 commit (CoreLocation) |
| Note étage / place | présent, non testé | MobilityTools.swift:233 alerte note |
| Itinéraire à pied vers la voiture (Plans) | présent, non testé | MobilityTools.swift:316 openInMaps dirflg=w |
| Temps écoulé depuis le stationnement | présent, non testé | MobilityTools.swift:305 elapsed |
| Effacer la place | présent, non testé | MobilityTools.swift:315 clear |
| Gestion du refus de localisation | présent, non testé | MobilityTools.swift:188, :195, :286 errorCard |
| Photo de la place | manquant | aucun PhotoPicker ni image dans ParkingView |
| Minuteur parcmètre et rappel | manquant | aucune notification ni minuteur dans ParkingView |
| Historique des emplacements | manquant | une seule place en AppStorage (parkLat/parkLon), écrasée à chaque fois |
| Carte affichée dans l'app | manquant | seules les coordonnées texte s'affichent (MobilityTools.swift:266), pas de MapK… |
| Recherche de lieux et fiches détaillées | manquant | aucun MKLocalSearch dans le module |
| Navigation, trafic, modes d'itinéraire | dépendance externe | délégué à Apple Plans par URL, rien dans l'app |
| Listes enregistrées, cartes hors ligne, avis | manquant | aucun code correspondant |

## 👥 Social


### Dexo (Dex)
Résumé : présent, non testé 8, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Contact manuel avec fréquence de contact | présent, non testé | SocialModule.swift:72 ContactEditor |
| Liste « À recontacter » (en retard) | présent, non testé | SocialModule.swift:17, Models_Assets.swift:178 isOverdue |
| Marquer contacté | présent, non testé | SocialModule.swift:65 |
| Import depuis Contacts iOS | présent, non testé | SocialModule.swift:253 ContactImportSheet |
| Dédoublonnage à l'import | présent, non testé | SocialModule.swift:276 par nom exact seulement |
| Relance visible dans l'agenda du jour | présent, non testé | TodayAgenda.swift:217 |
| Suppression d'un contact | présent, non testé | SocialModule.swift:68 menu contextuel |
| Identifiant source stable (CNContact.identifier) | manquant | Contact (Models_Assets.swift:167) ne garde pas l'identifiant, import par nom |
| Notes sur la personne | présent, non testé | Notes affichées dans la ligne SocialModule.swift:67, modifiables par le menu « … |
| Modifier un contact existant | manquant | aucun éditeur pour un Contact existant |
| Groupes / tags | manquant | aucun champ groupe/tag dans Contact |
| Historique des interactions | manquant | seul lastSeen, écrasé à chaque appui |
| Rappels de relance (notification) | manquant | aucune notification posée pour un contact en retard |
| Recherche | manquant | aucun .searchable dans SocialModule.swift |
| Intégrations mail / calendrier | dépendance externe | nécessite accès mail/calendrier (comptes), absent |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `SocialModule.swift:86` : Les notes saisies à la création sont enregistrées mais jamais affichées ni modifiables nulle part: pour l'utilisateur la donnée est perdue.

### Hipp (hip)
Résumé : présent, test auto 2, présent, non testé 4, manquant 6, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Anniversaires triés par proximité | présent, non testé | SocialModule.swift:102, :175 daysUntil |
| Import des anniversaires depuis Contacts | présent, non testé | SocialModule.swift:311 |
| Rappel annuel 3 jours avant à 10 h | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testBirthdayReminderUsesNonLeapYear (Bir… |
| Idées cadeaux (texte) | présent, non testé | affichées SocialModule.swift:124, saisies seulement à la création :85 |
| Délai de rappel configurable | manquant | délai figé à -3 jours SocialModule.swift:164 |
| Occasions personnalisées (mariage, fête…) | manquant | seul Contact.birthday existe |
| Règle du 29 février | présent, non testé | Règle explicite SocialModule.swift:211-222: calcul sur 2001 non bissextile, un … |
| Historique et budget cadeaux | manquant | giftIdeas est une seule chaîne, aucun historique ni montant |
| Cartes / messages | manquant | aucun modèle de message ni partage |
| Import depuis le calendrier | manquant | aucun EventKit dans SocialModule.swift |
| Calendrier familial partagé | dépendance externe | nécessite un backend de partage |
| ID d'événement stable | manquant | ID bday.<nom>.<timestamp> SocialModule.swift:157, dérivé du nom |
| Supprimer un contact annule son rappel d'anniversaire | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testBirthdayIdentifierKeepsLegacyShape (… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `SocialModule.swift:68` : Supprimer un contact dans le CRM n'annule pas son rappel d'anniversaire annuel; reschedule (:160) n'annule que les contacts encore présents, donc le rappel son…
- [corrigé] `SocialModule.swift:164` : Le décalage de 3 jours est calculé sur l'année de naissance: pour une naissance début mars en année bissextile, le rappel tombe 2 jours avant les autres années…

### Partyful (Partiful / Luma)
Résumé : présent, non testé 5, manquant 6, dépendance externe 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer un événement (titre, date, lieu) | présent, non testé | SocialModule.swift:226 EventEditor |
| Liste des événements à venir | présent, non testé | SocialModule.swift:192 |
| Rappel la veille | présent, non testé | SocialModule.swift:243 |
| Suppression avec annulation du rappel | présent, non testé | SocialModule.swift:214 |
| Événement du jour dans l'agenda | présent, non testé | TodayAgenda.swift:198 |
| Modifier un événement | manquant | aucun éditeur pour un SocialEvent existant |
| Pages / liens d'invitation | dépendance externe | nécessite un backend de partage web |
| Invités | manquant | SocialEvent (Models_Assets.swift:185) n'a aucune liste d'invités |
| RSVP / peut-être / liste d'attente | dépendance externe | nécessite identités invités + backend |
| +1 | manquant | aucun champ |
| Sondages | manquant | aucun code |
| Commentaires / mises à jour | dépendance externe | nécessite backend partagé |
| Permissions des invités | manquant | aucun code |
| Intégration calendrier | manquant | pas d'EventKit dans SocialModule.swift |
| Billetterie / check-in / remboursements | dépendance externe | nécessite une couche commerce/paiement |

## 📁 Admin


### Digicoffre (Digiposte)
Résumé : présent, test auto 4, présent, non testé 5, manquant 5, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'un document par photo (1 page) | présent, non testé | AdminModule.swift:111 PhotoPickerButton, une seule image |
| Documents multi-pages conservés | présent, test auto | LifeOSTests/DocVaultPagesTests.swift testFivePageDocumentKeepsEveryPage |
| Lecteur multi-pages | présent, non testé | AdminModule.swift:308 DocumentReader, ouvert :52 |
| Export PDF multi-pages / partage | présent, test auto | LifeOSTests/DocumentPDFTests.swift testOnePDFPagePerImage (DocumentPDF.write ut… |
| Classement par catégorie | présent, non testé | AdminModule.swift:29, :107 |
| Date d'expiration et rappel J-30 | présent, non testé | AdminModule.swift:47, :120 |
| Suppression avec nettoyage des fichiers et du rappel | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testDeletingOneDocumentKeepsTheOthersRem… |
| Import du fichier original (PDF) sans conversion | manquant | DocEditor n'accepte qu'une photo; le scan rasterise les PDF en JPEG (DesktopIma… |
| Recherche plein texte (OCR) | manquant | aucun .searchable ni filtre sur note dans AdminModule.swift |
| Métadonnées / tags modifiables | manquant | aucun éditeur d'un DocVault existant |
| Versions d'un document | manquant | aucun modèle de version |
| Verrou d'accès | présent, non testé | verrou global de l'app seulement, ProfileView.swift:978 (pas propre au coffre) |
| Sauvegarde / restauration | présent, test auto | LifeOSTests/FullBackupTests.swift testBackupThenRestoreRebuildsEverything (doss… |
| Synchro entre appareils | manquant | aucun iCloud/CloudKit pour DocVault |
| Liens de partage contrôlés et connecteurs de comptes | dépendance externe | nécessite backend de partage et connecteurs fournisseurs |

Défauts trouvés en lisant le code (0 corrigés sur 1) :

- [partiel] `ReminderIDs.swift:33` : Les IDs de rappel document/échéance/véhicule ne dépendent que du titre: deux documents de même titre partagent un rappel, le second écrase le premier et suppri… (reste : même titre ET même date partagent encore un identifiant)

### Papernid (Papernest)
Résumé : présent, test auto 1, présent, non testé 5, manquant 6, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Échéance datée par type (impôts, assurance, abonnement) | présent, non testé | AdminModule.swift:164 DeadlineEditor |
| Liste des échéances à venir | présent, non testé | AdminModule.swift:134 |
| Compte à rebours J-x | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testTomorrowDeadlineIsJMinusOne (Deadlin… |
| Rappel 7 jours avant | présent, non testé | AdminModule.swift:181 |
| Suppression avec annulation du rappel | présent, non testé | AdminModule.swift:151 |
| Échéance due dans l'agenda du jour | présent, non testé | TodayAgenda.swift:163 |
| Récurrence / renouvellement automatique | manquant | Deadline (Models_Assets.swift:226) n'a pas de périodicité |
| Lien contrats / abonnements | manquant | Deadline n'est relié à aucun contrat ni DocVault |
| Montants et prévisions de coût | manquant | aucun champ montant sur Deadline |
| Import de factures | manquant | aucun import |
| Comparaison d'offres sourcées | dépendance externe | nécessite source d'offres fournisseurs |
| Suivi de changement / résiliation par confirmation | manquant | aucun statut; le modèle de lettre n'est pas relié |
| Parcours déménagement | manquant | aucun code |
| Infos énergie | dépendance externe | nécessite données énergie vérifiées |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `AdminModule.swift:148` : J-x est calculé depuis maintenant vers une date qui garde l'heure de création: une échéance de demain affiche « Aujourd'hui » dès que l'heure de création est p…

### Lettre-Public (Modèles Service-Public)
Résumé : présent, non testé 3, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Catalogue de modèles (4 courriers) | présent, non testé | AdminModule.swift:193 templates |
| Aperçu éditable | présent, non testé | AdminModule.swift:287 TextEditor |
| Export / copie du texte | présent, non testé | AdminModule.swift:290 ShareLink(item: text) |
| Recherche dans le catalogue | manquant | aucun .searchable dans LetterGeneratorView |
| Source, date, juridiction, version | manquant | Template n'a que name/icon/body (AdminModule.swift:192) |
| Questionnaire conditionnel | manquant | champs [entre crochets] à remplacer à la main |
| Validation des champs obligatoires | manquant | aucun contrôle des [crochets] restants avant export |
| Pièces jointes | manquant | aucun code |
| Export PDF / DOCX | manquant | ShareLink partage du texte brut seulement |
| Sauvegarde des courriers rédigés | manquant | texte en @State (AdminModule.swift:282), perdu au retour |
| Suivi d'envoi (recommandé) | dépendance externe | nécessite un service d'envoi postal |

### Adobo Scan (Adobe Scan)
Résumé : présent, test auto 4, présent, non testé 6, manquant 4, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Scan caméra multi-pages (VisionKit) | dépendance externe | vrai appareil photo requis; DocScan.swift:114, :420 toutes les pages |
| Import photo de la photothèque | présent, non testé | DocScan.swift:176, :117 |
| Import fichier image ou PDF multi-pages | présent, non testé | DocScan.swift:101 fileImporter + DesktopImageHelper.loadPages, non testé |
| Glisser-déposer sur bureau | présent, non testé | DocScan.swift:95, mais PDF limité à la page 1 (voir bugs) |
| Réordonner les pages | présent, non testé | DocScan.swift:313 move |
| Tourner une page | présent, test auto | LifeOSTests/DocumentPDFTests.swift testRotateSwapsDimensions (rotatedClockwise … |
| Retirer une page | présent, non testé | DocScan.swift:326 remove |
| Recadrage et correction de perspective | manquant | aucun CIPerspectiveCorrection / VNDetectRectangles dans LifeOS (seule la caméra… |
| OCR de toutes les pages | présent, non testé | DocScan.swift:335 reanalyze + DocOCR :10, aucun test de DocOCR |
| Classement auto + correction manuelle | présent, test auto | LifeOSTests/AuditFixesAdminTests.swift testUnknownTextIsNotClassified (DocClass… |
| Indice de confiance du classement | manquant | categorize renvoie une chaîne seule, repli « Identité » |
| PDF avec couche texte (recherchable) | manquant | DocumentPDF.swift:33 dessine seulement les images |
| Rangement dans le coffre (toutes les pages) | présent, test auto | LifeOSTests/DocVaultPagesTests.swift testFivePageDocumentKeepsEveryPage (modèle… |
| Export PDF / partage | présent, test auto | LifeOSTests/DocumentPDFTests.swift testWriteProducesReadableFileWithSafeName (v… |
| Recherche dans les scans | manquant | aucune recherche sur DocVault.note |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `DesktopImageHelper.swift:121` : Le glisser-déposer (DocScan.swift:95) passe par loadImage, qui ne rend que la page 1 d'un PDF: les autres pages sont perdues sans message, contrairement au bou…
- [corrigé] `DocScan.swift:23` : VNImageRequestHandler reçoit le cgImage sans l'orientation de l'UIImage: une photo portrait de la photothèque (orientation .right) est lue de travers par l'OCR.
- [corrigé] `DocScan.swift:41` : Tout texte non reconnu, y compris un OCR vide, est classé « Identité » et présenté comme « Classé automatiquement »: classement inventé sans indice de confianc…

## ✈️ Voyage


### TripUp (TripIt)
Résumé : présent, test auto 1, présent, non testé 4, manquant 7, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Créer un voyage (nom, destination, dates, budget) | présent, non testé | TravelModule.swift:62 (TripEditor, bouton Créer), atteint par CategoryHub.swift… |
| Liste des voyages et suppression | présent, non testé | TravelModule.swift:23-31 (TripsView, contextMenu Supprimer) |
| Modifier un voyage après création (dates, nom, budget) | manquant | TripDetailView (TravelModule.swift:73-118) n'édite que notes et valise; aucun é… |
| Checklist valise générée selon durée et climat | présent, non testé | TravelModule.swift:65 + PackingEngine TravelModule.swift:123; aucun test Packin… |
| Cocher / ajouter un objet de valise | présent, non testé | TravelModule.swift:99 (toggle) et :119 (add); pas de suppression d'objet |
| Réservations structurées (vols, hôtels, train, voiture) | manquant | Modèle Trip (Models_Assets.swift:238) n'a que name/destination/start/end/budget… |
| Ajouter un vol Envol au voyage comme note 'non réservé' | présent, test auto | LifeOSTests/FlightSearchTests.swift testTripNoteSaysNotBookedAndDemo (FlightSea… |
| Import / analyse des mails de confirmation | manquant | aucun parseur de confirmation ni import mail dans TravelModule.swift ni Service… |
| Itinéraire à l'heure locale (fuseaux) | manquant | dates en .date seulement (TravelModule.swift:54-55), aucun TimeZone stocké sur … |
| Documents et cartes du voyage | manquant | aucune pièce jointe ni carte dans TripDetailView |
| Partage du voyage | manquant | aucun ShareLink/UIActivityViewController dans TravelModule.swift |
| Suivi des dépenses du voyage | manquant | seul un budget fixe (Trip.budget), aucune dépense liée au voyage |
| Alertes de voyage / statut et perturbations | dépendance externe | demande un flux de statut live (fournisseur de données vols), absent |

### Xchange (XE Currency)
Résumé : présent, test auto 6, présent, non testé 3, manquant 4, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Conversion entre 27 devises | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testECBFirstThenSecondarySourceForMissingC… |
| Taux BCE du jour, datés, avec source par devise | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testParsesECBWithItsDate; affichage Travel… |
| Source secondaire (ExchangeRate-API) pour devises absentes de la BCE | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testECBFirstThenSecondarySourceForMissingC… |
| Cache local avec âge, hors ligne | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testOfflineUsesTheCacheWithItsAge |
| Taux intégrés marqués anciens sans réseau ni cache | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testOfflineWithoutCacheSaysTheRatesAreOld |
| Devise inconnue sans faux taux | présent, test auto | LifeOSTests/ExchangeRatesTests.swift testUnknownCurrencyHasNoRateInsteadOfAFake… |
| Actualisation manuelle et tirer pour rafraîchir | présent, non testé | TravelTools.swift:74 (.refreshable) et :178 (bouton Actualiser), rafraîchit si … |
| Inverser les devises, repères rapides 10/50/100/500 | présent, non testé | TravelTools.swift:114-116 et :203-221 |
| Mention estimation vs taux de la banque | présent, non testé | TravelTools.swift:68 |
| Devises favorites | manquant | aucun favori; liste fixe currencies TravelTools.swift:14 |
| Graphique historique des taux | manquant | ExchangeRates ne charge que eurofxref-daily (ExchangeRates.swift:64), aucun his… |
| Alertes de taux | manquant | aucune alerte ni notification dans TravelTools.swift / ExchangeRates.swift |
| Plus de devises (≈170 chez XE) | manquant | 27 codes en dur TravelTools.swift:14-42 alors que ExchangeRate-API en renvoie b… |
| Transfert d'argent / devis exécutable | dépendance externe | demande un vrai service de paiement; non construit |

### iTraduis (iTranslate)
Résumé : présent, non testé 4, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| 12 phrases de voyage en 5 langues | présent, non testé | TravelTools.swift:257-270, atteint par CategoryHub.swift:785 |
| Prononciation à voix haute (AVSpeech) | présent, non testé | TravelTools.swift:272-281 (PhraseSpeaker), appelé :330 |
| Choix de la langue mémorisé | présent, non testé | TravelTools.swift:285 (@AppStorage phraseLang) et :310 |
| Fonctionne hors ligne (phrases intégrées) | présent, non testé | phrases en dur TravelTools.swift:257, aucune requête réseau |
| Réglage de la vitesse / voix de prononciation | manquant | rate fixe 0.42 TravelTools.swift:279, aucun réglage |
| Catégories et recherche de phrases | manquant | liste plate unique travelPhrases, aucun searchable ni catégorie |
| Favoris et phrases personnelles | manquant | aucun stockage de favoris ni ajout de phrase dans PhrasebookView |
| Collections par destination | manquant | aucune notion de destination dans PhrasebookView |
| Traduction de texte libre | manquant | PhrasebookView ne traduit rien; pas de lien vers TranslationView (#82) |
| Traduction voix / caméra / mode conversation | manquant | aucun SFSpeechRecognizer ni VNRecognizeText dans TravelTools.swift |

### Goggle Traduction (Google Traduction)
Résumé : présent, test auto 2, présent, non testé 5, manquant 8, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Traduction de texte sur l'appareil (Apple Translation) | présent, non testé | Translator.swift:105-123 (.translationTask), atteint par CategoryHub.swift:786;… |
| 12 langues au choix | présent, non testé | Translator.swift:14-27 |
| Inverser les langues (et le texte) | présent, non testé | Translator.swift:139-142 |
| Copier la traduction | présent, non testé | Translator.swift:198 |
| Message d'erreur si paire impossible | présent, non testé | Translator.swift:120 |
| Langues téléchargées par le système / iOS 18+ | dépendance externe | Apple Translation sur appareil, téléchargement de langue proposé par iOS (Trans… |
| Vérification dynamique des langues disponibles | manquant | aucun LanguageAvailability dans le projet (grep) |
| Gestion des téléchargements de langues | manquant | pas de bouton ni écran; commentaire Translator.swift:118 dit que le système s'e… |
| Détection automatique de la langue source | manquant | source fixe @State 'fr' Translator.swift:63, aucun NLLanguageRecognizer ici |
| Historique et favoris de traductions | manquant | aucune persistance dans TranslatorScreen (états @State seulement) |
| Entrée vocale et lecture à voix haute | manquant | aucun Speech/AVSpeech dans Translator.swift |
| Mode conversation | manquant | absent de Translator.swift |
| Traduction par caméra / image (OCR) | manquant | aucun VNRecognizeText ni caméra dans Translator.swift |
| Traduction de documents | manquant | aucun fileImporter dans Translator.swift |
| Deux langues identiques refusées avant l'appel | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testSameLanguageIsBlockedBeforeTheCall … |
| Retraduire avec la même paire de langues | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testSamePairNeedsInvalidate (Translator… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `Translator.swift:183` : Re-traduire avec la même paire de langues crée une Configuration égale à l'ancienne, donc translationTask ne se relance pas (il faut invalidate()): après avoir…
- [corrigé] `Translator.swift:138-146` : Rien n'empêche source = cible (ex. français vers français), ce qui finit toujours en erreur.

### Flighto (Flighty)
Résumé : présent, test auto 2, présent, non testé 4, manquant 4, dépendance externe 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajouter un vol à la main (trajet, compagnie, n°, départ) | présent, non testé | TravelModule.swift:261-305 (FlightEditor), atteint par CategoryHub.swift:788 |
| Compte à rebours avant décollage | présent, non testé | TravelModule.swift:224-228 et :238-245; aucun test |
| Modifier / supprimer un vol | présent, non testé | TravelModule.swift:203 et :235 |
| Statut choisi à la main | présent, non testé | TravelModule.swift:286 (Picker statuses), aucune source |
| Recherche par n° de vol / date / aéroport | manquant | aucune requête; champs texte libres TravelModule.swift:277-283 |
| Statut live, porte, terminal, retards | dépendance externe | demande un fournisseur de données vols en direct, aucun branché |
| Alertes de perturbation | dépendance externe | demande flux live + notifications; aucune notification dans FlightTrackerView |
| Avion entrant | dépendance externe | donnée fournisseur, absente |
| Heures à l'heure locale des aéroports | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testChangingZoneKeepsTheTicketTime, tes… |
| Import calendrier / mail | manquant | aucun import EventKit ni mail dans TravelModule.swift |
| Partage du vol | manquant | aucun ShareLink dans FlightTrackerView |
| Historique des vols / statistiques | manquant | vols passés restent avec 'Départ passé', aucun historique ni stats |
| Statut inconnu tant que non confirmé | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testNewFlightStatusIsUnknown (statut pa… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `TravelModule.swift:158` : Tout vol ajouté reçoit le statut 'À l'heure' sans aucune source: statut inventé affiché comme un fait.
- [corrigé] `TravelModule.swift:283` : L'heure de départ est saisie dans le fuseau de l'iPhone, pas celui de l'aéroport: un vol JFK 18:00 saisi depuis Paris donne un compte à rebours faux de 6 h.

### Envol (Skyscanner (functional reference only, never a provider))
Résumé : présent, test auto 8, présent, non testé 3, manquant 2, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Formulaire aller simple / aller-retour / multi-villes | présent, non testé | FlightCompare.swift:225-307, atteint par CategoryHub.swift:787 |
| Validation avant appel (codes IATA, dates, âges enfants) | présent, test auto | LifeOSTests/FlightSearchTests.swift testValidationBeforeAnyCall et testChildAge… |
| Recherche au moteur LifeOS avec clé app (et 'pas branché' dit sinon) | présent, test auto | LifeOSTests/FlightSearchTests.swift testSearchSendsKeyAndBodyAndDecodes; testNo… |
| Résultats partiels progressifs (flux NDJSON) | présent, test auto | LifeOSTests/FlightSearchTests.swift testStreamLinesPartialDoneError |
| Vrais vols multi-sources (Duffel, 2e source) | dépendance externe | flights-api non déployé, aucune clé Duffel, 2e source sous contrat (flights-api… |
| Groupement sans fusion, offres séparées et différences expliquées | présent, test auto | LifeOSTests/FlightSearchTests.swift testDifferencesExplainUnequalOffers; UI Fli… |
| Tri meilleur / moins cher / plus rapide et filtres (direct, bagage, t… | présent, non testé | FlightCompare.swift:35-38, :129 et FilterChips :345-365, renvoyés au serveur :68 |
| Prix converti avec montant facturé visible | présent, test auto | LifeOSTests/FlightSearchTests.swift testConvertedPriceShowsBilledAmount |
| Heures locales des aéroports | présent, test auto | LifeOSTests/FlightSearchTests.swift testLocalTimeUsesAirportZone |
| Favoris et historique des recherches persistés | présent, test auto | LifeOSTests/FlightSearchTests.swift testLibraryPersistsHistoryFavoritesAlerts |
| Alertes prix serveur, signalées une fois, désinscription | présent, test auto | LifeOSTests/FlightSearchTests.swift testAlertTriggerSignalledOncePerDrop et tes… |
| Ajout au voyage / calendrier marqué non réservé | présent, non testé | FlightCompare.swift:586-624 (addToTrip, addToNewTrip, addToCalendar), activé ap… |
| Réservation / lien vers le vendeur | dépendance externe | Duffel sans lien vendeur; réserver ferait de LifeOS le vendeur (FlightCompare.s… |
| Notifications push des alertes | manquant | seulement notification locale à l'ouverture (FlightCompare.swift:718-728); pas … |
| Recherche d'aéroports par ville / aéroports proches | manquant | saisie de code 3 lettres seulement FlightCompare.swift:309-319 |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `FlightCompare.swift:376 et :380` : group.offers[0] et segments.first! sans garde sur des données serveur: un groupe sans offre ou un trajet sans segment fait planter l'app.

## 🏡 En dehors des catégories


### Réveil (Alarmy)
Résumé : présent, test auto 6, présent, non testé 3, manquant 4, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Heure du réveil et activation | présent, non testé | WakeUpView.swift:165 (DatePicker) et :190-194 (Toggle), atteint par CategoryHub… |
| Jours de répétition | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testOnlyChosenDaysAreScheduled, testEve… |
| Plusieurs alarmes | manquant | une seule heure wakeupHour/wakeupMinute (WakeUpView.swift:6-7), un seul identif… |
| Étiquettes et choix du son | manquant | son fixe .defaultCritical (NotificationManager.swift:40) et SystemSoundID 1005 … |
| Sonnerie plein écran avec arrêt | présent, test auto | LifeOSTests/AlarmManagerTests.swift testStopAndShowBriefingHidesAlarmScreen |
| Snooze réglable (5 à 30 min) | présent, test auto | LifeOSTests/AlarmManagerTests.swift testSnoozeStopsRinging; réglage WakeUpView.… |
| Déclenchement non doublé | présent, test auto | LifeOSTests/AlarmManagerTests.swift testTriggerAlarmIsIdempotent |
| Missions (calcul, photo, code-barres, pas) | manquant | aucune mission dans AlarmManager.swift ni AlarmFullScreenView.swift; arrêt en u… |
| Contrôle du réveil (sleep check après arrêt) | présent, non testé | AlarmManager.swift:144 phase .sleepCheck, sheet LifeOSApp.swift:302 |
| Briefing vocal du matin | présent, non testé | AlarmManager.swift:200-219 et speakDailyPlan :275 |
| Historique des réveils | manquant | aucun journal de réveils dans AlarmManager.swift |
| Sonnerie fiable app fermée (AlarmKit / système) | dépendance externe | seulement notification time-sensitive (NotificationManager.swift:41); sonnerie … |
| Sonnerie 10 min puis snooze automatique (jamais « réveillé » par défa… | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testRingingLastsLongAndEndsInSnoozeNotS… |
| Désactiver annule tous les jours, l'aperçu « dans 5 minutes » et le s… | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testCancelCoversThePreview (Notificatio… |

Défauts trouvés en lisant le code (3 corrigés sur 3) :

- [corrigé] `NotificationManager.swift:44-46` : Le réveil est programmé avec seulement heure+minute en répétition quotidienne: les jours choisis (WakeUpView.swift:218) sont ignorés, il sonne aussi les jours …
- [corrigé] `AlarmManager.swift:67 et :110-113` : La sonnerie s'arrête toute seule après 10 secondes et passe au contrôle du réveil comme si l'utilisateur était levé; quelqu'un qui dort ne sera pas réveillé.
- [corrigé] `WakeUpView.swift:395 et ProfileView.swift:839` : Couper le réveil n'annule que 'lifeos.wakeup': la notification répétée 'lifeos.wakeup.preview' (Réveil dans 5 minutes) continue chaque jour.

### Ton coach (ChatGPT)
Résumé : présent, test auto 5, présent, non testé 4, manquant 5, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Chat avec Apple Intelligence sur l'appareil | dépendance externe | OnDeviceLLM.swift:86-103, demande iOS 26 + appareil Apple Intelligence |
| Fournisseurs cloud avec clé perso (OpenAI, Anthropic, Gemini...) | dépendance externe | LifeOS/Services/AICore/*Provider.swift, écran CoachAIProviderView; clé utilisat… |
| Routage fournisseurs, préférence et plafond de coût | présent, test auto | LifeOSTests/AIModelRouterUsageWireTests.swift testRouterExecute_onSuccess_recor… |
| Repli règles locales sans IA | présent, non testé | OnDeviceLLM.swift:106-112 (LocalCoach.respond) |
| Filet détresse avant tout LLM | présent, test auto | LifeOSTests/CoachSafetyScannerTests.swift testDistress_detectedOnDirectSuicidal… |
| Créer habitude / tâche / rappel depuis le chat | présent, test auto | LifeOSTests/CoachScenarioTests.swift testScenario_createHabitNaturalLanguage |
| Mise à jour du profil depuis le message | présent, test auto | LifeOSTests/IntelligentExtractorTests.swift testExtractAndPersist_returnsChange… |
| Historique par jour (lecture seule) et effacement | présent, non testé | AIAssistantView.swift:1940 CoachHistoryView, ouvert :1045/:1107; clearHistory :… |
| Recherche dans l'historique | manquant | aucun .searchable dans AIAssistantView.swift / CoachHistoryView |
| Conversations / projets séparés | manquant | un seul fil AIMessage, rotation journalière seulement AIAssistantView.swift:176… |
| Analyse d'image | présent, non testé | AIAssistantView.swift:834 analyzeImage via ImageIntel (Vision), PhotosPicker :1… |
| Analyse de fichiers / documents | manquant | fileImporter n'accepte que [.image] AIAssistantView.swift:1139 |
| Dictée vocale et réponse lue à voix haute | présent, non testé | AIAssistantView.swift:1652-1673 (startVoice / stopVoiceAndSend) et :391 CoachVo… |
| Recherche web avec sources | manquant | aucun outil web ni citation dans OnDeviceLLM / AICore Tools |
| Génération d'images | manquant | aucun appel de génération d'image dans AICore |
| Routage dès qu'un fournisseur cloud avec clé est prêt, sans Apple Int… | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift testCloudProviderAloneIsEnoughToRoute (… |

Défauts trouvés en lisant le code (1 corrigés sur 1) :

- [corrigé] `OnDeviceLLM.swift:86-103` : Les fournisseurs cloud configurés par clé (OpenAI, Anthropic...) ne sont appelés que si Apple Intelligence est disponible: sans Apple Intelligence, une clé val…

### Score du jour & bilan (Bevel)
Résumé : présent, test auto 9, présent, non testé 2, manquant 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Score d'énergie rapporté aux critères saisis | présent, test auto | LifeOSTests/EnergyScoreTests.swift testOnlyMoodLoggedIsNotAnEnergyCollapse |
| Couverture des entrées affichée | présent, test auto | LifeOSTests/EnergyScoreTests.swift testCoverageReflectsWhatWasLogged; UI Profil… |
| Score caché si trop peu de données | présent, test auto | LifeOSTests/EnergyScoreTests.swift testMinimumCoverageThresholdIsSane |
| Seul le sommeil de ce matin compte | présent, test auto | LifeOSTests/EnergyScoreTodayTests.swift testYesterdaysSleepIsNotTodaysSleep |
| Jour de repos ne baisse pas le score (habitudes prévues) | présent, test auto | LifeOSTests/EnergyScoreTodayTests.swift testRestDayDoesNotLowerTheScore |
| Objectifs perso (eau, sommeil) utilisés | présent, test auto | LifeOSTests/EnergyScoreTodayTests.swift testPersonalWaterGoalIsUsed |
| Chaque score liste ses entrées | présent, test auto | LifeOSTests/EnergyScoreTodayTests.swift testEveryShownScoreListsItsInputs; UI P… |
| Anneau 'Score du jour' des objectifs + semaine | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift AuditFixesDailyScoreTests testOnlyHabit… |
| Widget score d'énergie | présent, non testé | EnergyScore.swift:93 publishToAppGroup, appelé LifeOSApp.swift:226 |
| Bilan du soir | présent, non testé | EveningSummaryView.swift:37 overallScore, ouvert ShortcutsHomeView.swift:101 |
| Bilan de semaine + analyse du coach + partage | présent, test auto | LifeOSTests/AuditFixesTravelTests.swift AuditFixesWeeklyBilanTests testRestDays… |
| Récupération (VFC, FC repos) / effort / stress séparés | manquant | HRV lu seulement dans SleepModule/HealthService, absent de EnergyScore et Daily… |
| Références personnelles (baseline) et tendances | manquant | aucun calcul de baseline dans EnergyScore*.swift ni DailyScoreRing.swift |
| Corrélations journal / score | manquant | aucune corrélation humeur/habitudes/score dans Services |
| Un seul score cohérent | manquant | trois formules différentes: EnergyScore (Profil), DailyScoreEngine (accueil), E… |

Défauts trouvés en lisant le code (4 corrigés sur 4) :

- [corrigé] `DailyScoreRing.swift:115-118` : L'anneau 'Score du jour' compte toutes les habitudes (archivées, en attente, non prévues ce jour) au dénominateur: un jour de repos baisse le score, défaut déj…
- [corrigé] `DailyScoreRing.swift:128` : moods.first(where:) sur une @Query non triée prend une humeur quelconque du jour, pas la plus récente.
- [corrigé] `WeeklyBilanView.swift:22 et :31` : Le score de semaine filtre isPending mais pas isArchived et ignore le planning: des habitudes archivées ou non prévues font baisser le pourcentage.
- [corrigé] `WeeklyBilanView.swift:319-323` : Sans Apple Intelligence, la réponse des règles locales à l'invite [BILAN_SEMAINE] est affichée et mise en cache pour la journée comme 'Analyse du coach', sans …

### Accueil personnalisable (Widgets iOS)
Résumé : présent, test auto 4, présent, non testé 2, manquant 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Deuxième onglet au choix, persistant, repli sûr | présent, test auto | SecondTabTests |
| Réveil accessible depuis Sommeil | présent, test auto | SecondTabTests.testWakeUpStaysReachableFromSleep |
| Palette couleurs / neutre sans reconstruire les écrans | présent, test auto | LifeOSTests/Build48DefectTests.swift PaletteWithoutRebuildTests |
| Neutre = même luminance (contraste identique) | présent, test auto | ThemePaletteTests |
| Widgets suivent la palette | présent, non testé | WidgetPalette, pas de test (cible widget) |
| Quatre apparences vérifiées sur iPhone / iPad / Mac | manquant | simulateur iPhone seulement |
| Ajouter / retirer / réordonner les cartes de l'accueil | présent, non testé | HomeWidgetEditing.swift, non requalifié |

## 😴 Sommeil


### Nuit sonore (SnoreLab / Sleep Cycle sound events)
Résumé : présent, test auto 7, présent, non testé 5, manquant 3, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Consentement explicite avant toute écoute | présent, non testé | NightSoundView.swift:34 consentCard + requestPermission |
| Écoute micro + classifieur Apple sur l'appareil | dépendance externe | NightSounds.swift:187 start(); needs a real iPhone microphone (simulator refuse… |
| Regroupement des détections en événements | présent, test auto | LifeOSTests/NightSoundsTests.swift testContinuousSnoringIsOneEvent, testGapSpli… |
| Rejet des détections faibles ou trop courtes | présent, test auto | LifeOSTests/NightSoundsTests.swift testWeakOrTooShortDetectionsAreDropped |
| Résumé par catégorie (nombre, minutes) | présent, test auto | LifeOSTests/NightSoundsTests.swift testSummaryCountsAndMinutes |
| Étiquettes Apple vers catégories françaises | présent, test auto | LifeOSTests/NightSoundsTests.swift testAppleLabelsMapToFrenchKinds |
| Durée de conservation et purge (fichiers compris) | présent, test auto | LifeOSTests/NightSoundsTests.swift testRetentionDeletesOnlyOldNights |
| Extraits audio autour des événements + lecture | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testSecondKindDuringOpenClipGetsThatCli… |
| Supprimer un événement | présent, non testé | NightSounds.swift:133 deleteEvent via swipe NightSoundView.swift:138 (not teste… |
| Supprimer une nuit | présent, non testé | NightSoundView.swift:142 -> NightStore.delete NightSounds.swift:127 (exercised … |
| Coupures appel / autre app notées | présent, non testé | NightSounds.swift:242 interrupted, shown NightSoundView.swift:119 |
| Garde stockage plein | présent, non testé | NightSounds.swift:192 |
| Batterie faible | manquant | no batteryLevel/batteryState use in LifeOS; stop(reason:) never called with a r… |
| Tendance des minutes de ronflement sur plusieurs nuits | manquant | summary is per night only (NightSounds.swift:77) |
| Export des nuits | manquant | no export path for NightStore |
| Nuit retrouvée après fermeture forcée de l'app (session close, extrai… | présent, test auto | LifeOSTests/AuditFixesHealthTests.swift testOpenNightIsClosedOnRelaunch, testCl… |

Défauts trouvés en lisant le code (2 corrigés sur 2) :

- [corrigé] `NightSounds.swift:167 + :257` : Detections live only in memory until stop(); if the app is killed overnight the saved session keeps end=nil, is hidden by the list filter (NightSoundView.swift…
- [corrigé] `NightSounds.swift:265-268` : Clips written for detections later dropped by events() (too short or weak) or of a second kind during an open clip are never referenced and stay on disk until …
