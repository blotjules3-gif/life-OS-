# Matrice des fonctionnalités

Généré par `render.py`. États : **vérifié sur appareil**, **présent, test auto**, **présent, non testé**, **manquant**, **dépendance externe**.
Les outils sans matrice ne sont pas encore inventoriés fonction par fonction.

Inventoriés : 6 sur 89.


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

- **Zerø** : pas encore inventorié.
- **Yumzio** : pas encore inventorié.

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
- **Yuko** : pas encore inventorié.
- **Fridgy** : pas encore inventorié.
- **Bringo** : pas encore inventorié.
- **WaterMind** : pas encore inventorié.
- **SuppSafe** : pas encore inventorié.
- **Figue** : pas encore inventorié.

## 💪 Sport


### Fitbot (Fitbod)
Résumé : présent, test auto 10, présent, non testé 3, manquant 5

| Fonctionnalité | État | Preuve |
|---|---|---|
| Semaine éditable (séance, exercices, remplacement) | présent, non testé | GymProgram.swift, pas de test d'écran |
| Démarrer une séance, prescription figée au démarrage | présent, test auto | LifeOSTests/Build48DefectTests.swift testPrescriptionIsFrozenWhenTheSessionStar… |
| Progression depuis les séances TERMINÉES seulement | présent, test auto | LifeOSTests/Build48DefectTests.swift testUnfinishedOrCancelledSessionIsNotABase |
| Deux séances le même jour restent séparées | présent, test auto | LifeOSTests/Build48DefectTests.swift testTwoSessionsTheSameDayStaySeparate (con… |
| Séries typées échauffement / travail / dégressive | présent, test auto | LifeOSTests/Build48DefectTests.swift testWarmupAndDropSetsDoNotCount |
| Sauvegarde : erreur affichée, saisie gardée, aucune série fantôme | présent, test auto | LifeOSTests/Build48DefectTests.swift GymSessionSaveTests |
| Terminer / annuler (garder ou effacer les séries) | présent, test auto | LifeOSTests/Build48DefectTests.swift testFailedFinishLeavesSessionActive, testC… |
| Reprise d'une séance en cours après relance | présent, non testé | séance stockée en base, bouton Reprendre ; pas de parcours fait |
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
- **Stepometer** : pas encore inventorié.

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
- **TabaTime** : pas encore inventorié.
- **GOMOB** : pas encore inventorié.
- **Streakz** : pas encore inventorié.

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
