# Matrice des fonctionnalités

Généré par `render.py`. États : **vérifié sur appareil**, **présent, test auto**, **présent, non testé**, **manquant**, **dépendance externe**.
Les outils sans matrice ne sont pas encore inventoriés fonction par fonction.

Inventoriés : 18 sur 89.


## 🩺 Santé

- **MediSûr** : pas encore inventorié.
- **Doctolink** : pas encore inventorié.
- **Maple Health** : pas encore inventorié.
- **Mon Espace Vaccin** : pas encore inventorié.

## 🌸 Cycle

- **Floé** : pas encore inventorié.
- **Klue** : pas encore inventorié.
- **Floé Stats** : pas encore inventorié.

## 😴 Sommeil

- **Sleep Circle** : pas encore inventorié.
- **Pzazz** : pas encore inventorié.
- **Rize** : pas encore inventorié.
- **Awaken** : pas encore inventorié.
- **Whoosh** : pas encore inventorié.

## 🥗 Nutrition


### Zerø (Zero)
Résumé : présent, test auto 3, présent, non testé 4, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Protocole 16:8 / 18:6 / 20:4 / OMAD | présent, non testé | FastingView |
| Démarrer / rompre, enregistrement vérifié (erreur affichée) | présent, non testé | FastingView.commit |
| Corriger l'heure de début (72 h max, pas dans le futur) | présent, test auto | LifeOSTests/NutritionLotTests.swift FastingStatsTests.testCorrectedStartIsNever… |
| Notification à l'objectif atteint | présent, non testé | NotificationManager.schedule |
| Historique, objectifs atteints x/y, moyenne | présent, test auto | LifeOSTests/NutritionLotTests.swift FastingStatsTests.testSummaryCountsReachedA… |
| Supprimer une entrée | présent, non testé | appui long |
| Widget jeûne avec le vrai début (corrigé 30 sept. : 14,5 h inventées … | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Durée personnalisée, zones métaboliques | manquant |  |
| Graphiques, série | manquant |  |
| Santé | manquant |  |

### Yumzio (Yazio / MyFitnessPal)
Résumé : présent, test auto 6, présent, non testé 3, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout d'un repas tout-ou-rien (FoodLogService) | présent, test auto | FoodLogServiceTests.testLogWritesEveryLine |
| Validation de la saisie | présent, test auto | FoodLogServiceTests.testInvalidDraftsAreRefusedBeforeAnyWrite |
| Modifier un repas, retour arrière si échec | présent, test auto | FoodLogServiceTests.testEditRecalculatesTheDayAndRevertsOnFailure |
| Supprimer un repas | présent, test auto | FoodLogServiceTests.testDeleteRemovesFromTheDay |
| Changer la date d'un repas | présent, test auto | FoodLogServiceTests.testHistoricalMealDoesNotCountToday |
| Recherche OpenFoodFacts + portion | présent, non testé | FoodEditor |
| Scan code-barres → journal | présent, non testé | CalAIView |
| Objectifs, restant, anneaux, historique 7 jours | présent, non testé | CalAIView |
| Totaux du jour pour le coach | présent, test auto | CrossDomainToolsWireTests.testGetTodayNutrition_withFoodEntries_returnsAggregat… |
| Hors ligne : écran sans message d'erreur réseau | manquant | FoodSearch renvoie [] ("Aucun produit") |
| Ajout direct sur un jour passé | manquant | FoodEditor écrit maintenant |
| Favoris, récents, recettes, micronutriments, Santé | manquant |  |

### Cal Eye (Cal AI)
Résumé : présent, test auto 2, présent, non testé 3, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Analyse photo par le fournisseur de l'utilisateur (clé) | présent, non testé | FoodPhotoAnalyzer |
| Analyse sans clé intégrée à l'app | dépendance externe | serveur à décider par Theo (confidentialité App Store) |
| Reconnaissance sur l'appareil + valeurs Ciqual | présent, test auto | FoodRecognitionPipelineTests |
| Échec de reconnaissance : recherche proposée | présent, non testé | bouton Chercher un aliment |
| Portions corrigibles, une ligne de journal par aliment | présent, test auto | FoodLogService tests |
| Benchmark de vrais plats | présent, non testé | tools/calai-bench (12 photos), pas relancé |

### Yuko (Yuka)
Résumé : présent, test auto 8, manquant 2, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Scan = recherche : base universelle, codes normalisés | présent, test auto | ProductCatalogTests |
| Panne ≠ produit absent | présent, test auto | ProductCatalogTests (réponses mixtes) |
| Note 2.0 (Nutri-Score 2023 officiel, plafond 49) | présent, test auto | ProductScoreTests |
| Cosmétiques : liste de surveillance + annexes CosIng II/III | présent, test auto | CosmeticAnnexTests |
| Nourriture pour chats et chiens | présent, test auto | PetFoodScoreTests |
| Objectifs perso et compatibilité | présent, test auto | ProductFitTests |
| Alternatives avec raisons | présent, test auto | ProductCatalogTests |
| Historique des scans, favoris, enrichissement photo local | présent, test auto | ProductStoreTests |
| Scan caméra et photo d'étiquette sur iPhone | dépendance externe | appareil réel |
| Envoi des photos à Open Beauty / Food Facts | manquant | stockage local seulement |
| Mesure de couverture des produits introuvables | manquant | failed_scans.txt vide |

### Fridgy (Fridgely)
Résumé : présent, test auto 1, présent, non testé 5, manquant 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajouter un article (quantité, catégorie, endroit, péremption) | présent, non testé | PantryEditor |
| Badge J-n / Périmé | présent, non testé | ExpiryBadge |
| Supprimer (enregistrement vérifié) | présent, non testé | FridgeView |
| Envoyer vers la liste de courses sans doublon (ajouté 30 sept.) | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests (règle) ; bouton non t… |
| Idées repas (8 recettes fixes) | présent, non testé | RecipeEngine |
| Partagé avec NoGaspi | présent, non testé | PantryItem |
| Modifier un article | manquant |  |
| Alertes de péremption | manquant |  |
| Ajout par code-barres / ticket | manquant |  |
| Tri / filtre par endroit ou catégorie | manquant |  |

### Bringo (Bring!)
Résumé : présent, test auto 2, présent, non testé 4, manquant 2, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout avec quantité, rayon deviné | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests.testAisleGuess |
| Pas de doublon d'un article à acheter | présent, test auto | LifeOSTests/NutritionLotTests.swift ShoppingListOpsTests.testNoDuplicateOfAnIte… |
| Cocher, supprimer (enregistrement vérifié) | présent, non testé | ShoppingListView.save |
| Retirer les articles cochés (ajouté 30 sept.) | présent, non testé |  |
| Articles cochés → frigo (ajouté 30 sept.) | présent, non testé | moveCheckedToFridge |
| Texte « génère depuis un plan repas » retiré (aucun générateur) | présent, non testé |  |
| Modifier un article | manquant |  |
| Plusieurs listes, liste partagée | dépendance externe | partage = compte en ligne (non livré) |
| Suggestions / récents | manquant |  |

### WaterMind (WaterMinder)
Résumé : présent, test auto 1, présent, non testé 6, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout rapide 250/500/750 ml et quantité libre (1 à 3000 ml) | présent, non testé | HydrationView.add |
| Objectif réglable dans l'écran (ajouté 30 sept.) | présent, non testé | Stepper |
| Annuler / supprimer une prise | présent, non testé | HydrationView.remove |
| Historique 7 jours (ajouté 30 sept.) | présent, non testé | graphique |
| Rappels : autorisation demandée, refus affiché + Réglages (corrigé 30… | présent, non testé | requestAuthorization |
| Widget avec la vraie quantité du jour (corrigé 30 sept. : clé différe… | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Raccourci Siri | présent, non testé | LogWaterIntent |
| Types de boissons | manquant |  |
| Santé (eau) | manquant |  |
| Objectif selon poids / activité | manquant |  |

### SuppSafe (Medisafe)
Résumé : présent, non testé 4, manquant 5, dépendance externe 1

| Fonctionnalité | État | Preuve |
|---|---|---|
| Ajout avec conseil de moment | présent, non testé | SupplementAdvisor |
| Rappel quotidien, vérification « bien pris ? » | présent, non testé | SupplementsView.reschedule |
| Série de prises confirmées | présent, non testé | ConfirmationStore |
| Activer / pause, supprimer (notifications annulées) | présent, non testé |  |
| Refus des notifications affiché | manquant |  |
| Modifier un complément | manquant |  |
| Dose, stock, réassort | manquant |  |
| Plusieurs prises / jours choisis | manquant |  |
| Historique des prises | manquant |  |
| Interactions avec les médicaments (source réelle) | dépendance externe | base de données médicaments |

### Figue (Fig)
Résumé : présent, test auto 3, présent, non testé 2, manquant 4

| Fonctionnalité | État | Preuve |
|---|---|---|
| 16 régimes et allergènes (dont 8 allergènes majeurs UE, ajoutés 30 se… | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testEUMajorAllergensAn… |
| Casher avec règles (corrigé 30 sept. : aucune règle avant) | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testKosherHasRules |
| Expressions sans risque ignorées (noix de coco, lait d'amande) | présent, test auto | LifeOSTests/NutritionLotTests.swift AllergenCheckerTests.testHarmlessPhrasesAre… |
| Résultat honnête : « aucun mot à risque trouvé », pas « compatible » | présent, non testé | DietProfileView |
| Profil appliqué aux produits scannés Yuko | présent, non testé | Yuko.swift |
| Profil appliqué au journal Yumzio | manquant |  |
| Allergènes perso et gravité | manquant |  |
| Plusieurs profils (famille) | manquant |  |
| Traces possibles / contamination croisée | manquant |  |

## 💪 Sport


### Fitbot (Fitbod)
Résumé : présent, test auto 16, présent, non testé 2, manquant 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Semaine éditable (séance, exercices, remplacement) | présent, non testé | GymProgram.swift, pas de test d'écran |
| Démarrer une séance, prescription figée au démarrage | présent, test auto | LifeOSTests/Build48DefectTests.swift testPrescriptionIsFrozenWhenTheSessionStar… |
| Progression depuis les séances TERMINÉES seulement | présent, test auto | LifeOSTests/Build48DefectTests.swift testUnfinishedOrCancelledSessionIsNotABase |
| Deux séances le même jour restent séparées | présent, test auto | LifeOSTests/Build48DefectTests.swift testTwoSessionsTheSameDayStaySeparate (con… |
| Séries typées échauffement / travail / dégressive | présent, test auto | LifeOSTests/Build48DefectTests.swift testWarmupAndDropSetsDoNotCount |
| Sauvegarde : erreur affichée, saisie gardée, aucune série fantôme | présent, test auto | LifeOSTests/Build48DefectTests.swift GymSessionSaveTests |
| Terminer / annuler (garder ou effacer les séries) | présent, test auto | LifeOSTests/Build48DefectTests.swift testFailedFinishLeavesSessionActive, testC… |
| Minuteur de repos réglable | présent, non testé | GymSession.swift |
| Record personnel signalé | présent, test auto | LifeOSTests/Build48DefectTests.swift testPersonalRecordAgainstFinishedHistory |
| Alerte récupération < 48 h (séance du même jour comprise) | présent, test auto | LifeOSTests/Build48DefectTests.swift testRecoverySeesAnEarlierSessionToday (con… |
| Volume hebdo par muscle (séries de travail) | présent, test auto | StrengthProgressionTests |
| Cibles en fourchette (3×8-12), cible par défaut, pas de charge réglab… | présent, test auto | LifeOSTests/Build48DefectTests.swift testTargetRangesDefaultTargetAndMinIncreme… |
| Démonstrations d'exercices | manquant |  |
| Filtre matériel disponible | manquant |  |
| Supersets | manquant |  |
| Générateur de programme selon fréquence, matériel, objectif | manquant |  |
| Parcours complet sur iPhone / iPad / Mac | manquant | non fait |
| Séance liée au jour de programme par identifiant, pas par titre (corr… | présent, test auto | LifeOSTests/Build49DefectTests.swift GymSessionLinkTests |
| Liste d'exercices figée pendant la séance (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testEditingTheProgrammeDoesNotChangeTheRun… |
| Reprise par identifiant, même le lendemain (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testResumeTheNextDayAfterARestDay |
| Repos gardé dans la séance, notification de fin (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testRestEndIsStoredInTheSession |
| Un seul parseur de libellé, noms historiques migrés (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift ExerciseLabelTests, testMigrationGivesHist… |
| Suppression isolée, sans rollback global (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift testFailedDeleteKeepsOtherPendingChanges |

### Stepometer (Pedometer++)
Résumé : présent, non testé 5, manquant 4, dépendance externe 2

| Fonctionnalité | État | Preuve |
|---|---|---|
| Pas du jour lus dans Apple Santé | dépendance externe | HealthService.stepsToday ; données réelles sur appareil |
| Anneau vers l'objectif, objectif réglable et gardé | présent, non testé | FitnessModule.swift StepsView |
| Historique 7 jours, moyenne, objectif atteint x/7 (ajouté 30 sept.) | présent, non testé | HealthService.stepsByDay ; sans données Santé au simulateur |
| Tirer pour rafraîchir (ajouté 30 sept.) | présent, non testé | .refreshable |
| Refus d'accès Santé : réessayer + Réglages | présent, non testé | StepsView EmptyState |
| Distance et kcal | présent, non testé | estimations fixes, sans taille ni poids |
| Distance réelle, étages, calories actives de Santé | manquant |  |
| Historique long (mois, année, records) | manquant |  |
| Widget de pas | manquant |  |
| Notification d'objectif atteint | manquant |  |
| Apple Watch | dépendance externe | pas de cible watchOS |

### Hevvy (Strong / Hevy)
Résumé : présent, test auto 1, présent, non testé 6, manquant 3

| Fonctionnalité | État | Preuve |
|---|---|---|
| Logger une série (type, charge, reps, effort) | présent, non testé | FitnessModule.swift WorkoutEditor |
| Corriger une série existante | présent, non testé | toucher une ligne ; pas de test d'écran |
| Suppression avec erreur visible | présent, non testé | GymSessionService.delete |
| Courbe 1RM par exercice | présent, non testé | ProgressChartCard |
| Conseil de prochaine charge (moteur partagé, séances terminées) | présent, test auto | StrengthProgressionTests |
| Records par exercice | présent, non testé | section Records |
| Routines réutilisables | présent, non testé | via le programme Fitbot (GymDay), pas de routine propre à Hevvy |
| Exercices personnalisés avec groupe musculaire | manquant | texte libre accepté, sans groupe ni matériel |
| Mensurations corporelles | manquant |  |
| Export | manquant |  |

### TabaTime (Tabata Timer)
Résumé : présent, test auto 7, présent, non testé 4, manquant 3, dépendance externe 1

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
| Widget Tabata avec tes vrais réglages (corrigé 30 sept.) | présent, test auto | LifeOSTests/Build49DefectTests.swift WidgetDataTests |
| Préréglages perso nommés | manquant |  |
| Historique des séances dans l'app | manquant |  |
| Annonces vocales / Live Activity | manquant |  |
| Écriture Santé réelle sur appareil | dépendance externe | HealthKit sur iPhone |

### GOMOB (GOWOD / Pliability)
Résumé : présent, test auto 1, présent, non testé 3, manquant 8

| Fonctionnalité | État | Preuve |
|---|---|---|
| 3 routines de mobilité intégrées | présent, non testé | FitnessModule.swift |
| Séance guidée, minuteur par exercice, enchaînement | présent, non testé | GuidedStretchView |
| Moteur de compte à rebours sur l'horloge | présent, test auto | CountdownEngineTests |
| Minuteur séparé du minuteur de focus (corrigé 30 sept. : même clé de … | présent, non testé | CountdownEngine(key: "mobility") |
| Pause / reprise dans la séance | manquant | le moteur sait, l'écran n'a pas de bouton |
| Reprise après relance (exercice en cours) | manquant | index en @State |
| Sons entre exercices | manquant |  |
| Démonstrations (vidéo / animation) | manquant |  |
| Routines perso | manquant |  |
| Évaluation de mobilité / programme adaptatif | manquant |  |
| Historique et écriture Santé | manquant |  |
| Prise en compte dans Streakz | manquant |  |

### Streakz (Streaks)
Résumé : présent, non testé 3, manquant 6

| Fonctionnalité | État | Preuve |
|---|---|---|
| Série de jours d'entraînement consécutifs | présent, non testé | StreaksView |
| Jours actifs, séries totales, 3 objectifs fixes | présent, non testé | StreaksView |
| Calculé depuis les séries muscu (SwiftData) | présent, non testé | @Query WorkoutSet |
| Habitudes perso | manquant | Habitly existe, pas relié |
| Tabata, mobilité et Santé comptés | manquant |  |
| Calendrier / heatmap | manquant |  |
| Meilleure série | manquant |  |
| Fréquence souple, jours de repos | manquant |  |
| Rappels, widget de série | manquant |  |

## ✨ Apparence

- **Umaxx** : pas encore inventorié.
- **TrueSkin** : pas encore inventorié.
- **Progrez** : pas encore inventorié.
- **Mewing Klub** : pas encore inventorié.
- **Wearing** : pas encore inventorié.

## 🧠 Mental

- **Breathwerk** : pas encore inventorié.
- **Headplace** : pas encore inventorié.
- **Endlo** : pas encore inventorié.
- **Daylia** : pas encore inventorié.

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
- **Fabuleux** : pas encore inventorié.

## ✅ Productivité

- **Todoo** : pas encore inventorié.
- **Structurd** : pas encore inventorié.
- **Habitly** : pas encore inventorié.
- **Forêt** : pas encore inventorié.
- **Notio** : pas encore inventorié.

## 💶 Argent

- **Bankino** : pas encore inventorié.
- **Ynabi** : pas encore inventorié.
- **Pocket Money** : pas encore inventorié.
- **Quadricount** : pas encore inventorié.
- **Kapital** : pas encore inventorié.
- **Linxa** : pas encore inventorié.

## 📈 Investissement

- **Finario** : pas encore inventorié.

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
- **Horizo** : pas encore inventorié.
- **Impôts+** : pas encore inventorié.

## 💼 Carrière

- **Huntly** : pas encore inventorié.
- **Zetty** : pas encore inventorié.
- **LinkedUp** : pas encore inventorié.
- **Yoodly** : pas encore inventorié.
- **Welcome to the Djob** : pas encore inventorié.

## 📚 Apprentissage

- **Trilingo** : pas encore inventorié.
- **Anko** : pas encore inventorié.
- **Headwave** : pas encore inventorié.
- **Blinklist** : pas encore inventorié.
- **Coursia** : pas encore inventorié.

## 🏠 Maison

- **NoGaspi** : pas encore inventorié.
- **SuperCuisto** : pas encore inventorié.
- **Sweepo** : pas encore inventorié.
- **12pets** : pas encore inventorié.
- **HomeZen** : pas encore inventorié.

## 🚗 Mobilité

- **Fuelo** : pas encore inventorié.
- **CityMappr** : pas encore inventorié.
- **Park Maps** : pas encore inventorié.

## 👥 Social

- **Dexo** : pas encore inventorié.
- **Hipp** : pas encore inventorié.
- **Partyful** : pas encore inventorié.

## 📁 Admin

- **Digicoffre** : pas encore inventorié.
- **Papernid** : pas encore inventorié.
- **Lettre-Public** : pas encore inventorié.
- **Adobo Scan** : pas encore inventorié.

## ✈️ Voyage

- **TripUp** : pas encore inventorié.
- **Xchange** : pas encore inventorié.
- **iTraduis** : pas encore inventorié.
- **Goggle Traduction** : pas encore inventorié.
- **Flighto** : pas encore inventorié.
- **Envol** : pas encore inventorié.

## 🏡 En dehors des catégories

- **Réveil** : pas encore inventorié.
- **Ton coach** : pas encore inventorié.
- **Score du jour & bilan** : pas encore inventorié.

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

- **Nuit sonore** : pas encore inventorié.
