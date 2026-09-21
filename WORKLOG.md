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

## Prochaine action exacte

1. Debloquer la facturation GitHub, sinon rien ne se construit ni ne part sur
   TestFlight. Tout le reste peut avancer sans.
2. Reprendre la liste des 83 destinations de `CategoryHub.swift`. Un test
   (`CategoryHubDestinationTests`) interdit desormais qu'un outil ouvre un
   menu ou qu'un ecran soit atteint deux fois.
3. Supprimer les 17 `*HubView` morts, un fichier a la fois, en relancant
   `parse-check.sh` apres chacun. `MedicalHubView` etait le dernier encore
   atteignable, il ne l'est plus.
