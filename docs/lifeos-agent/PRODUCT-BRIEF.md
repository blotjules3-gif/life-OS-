# LifeOS — prompt maître de mise à niveau complète

Tu dois améliorer réellement LifeOS, pas seulement corriger les derniers éléments cités. Reprends `/Users/Shared/Claude/apps/lifeos` dans son état actuel, y compris les changements non commités. Préserve le travail existant. Mon objectif : une application utilisable au quotidien, avec des modules profonds, reliés entre eux, sur iPhone et Mac, et notre design minimaliste Liquid Glass partout.

Lis aussi l’annexe `LIFEOS-ANNEXE-88-OUTILS-UPGRADE.md`, située avec ce prompt. Elle énumère les 88 outils, références, exigences et parcours de recette du registre. Ses statuts sont des déclarations à vérifier, pas des preuves de complétude. Ce prompt prime lorsqu’un ancien constat est dépassé.

## 1. Point de départ : ne pas refaire les corrections livrées

La revue actuelle confirme dans le code :

- Yuko : recherche universelle `product_type=all`, normalisation des codes, traces de lookup, cache de secours ; objectifs personnels, historique des scans, alternatives et saisie photo/OCR avec confirmation ; prise en charge spécifique des produits animaux.
- Cal AI : résultats en plusieurs aliments, alternatives, préparation, confiance et question de clarification ; base Ciqual embarquée pour aliments génériques. Ne plus décrire ce parcours comme un simple résultat unique.
- HabitSync : corrections des erreurs de lecture, migration et ordre des actions rapprochées présentes.
- Tabata : palette clair/sombre présente. Restent rendu des états secondaires et cohérence de matière à vérifier.
- Export PDF CV, documents multipages, taux de change et traduction Mac : conserver les avancées.
- 40/40 tests backend vols et contrôle statique glass relancés avec succès pendant cette revue. Ce ne sont pas des tests de parité complète, de recherche aérienne réelle ou de rendu sur tous les écrans.

Écarts encore confirmés : quatre packs Trilingo de seize entrées ; pas de moteur effectif de blocage Screen Time ; pas de capture sonore nocturne ; `onlineAccountsAvailable = false` ; widgets incomplets ; projection FIRE très simplifiée. Le registre garde 76 lignes `not_started` : il n’atteste donc pas une qualification exhaustive, même quand du code existe.

Le disque avait moins de 1 Go libre lors du contrôle. Évalue l’espace avant les builds ; ne supprime que tes artefacts régénérables identifiés. Un build échoué faute d’espace n’est ni un succès ni une raison d’arrêter le reste du travail.

## 2. Méthode obligatoire pour ne plus abandonner 90 % de l’app

Crée un suivi versionné regroupant TOUTES les demandes ci-dessous et les 88 outils. Pour chacun : capacités de référence et version/pays/offre comparée, routes et sous-pages, comportement actuel, manque concret, dépendances, travaux, tests et preuve. Recherche les outils accessibles hors catégories également. Un écran ouvrable ou une suite verte ne signifie pas un produit complet.

Travaille par parcours verticaux : entrée → action réelle → résultat → sauvegarde → réouverture → correction/suppression → effets sur accueil/autres modules/widgets. Après chaque lot, teste, examine le résultat et corrige avant de le clore. Ajoute des tests de régression qui auraient détecté le défaut, pas uniquement des tests qui répètent l’implémentation.

Exécute les routes de navigation sur iPhone, iPad et vrai Mac/Catalyst. Le mode `-routeSmoke` est utile, mais ne prouve pas que les clics, formulaires, retours, feuilles et actions fonctionnent. Couvre clavier, redimensionnement, safe areas, Dynamic Type, VoiceOver et permissions refusées.

Ne marque jamais « terminé » un parcours dépendant d’un fournisseur non connecté, d’un mock ou d’une autorisation absente. Prépare toute l’intégration possible, expose la dépendance exacte et continue les autres lots. Une limite de session impose un checkpoint précis avec prochain travail, pas une déclaration « app terminée ».

## 3. Yuko : couverture, scan et résultats cohérents

Répare en priorité le cas utilisateur « absent au scan alors que trouvé par nom ». Utilise la même identité canonique pour scan, recherche, cache, historique et contributions, sans fusionner des variantes de formulation/pays/conditionnement. Teste EAN/UPC/GTIN, zéros initiaux, caméra et recherche manuelle.

**Point nouveau à reproduire dans `ProductCatalog.lookup` :** le résultat final peut devenir `.notFound` si au moins une tentative est absente, même lorsqu’une autre est indisponible. Une absence sur une forme équivalente ne doit pas masquer une panne sur une source pertinente. Teste explicitement réponses mixtes 404/429/503, cache vide/présent et fallback. Affiche « recherche incomplète, réessayer » lorsque l’absence n’a pas été établie.

Élargis concrètement les sources : alimentation, boissons, suppléments/protéines, cosmétiques de supermarché/pharmacie/Sephora/marques privées, Europe et Amérique. Open Food Facts/Beauty/Pet ne constituent pas une couverture universelle. Évalue catalogues fabricants, flux distributeurs et contributions avec droits de réutilisation, rapprochement GTIN, provenance et mise à jour. N’invente pas une couverture « tous les produits ».

Chaque fiche : photo, marque, format, pays/formulation, composition intégrale, allergènes, valeurs et unités, note expliquée, sources/fraîcheur, historique et comparaison. Scanner accessible dès l’accueil Yuko, historique daté des vrais scans et recommandations comparables avec raisons. Si image absente, proposer contribution et état explicite ; ne montrer aucune photo d’un autre produit.

Produit inconnu : photo recto/code, ingrédients et tableau nutritionnel, extraction locale quand possible, revue/correction avant sauvegarde, persistance immédiate dans le catalogue utilisateur, puis enrichissement/contribution. Tester colonnes par portion/par 100 g, sel/sodium, virgules, plusieurs langues et données manquantes. Ne pas promettre une IA distante gratuite illimitée 24/7 ; fournir un fonctionnement local utile et une infrastructure mesurée si nécessaire.

Constitue un benchmark réel d’au moins 100 codes équilibré par catégorie/pays, dont produits absents, erreurs réseau et cas utilisateur. Publie séparément reconnaissance, complétude, photos, notes calculables et latence. Ajoute les références utilisateur exactes dès qu’elles sont disponibles, sans attendre pour les autres tests.

## 4. Yuko : score /100, méthode et objectifs

L’objectif est de se rapprocher de la méthode publique Yuka, avec davantage de catégories. Vérifie nutrition 60 %, additifs 30 %, bio 10 %, seuils et plafonds ; compare au simulateur/exemples publics. Les cosmétiques et produits animaux nécessitent des méthodes séparées. Ne revendique pas une note identique sans la démontrer.

Reproduis le Coca signalé à 50 avec le code/formulation exacts ; décompose le calcul, unités, sucre, catégorie boisson, additifs et plafonds. Pas de règle spéciale « Coca = 10 ». Les noms chimiques et le gras total ne constituent pas à eux seuls une règle fiable de pénalisation. Utilise une méthode documentée, des sources et des règles adaptées à la catégorie.

Cherche à noter chaque produit évaluable en complétant les données ; n’invente jamais une note pour combler un trou. Les ingrédients non évalués ne sont pas automatiquement sans risque. Explique ce qui est connu, incertain ou absent et comment compléter la fiche. Les fiches d’ingrédients signalés doivent expliquer les effets documentés et leur contexte, sans transformer une association ou une restriction en certitude individuelle.

Préserve les objectifs éditables depuis la fiche et l’accueil : prise de muscle/masse, perte de poids et autres objectifs. Affiche séparément note générale et adéquation personnelle, avec raisons. Complète la méthode des suppléments au lieu de leur appliquer aveuglément celle des aliments. Audite aussi la nouvelle méthode animaux avant toute promesse de validation nutritionnelle ; pas de mélange avec le journal alimentaire humain.

## 5. Trilingo : véritable apprentissage durable

Construis un moteur de cours, pas une liste plus longue de flashcards.

- Questionnaire obligatoire avant le premier accès : langue source/cible, expérience, objectif, temps quotidien. Quitter reste possible ; ignorer le questionnaire n’ouvre pas le cours. Réglages modifiables ensuite, sans le redemander quotidiennement.
- Placement adaptatif court ou parcours débutant, niveau estimé expliqué et possibilité de réévaluation.
- Au moins 180 jours de pratique pertinente pour chaque cours déclaré complet, avec progression par unités, grammaire, vocabulaire, dialogues, lecture, écoute, dictée, écriture et oral ; révisions espacées, erreurs et bilans de maîtrise. Ne pas multiplier artificiellement les jours en recyclant seize phrases.
- Audio naturel adapté à chaque langue, réécoute/vitesse, reconnaissance vocale et retour utile ; déclarer les limites de prononciation et les modes sans micro.
- Rappel quotidien à l’heure choisie avec permission, fuseau, annulation après séance, désactivation et aucun doublon.
- Catalogue largement au-delà de quatre langues : architecture multilingue, RTL/alphabets/translittération, contenu et voix par paire de langues. Objectif toutes les langues supportables ; aucune langue annoncée disponible avec un cours vide. Documenter la couverture et les cours restant à produire.
- Contenus originaux/réutilisables, validation linguistique, versionnement, téléchargement et progression durable. Une génération IA non contrôlée ne constitue pas un cursus.

Recette : nouveau compte → configuration → placement → séance multimodale → lendemain → révision → changement de langue → retour au progrès → simulation de 180 jours. Ne pas promettre un niveau de maîtrise garanti par la seule durée.

## 6. Détox écran et sommeil nocturne

**Détox :** implémenter FamilyControls, sélection système des applications, ManagedSettings et DeviceActivity avec extensions, App Groups et autorisations de distribution requises. Réaliser autoriser → sélectionner → bloquer → constater le shield dans l’app ciblée → pause/reprise → fin/suppression. Tester LifeOS fermé, verrouillage, reboot, fuseau et révocation. Un minuteur local ne doit pas afficher « blocage actif ». Sur Mac, vérifier une solution réellement supportée, sans supposer que les API iPhone suffisent.

**Nuit :** ajouter une session sonore nocturne distincte du journal de rêves : consentement, début/fin, courts extraits d’événements, timeline, écoute, suppression/rétention et stockage local par défaut. Tester interruptions, appels, écran verrouillé, batterie et stockage plein. Les événements estimés ne constituent ni diagnostic ni mesure des phases du sommeil. Vérifier séparément les réveils, notifications et missions sur appareil réel, app fermée.

## 7. Cal AI et données communes

Préserve la liste d’aliments et Ciqual. Reproduis les erreurs de reconnaissance comme légumes → soupe sur un jeu de photos annotées ; compare moteurs, faux aliments, omissions, portions et macros. Trace quel moteur a répondu ; n’assimile pas fallback local et modèle multimodal distant.

L’utilisateur corrige chaque aliment, poids, préparation, huile/sauce avant confirmation. Distingue observations, hypothèses et valeurs nutritionnelles de référence. Le moteur principal doit fonctionner pour l’utilisateur normal sans clé personnelle si c’est la promesse produit ; préparer service sécurisé, coûts, quotas, consentement et fallback, puis vérifier son déploiement réel.

Une confirmation crée une seule écriture canonique. Journal, dashboard, objectifs, protéines/macros et widgets doivent tous se mettre à jour. Correction/suppression annule les contributions correspondantes. Tester doublons, relance, annulation, erreurs réseau et données tardives. Appliquer cette cohérence aussi aux habitudes, entraînements, sommeil, finances et score quotidien.

## 8. Comptes et questionnaires

Créer un compte avant le questionnaire initial via Apple, Google, Facebook ou email. Implémenter les parcours complets de connexion, retour OAuth, annulation, email/vérification/réinitialisation, reprise de session, liaison d’identités et suppression de compte. Ne pas laisser des boutons décoratifs. Configurer backend et fournisseurs ; les identifiants manquants doivent être des dépendances précises, pas un faux succès local.

Préserver les brouillons de questionnaire, reprise après « passer », bouton permanent pour compléter, état terminé distinct et édition des objectifs à tout moment. Vérifier chaque catégorie et la propagation aux recommandations. Exception explicite : configuration minimale Trilingo obligatoire. Préserver/migrer les données locales sans perte lors de la connexion ; tester déconnexion et isolation entre comptes.

## 9. Profondeur fonctionnelle des autres catégories

Applique l’annexe aux 88 outils. Les points suivants sont prioritaires, pas une dispense pour les autres :

- **Sport :** questionnaire morphologie/objectifs/expérience/contraintes/matériel/disponibilités, plans personnalisés orientés machines et poids libres, substitutions, progression, charges, repos et historique. L’utilisateur peut modifier le plan. Réparer navigation Mac FitBot/Hevy/GoMob/pas et vérifier leurs parcours réels.
- **Investissement :** cours datés et provenance, recherche/watchlist, transactions/frais/devises, scénarios persistants comparables avec rendement nul/négatif, inflation et apports. Le capital investi ne doit pas être automatiquement tout le patrimoine net, immobilier compris. Séparer hypothèses de résultats garantis.
- **Argent :** ledger partagé, imports, budgets reliés aux transactions, abonnements, remboursements/groupes et agrégation réelle si promise.
- **Productivité :** tâches/récurrence/sous-tâches, calendrier et conflits, habitudes/annulation, notes structurées/recherche/pièces jointes, focus durable et interconnexion.
- **Santé/cycle :** prises réelles et historique, rappels fiables, dossiers/documents, mesures sourcées, corrections rétroactives, incertitude des prédictions ; pas de réservation médicale fictive.
- **Carrière/apprentissage :** CV mis en page, candidatures/documents, entretiens adaptatifs, offres actualisées, flashcards avancées et catalogues pédagogiques substantiels.
- **Maison/mobilité/social :** quantités/lots/recettes complètes, tâches partagées, soins animaux/maintenance, véhicules, vrais itinéraires si promis, contacts dédoublonnés, invitations/RSVP réels.
- **Administration :** capture/import multipage, crop/rotation/perspective, PDF avec texte OCR recherchable, classement/export/partage, sauvegarde et restauration vérifiées.
- **Apparence/mental :** parcours complets, historiques, photos/documents et recommandations contextualisées ; pas seulement un formulaire et un compteur.

## 10. Voyage : concurrent indépendant de Skyscanner

Ne pas utiliser l’API Skyscanner ni intégrer son interface. Compléter le moteur indépendant avec sources aériennes réellement connectées, recherche lieux/dates/flexibilité, filtres, bagages, devises, prix totaux, comparaison d’offres, expiration/revalidation et passage vendeur/réservation selon le modèle retenu.

Le connecteur Travelport est encore un squelette ; deux sources démo ne constituent pas une comparaison multi-fournisseurs. Implémenter les connecteurs accessibles et traiter contrats/credentials comme dépendances documentées. Relier voyage/itinéraire, suivi de vol et alertes réellement livrées, sans présenter des données saisies ou fictives comme temps réel.

## 11. Widgets iPhone ET Mac pour tous les outils pertinents

Inventorier chaque outil avec widget proposé, données, action et lien profond : cours actions/devises, tâches, habitudes, calories/macros, photo repas, hydratation, sport, jeûne, sommeil, langues, rappels, voyages, etc. Pour un module sans donnée utile à exposer, prévoir un raccourci contextualisé et expliquer le choix. Une Live Activity, un contrôle et un widget ne sont pas trois outils différents.

App Groups, instantanés datés, App Intents, actions idempotentes, rafraîchissement cohérent, état hors-ligne et isolation du compte. Le widget photo ouvre directement le parcours caméra dans l’app ; ne pas promettre une caméra intégrée au widget. Vérifier chaque famille supportée sur appareil/Mac, app fermée et après changement/suppression des données.

## 12. Design Liquid Glass partout et mouvement Lusion

Les références initiales Apple restent le critère : boutons Nouvelle tâche, petits contrôles, grandes cartes d’information, boîtes contenant d’autres boutons, sidebar, sélection, cercles de jours, onglets, formulaires, fenêtres et toutes les sous-pages. Même système sur iPhone et Mac, en clair/sombre. Ne pas obtenir des contours gris autour d’aplats blancs opaques en guise de verre.

Auditer matériaux, transparence, reflets de bord, intérieur, ombre, géométrie et lisibilité sur le même fond que les références. Utiliser les capacités natives disponibles avec fallback cohérent ; ne pas prétendre qu’une valeur de pixel ou le script glass prouve la ressemblance complète. Tester surfaces imbriquées, défilement, contenu sous les barres et contrastes sans rendre les textes transparents.

S’inspirer de https://lusion.co pour transitions, profondeur, graphismes réactifs au scroll et retours d’interaction. Conserver le minimalisme et créer un système partagé de mouvement. Réduire les animations respecté, éléments hors écran suspendus, pas de scroll détourné, aucun effet bloquant les clics. Mesurer fluidité, batterie et chauffe. Fournir preuves visuelles clair/sombre sur les familles d’écrans, dont Tabata prêt/en cours/pause/fin, et pas uniquement l’accueil.

## 13. Outil créateur vidéo demandé, à ne pas oublier

Ajouter un module créateur une fois les fondations prioritaires stabilisées : import vidéo, timeline, détection de parole/silences avec seuils réglables et aperçu, suppression des blancs non destructive, transcription/sous-titres éditables, effets/transitions/titres animés, formats sociaux et export avec audio synchronisé. Permettre d’annuler et conserver l’original. L’intégration des outils YouTube personnels nécessite leurs fichiers/API : préparer les points d’intégration sans inventer leur fonctionnement. « Plus d’effets que CapCut » reste une ambition à transformer en catalogue et preuves, pas une affirmation marketing.

## 14. Ordre d’exécution et définition de fini

1. Actualiser les 88 lignes, réparer navigation et pertes/incohérences de données ; reproduire les échecs Yuko et repas.
2. Rendre comptes, Trilingo, détox et gym réellement utilisables ; continuer enrichissement Yuko/Cal AI et capture nocturne.
3. Achever les parcours métier des autres catégories et widgets, connecter les fournisseurs nécessaires.
4. Qualifier design/mouvement sur chaque famille d’écrans ; compléter créateur vidéo et exigences restantes.

Ne reporte pas tous les tests au dernier lot : chaque livraison contient implémentation, tests pertinents et recette réelle. Conserve un journal court : terminé avec preuve / partiel avec manque précis / bloqué avec action externe précise / non testé. Fournis la version installée réellement examinée et ne mesure pas l’onboarding par erreur à la place de l’accueil. Pas de déploiement présenté comme accompli sans résultat vérifié.

L’application n’est « complète » que lorsque les exigences et parcours retenus dans les 88 lignes, plus comptes/widgets/design/vidéo, sont satisfaits ou explicitement laissés ouverts. Continue le travail tant qu’un lot indépendant est réalisable. Le résultat attendu est du logiciel utilisable, des données utiles et des preuves, pas davantage de promesses.

## Références à vérifier pendant l’implémentation

- Yuka : https://help.yuka.io/l/en/article/ijzgfvi1jq et https://help.yuka.io/l/en/article/ih5pet4ffc ; simulateur https://editor.yuka.io/
- Open Food Facts universel : https://github.com/openfoodfacts/openfoodfacts-server/blob/main/docs/api/tutorials/scanning-cosmetics-pet-food-and-other-products.md
- Duolingo : https://blog.duolingo.com/duolingo-101-how-to-learn-a-language-on-duolingo/ et https://blog.duolingo.com/spaced-repetition-for-learning/
- Apple Family Controls : https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Mouvement : https://lusion.co/
