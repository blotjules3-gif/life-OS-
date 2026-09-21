# WORKLOG — remise a niveau des modules

Derniere mise a jour: 2026-09-21. A lire d'abord par toute session qui reprend.

## Le piege a connaitre avant de toucher au code

`AppCategory.destination` rend **`CategoryHubView`** (`Core/CategoryHub.swift`).
C'est le SEUL chemin que l'utilisateur emprunte, et il liste **79 outils**.

Les fichiers `Modules/*Module.swift` contiennent une generation PRECEDENTE
d'ecrans de categorie: **16 des 17 `*HubView` ont zero reference** dans tout le
projet (seul `MedicalHubView` est encore utilise). Cela represente environ
**7 439 lignes injoignables**, avec leurs bannieres "bientot disponible".

Consequence: la plupart des `IntegrationNotice` ne sont JAMAIS vues par un
utilisateur. Ne pas perdre de temps dessus. Verifier d'abord qu'un ecran est
atteignable depuis `CategoryHub.swift`.

Attention: les fichiers `*Module.swift` contiennent AUSSI des vues bien
vivantes (`StepsView`, `PortfolioView`, `TimeBlockView`...). Le fichier est
mort, ses vues ne le sont pas. Ne pas supprimer un fichier en bloc.

## Fait et verifie

- **Cours crypto reels** (`Services/PriceService.swift`, neuf).
  CoinGecko `/coins/markets`, public, sans cle. Endpoint verifie en vrai:
  btc 70 690 EUR, eth 2 299,1, sol 96,23. Cache 60 s contre le 429.
  Branche dans `PortfolioView`: bouton actualiser, pull-to-refresh, ecriture
  dans le modele. Actions et ETF restent manuels et l'ecran le dit.
- **Time-blocking persistant** (`Modules/ProductivityModule.swift`).
  `TodoItem.blockStart/blockEnd` existaient et RIEN ne les ecrivait. Creneaux
  enregistres, relus a l'ouverture, effacables. Corrige aussi: generer le soir
  rendait une liste vide sans explication (planifie demain), et deux force
  unwrap sur des dates.
- **Pas: vrai parcours de permission** (`Modules/FitnessModule.swift`).
  L'ecran disait a l'UTILISATEUR d'"activer la capability HealthKit dans
  Xcode", sans action possible. Remplace par un bouton d'autorisation et un
  lien vers les Reglages (iOS ne redemande jamais une permission refusee).
- **Detox ecran: remise a zero quotidienne** (`Modules/MindModule.swift`).
  Le compteur "aujourd'hui" cumulait depuis l'installation.

## Faux positifs verifies (ne pas y revenir)

`PetsView`, `VehicleListView`, `WardrobeView`, `DocVaultView`,
`DietProfileView`, `ScreenDetoxView`: signales par mes heuristiques, en fait
fonctionnels (CRUD reel, persistance reelle).
Barcode (`FoodSearch.swift`), OCR (`DocScan.swift`), analyse faciale
(`FaceAnalysis.swift`): reellement implementes et correctement branches
depuis `CategoryHub`.

## Bloque par un tiers, pas par le code

- Bloqueur d'apps et temps d'ecran systeme: entitlement FamilyControls a
  demander a Apple.
- Detection automatique d'abonnements: agregation bancaire, service paye et
  reglemente.
- Reveil intelligent: analyse du sommeil nuit par nuit.
- Cours des ACTIONS: aucune API gratuite sans cle.
- CV, mock interview, resumes de livres: demandent une cle LLM. La couche
  existe deja (`Services/AICore`), il ne manque que la cle.

## Tests

`.github/workflows/tests.yml` lance la suite sur simulateur.
Dernier passage: **309 tests, 0 echec**.

Le job peut malgre tout finir en rouge: le runner plante parfois au demontage
du simulateur (erreurs CoreSimulator / SQLite). Lire le nombre d'echecs dans
le journal, pas seulement la pastille du job.

Trois pieges corriges sur ce job, a ne pas reintroduire:
- La cible LifeOSTests visait iOS 26.5 alors que l'app vise 17.0, donc AUCUN
  simulateur ne pouvait lancer les tests. Ils ne se construisaient jamais.
- Le tube finissait par `|| true`, ce qui remet PIPESTATUS a zero: le job
  passait au vert alors que la compilation des tests echouait.
- Ne jamais coder en dur un nom de simulateur, le parc des runners change.

Deux defauts pre-existants sont sortis des que les tests ont pu tourner:
une suite qui ne compilait pas (isolation MainActor) et un test qui supposait
le trousseau accessible.

## Regle de vocabulaire (m'a pris au piege)

Dans l'interface on dit "ton coach", jamais "IA" ni "LLM". Un test scanne les
chaines et echoue sinon. Mes six chaines ajoutees violaient toutes la regle.

## Phase 2 (meme session)

Fait et verifie, chaque point construit et teste:
- **Analyse photo REELLE sans cle**: Vision sur l'appareil, puis vraies
  valeurs 100 g d'OpenFoodFacts, puis portion modifiable. Mediane de 9
  resultats, pas le premier (base collaborative). Liste editable, ajout
  manuel, une ligne de journal par aliment.
- **Bug trouve par son propre test**: "cake" masquait "pancake", une assiette
  de pancakes devenait un gateau. Le mot cle le plus LONG gagne maintenant.
- **Cours des actions** via le point graphique public de Yahoo, sans cle,
  converti en euros (EURUSD=X). Stooq est mort, il repond par un defi
  anti-robot. Crypto et actions rafraichies separement.
- **Budget mensuel** remis a zero au changement de mois (periodStart).
- **Hydratation**: on peut enfin retirer une prise d'eau.
- **Coffre-fort**: ImageStore rendait un nom de fichier meme quand l'ecriture
  echouait, donc la fiche survivait sans son image. Rend nil desormais.
- **Plantage** au bouton Resilier: le nom d'abonnement etait interpole puis
  force-deballe. "Disney +" suffisait. Reecrit avec URLComponents.
- **Activite en direct du reveil** et **10 sauvegardes** ne ratent plus en
  silence.
- **CI verte**: 335 tests, 0 defaillance. Le simulateur est efface avant la
  campagne, et le verdict se lit sur le compte d'echecs, pas sur le seul code
  de sortie de xcodebuild (qui rend 65 sur un incident de demontage).

Pieges a ne pas repeter:
- LifeOSTry prend une autoclosure qui throw: le `try` est obligatoire, donc
  l'appel ne peut PAS etre ecrit directement dans une fermeture non throwing
  (action de bouton, setter de Binding). Passer par une petite fonction.
- Ancrer un remplacement sur une chaine de texte sans borner la structure
  visee: deux fois de suite du code a atterri dans la mauvaise vue d'un
  meme fichier. Verifier quelle structure contient la ligne AVANT de
  construire.

## BLOQUE: la CI est coupee par la facturation GitHub (21 septembre 2026)

Depuis 10h46, TOUS les jobs du depot de construction echouent en 5 a 10
secondes, sans qu'aucune etape ne demarre et sans runner attribue, aussi bien
sur `ubuntu-latest` que sur `macos-26`. Le message est dans l'annotation du
job, pas dans les logs (les logs n'existent meme pas):

    The job was not started because recent account payments have failed or
    your spending limit needs to be increased.

Pour le relire soi-meme, les logs ne servent a rien, il faut les annotations:

    gh api repos/leilajkaseme-hub/lifeos-build/actions/runs/<id>/jobs \
      -q '.jobs[].check_run_url'
    gh api <check_run_url>/annotations

Consequence: plus aucun build, donc plus aucun envoi TestFlight, tant que la
facturation du compte `leilajkaseme-hub` n'est pas reglee. Seul Theo peut le
faire, dans Settings puis Billing & plans. Les minutes macOS comptent dix fois
plus que les minutes Linux, c'est ce qui vide le quota si vite.

Dernier etat verte connu, avant la coupure: **360 tests, 0 defaillance,
0 erreur de compilation**.

## Verifier sans Xcode et sans CI

Ce Mac n'a que les Command Line Tools, donc l'app iOS ne se construit pas
ici. Mais `swiftc` 6.4 est bien la, et deux controles reels tournent en local.

`./scripts/parse-check.sh` lit la grammaire de tous les fichiers Swift
(299 fichiers, quelques secondes). Ca attrape exactement la categorie
d'erreur qu'un remplacement de texte introduit: accolade en trop, structure
coupee, code atterri hors de sa structure. Ca ne verifie AUCUN type: une vue
SwiftUI mal typee passe ce controle.

`./scripts/run-logic-tests.sh` EXECUTE pour de vrai les suites de logique
pure, sur les MEMES fichiers de test que la CI, via un faux XCTest
(`scripts/localtests/Shim.swift`). Aujourd'hui: ListingParser 24 controles,
CycleStats 20, MedicationSchedule 22, tous verts. Seules les regles qui ne
dependent que de Foundation peuvent y passer, donc rien de SwiftUI ni de
SwiftData. C'est justement la partie ou une erreur donne un chiffre faux a
l'utilisateur.

Ajouter une suite: une ligne dans le tableau `SUITES` du script.

## Faux positifs verifies cette passe (ne pas y revenir)

- **Divisions par zero**: les 20 endroits qui divisent par un `.count` ont
  tous ete relus un par un. Tous sont gardes par un `guard !x.isEmpty` ou un
  `if x > 0` juste au-dessus. Rien a faire.
- **Erreurs avalees**: pas un seul `catch {}` vide dans l'app. Les `try?` sur
  `ctx.fetch` sont des lectures avec une valeur par defaut saine.
- **Force unwrap**: un seul `as!`, sur `BGAppRefreshTask`, garanti par l'API.
- **Notes "a brancher"**: il en reste cinq, et les cinq disent vrai (temps
  d'ecran et bloqueur d'apps interdits par Apple sans autorisation speciale,
  agregation bancaire, analyse du sommeil sans montre). Ne pas les
  "corriger", ce sont des limites reelles annoncees honnetement.

## Phase 3 (meme session, CI bloquee)

Defauts trouves et corriges, chacun verifie autant que l'outillage local le
permet:

- **"Medicaments" ouvrait un menu**, pas la liste des traitements. L'outil
  pointait sur `MedicalHubView`, un second menu qui se contenait lui meme.
- **Les rappels de prise n'existaient pas vraiment**: une notification UNIQUE
  etait posee, donc un traitement quotidien sonnait le lendemain matin puis
  plus jamais. "2x/jour" ne posait qu'un rappel, la date de fin n'etait pas
  regardee, et "Au besoin" aurait rappele tous les matins de prendre un
  antidouleur.
- **Neuf ecrans posaient un rappel sans jamais l'annuler**: un rendez vous
  medical supprime sonnait quand meme la veille. Les identifiants vivent
  desormais dans `ReminderIDs`, appele des deux cotes.
- **Le simulateur d'impot** utilisait le bareme 2024 en 2026, ignorait le
  plafonnement du quotient familial (6 564 € d'erreur sur un cas courant, et
  toujours dans le sens agreable) et la decote (484 € annonces au lieu de 0).
- **La sauvegarde avant effacement** pouvait rater sans rien afficher, juste
  avant le bouton "Tout effacer".
- **La duree moyenne du cycle** ne s'affichait jamais pour qui remplit l'app
  tous les jours.
- **L'app demandait d'ecrire dans Apple Sante et n'ecrivait rien**: la
  fonction existait sans aucun appelant. Branchee sur la fin d'une seance
  Tabata.
- Deux notes "a brancher" tenues: retour du coach sur une reponse
  d'entretien, et lecture d'une annonce immobiliere collee.

Regle que je me suis appliquee deux fois ici, apres m'etre trompe:
**compter avant d'annoncer**. Il n'y avait pas 16 menus morts mais un seul,
comme il n'y avait pas 7 439 lignes de code mort mais 539.

Et une regle de methode qui a paye: **calculer les valeurs attendues a part,
avant d'ecrire le code**, puis les figer dans le test. C'est comme ca que la
regle "charges superieures au loyer donc montant annuel" a ete prise en
faute: elle divisait par douze un cas banal, 300 de loyer et 400 de charges.

## Noms des outils pilotes depuis Notion (21 septembre 2026)

- Table: Notion "Apps integrees dans LifeOS" (page 3e27d2c1063e81a78d95d5e52f1d06e4),
  colonne "Nouveau nom LifeOS". La colonne "Nom descriptif" est la cle: elle
  doit rester egale a l'`alias` de l'outil dans `CategoryHub.swift`.
- Serveur: `names-worker/`, Cloudflare `lifeos-names` (compte chifandcopt),
  https://lifeos-names.chifandcopt.workers.dev/names. KV `NAMES` garde les
  derniers noms lus. Cache 5 min. `node test.mjs` pour ses controles.
- App: `ToolNames.swift`, lu a l'ouverture et au retour au premier plan.
  `CategoryTool.title` est calcule: nom Notion, sinon `defaultTitle`.
- BLOQUE sur une chose que seul Theo peut faire: creer l'integration Notion,
  partager la page avec elle, deposer la cle dans
  `.credentials/notion-lifeos.token`, puis `names-worker/set-notion-key.sh`.
  D'ici la, le serveur rend les noms d'origine (`source: fallback`).
- Ajouter un outil: l'ajouter a `FALLBACK` du serveur (`fallback.js`), sinon
  ses renommages dans Notion sont ignores.

## Mac, iPad, Apple Watch et synchro (21 septembre 2026)

- **iPad**: existe deja, la cible vise iPhone et iPad (`TARGETED_DEVICE_FAMILY = "1,2"`).
- **Mac**: existe deja aussi. Le build 10 annonce `computedMinMacOsVersion 14.0`,
  donc l'app iPad tourne sur un Mac Apple Silicon via TestFlight pour Mac.
  Sante (pas, HRV) n'existe pas sur Mac: ces ecrans restent vides, c'est gere.
- **Synchro**: branche `feat/multidevice`, PAS fusionnee. Les modeles passent
  `scripts/cloudkit-ready.py` (228 problemes avant, 0 apres). Ne fusionner
  qu'apres que `SyncMigrationTests` a PASSE en CI: c'est lui qui prouve que
  les series des telephones survivent au changement de forme de la base.
  Reste, cote compte Apple: activer iCloud sur l'App ID `com.chifandco.lifeos`
  (6877WBMC34), creer le conteneur `iCloud.com.chifandco.lifeos` (le portail
  developpeur seulement, l'API ne sait pas), regenerer le profil, ajouter
  les cles iCloud au fichier d'entitlements, puis `cloudKitEnabled` a true.
- **Apple Watch**: pas commencee. Nouvelle cible watchOS, qui lit la meme base
  iCloud. A construire quand la CI tourne: une cible ajoutee a la main dans
  le pbxproj sans pouvoir compiler une seule fois casserait le build iPhone.

## Prochaine action exacte

1. Debloquer la facturation GitHub, sinon rien ne se construit ni ne part sur
   TestFlight. Tout le reste peut avancer sans.
2. Reprendre la liste des 83 destinations de `CategoryHub.swift`. Un test
   (`CategoryHubDestinationTests`) interdit desormais qu'un outil ouvre un
   menu ou qu'un ecran soit atteint deux fois.
3. FAIT. Et le chiffre que j'avancais etait faux: il n'y avait pas 16 ni 17
   `*HubView` morts, il y en avait **un seul**, `MedicalHubView`, et il
   n'etait meme pas mort puisque l'outil "Medicaments" pointait dessus.
   Supprime avec `ToolRow` et `HubScaffold`, ses deux seuls utilisateurs,
   soit 59 lignes au total. Compter avant d'annoncer.
