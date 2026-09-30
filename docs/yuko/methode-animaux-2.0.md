# Yuko, méthode « Animaux 2.0 » (chats et chiens)

Code : `LifeOS/Services/PetFoodScore.swift` (note), `PetLabel.swift` (lecture d'étiquette,
identité), `PetEnrichment.swift` (profil par produit, fusion, lecture des photos).
Version affichée sur chaque note : `Animaux 2.0 · chat · chaton`.

## Pourquoi une 2.0

La 1.0 abandonnait dès que l'espèce manquait (« Espèce non reconnue »), sans dire que la
composition manquait aussi, et découpait les ingrédients sur les virgules (« 18,5 % »
cassé). Un chaton était comparé aux besoins d'un adulte. Le choix Chat/Chien était rangé
par code brut dans les réglages et passait sous la barre d'onglets.

## Chemin d'une fiche

1. **Base** : Open Pet Food Facts, par code (forme canonique du GTIN, voir `Barcode`).
2. **Photos d'étiquette choisies par la base** (`ingredients_*`, `nutrition_*`) : lues
   **sur l'iPhone** par Vision (rien n'est envoyé). Photo redressée et ramenée à 2 400 px.
   Toutes les photos sont lues ; la lecture la plus complète gagne
   (`PetLabelReader.quality`). État « Recherche de la composition… », erreur réessayable
   (un délai dépassé n'est jamais « produit absent »).
3. **Photo de l'utilisateur** si rien n'a marché : il photographie, relit, corrige, valide.
4. Le résultat est rangé sous le **GTIN canonique** (`pets.json`), avec les codes vus en
   alias. Jamais attaché à un autre GTIN, même au nom proche (recette saumon ≠ poulet,
   junior ≠ adulte).

Pas de fabricant ni de distributeur automatique dans cette version : leurs pages ne
donnent pas le GTIN, donc l'association à la fiche ne serait pas prouvée (voir « Limites »). Rien n'est publié dans la base
communautaire.

## Fusion (`PetMerge`)

- Choix de l'utilisateur (espèce, stade) d'abord.
- La base garde ce qu'elle a ; l'étiquette lue ne remplit que les trous.
- Composition et valeurs viennent de la **même** étiquette quand la base n'a pas de
  composition. Si la base a une composition mais pas de valeurs, les valeurs de l'étiquette
  ne sont prises que si 2 des 3 premiers ingrédients concordent (sinon : deux versions de
  la recette, valeurs non mélangées, et c'est écrit).
- Chaque apport est dit en clair (« lue automatiquement, à vérifier » / « relue par toi »).

## Identité

Indices pondérés : catégorie de la base 3, mention d'étiquette 3, nom 2, face avant 2,
marque réservée à une espèce 1. Chat ET chien → ambigu, on demande. « Junior » ou
« Purina » seuls ne donnent pas l'espèce. Oiseau, rongeur… → hors méthode. Stade : chaton /
chiot / junior / croissance / gestation-lactation → jeune ; senior, 7+ ; adulte, 1+.
Constituants déclarés ≥ 40 % tel quel → croquettes (une pâtée a plus de 60 % d'eau).

## Note /100

| Partie | Max | Règles |
|---|---|---|
| Composition | 45 | viande ou poisson nommé en tête +15 (sans espèce +5, nommé en 2e +6) ; part déclarée du 1er ingrédient animal ≥ 50 % +20, ≥ 26 +14, ≥ 14 +8, > 4 +3, 4 % (minimum légal) +0 ; céréales et protéines végétales dans les 5 premiers : 10 − 3 par ingrédient (chat) / − 2 (chien) ; « sous-produits » −5. Termes entiers seulement (« pois » ≠ « poisson »). « (dont poulet 4 %) » compte comme part de viande nommée, jamais comme total de viande. |
| Nutrition | 25 | aliment complet seulement. Protéines sur matière sèche (valeur basse de la fourchette) contre le repère FEDIAF du stade : < repère 0, +5 → 8, +10 → 14, +20 → 20, au-delà 25. Graisses sous le repère −4. Chat : taurine sous le repère −4 ; glucides estimés > 40 % MS −8, > 25 % −4. |
| Additifs et ingrédients à éviter | 30 | sucres −15, colorants −6, BHA/BHT/éthoxyquine −10, propylène glycol (chat) −15, toxiques −25 et note plafonnée. Vitamines, oligo-éléments et taurine ajoutés : **jamais pénalisés**. Antioxygènes non nommés : signalés, sans pénalité. |

Repères FEDIAF (Nutritional Guidelines, octobre 2021, tableaux III-3a et III-4a), pour
100 g de matière sèche : chat adulte protéines 25 g, croissance 28 g, graisses 9 g, taurine
sec 0,10 g, humide 0,20 g (adulte) / 0,25 g (croissance) ; chien adulte protéines 18 g,
croissance 25 g, graisses 5,5 / 8,5 g.

**Matière sèche** : humidité déclarée, sinon croquettes prouvées (humidité < 14 %, seuil de
déclaration du règlement 767/2009) → fourchette 86 à 100 % de MS. Jamais d'humidité inventée
pour un aliment qui peut être humide : la nutrition est alors « non évaluée ».
**Glucides** : estimés seulement avec protéines, graisses, cendres et cellulose, en fourchette.
**Calcium, phosphore, taurine** : valeur des constituants analytiques seulement ; un sel de
calcium dans les additifs n'est pas une teneur.
**Valeur impossible** (virgule perdue à la lecture : « 07 % » d'oméga 3) : laissée vide.

**Données manquantes** : pas d'espèce ou pas de composition → pas de note, les deux manques
dits ensemble. Aliment complet sans valeurs → nutrition comptée à mi-points (12,5/25), note
provisoire, confiance faible (avant : ramenée à 100, d'où des 100/100 sans aucune valeur).
Friandise ou complémentaire → pas comparée aux besoins d'un aliment complet.

**Confiance** (séparée de la note) : élevée = composition et valeurs de la fiche ou relues
par l'utilisateur, humidité déclarée ; moyenne = lecture automatique ou humidité supposée ;
faible = valeurs manquantes.

Pas un avis vétérinaire. Les aliments animaux n'entrent jamais dans le journal alimentaire
ni dans les objectifs personnels.

## Le cas réel « one junior » (8445290938091)

Fiche de la base : nom « one junior », catégorie vide, pas de composition, pas de marque.
Code confirmé par le code-barres imprimé sur la photo d'étiquette (« 445290 938091 »).
Recette au **saumon** : la page fabricant « junior chaton poulet » est un autre produit, ses
valeurs ne sont pas utilisées.

Calcul : composition 15 (saumon en tête) + 8 (18 %) + 4 (blé et protéines de pois : −6) =
27/45 ; nutrition : croquettes prouvées (70,5 % déclarés), protéines 41 à 47,7 % MS contre
28 % (chaton) → 20/25, graisses, taurine et glucides (18 à 29,5 % MS) sans retrait ;
additifs 30/30. **77/100, confiance moyenne.** Test :
`PetFoodRealCaseTests.testOneJuniorWithItsLabelPhotoIsScoredAsKitten`.

## Corpus

`tools/yuko-bench/petfood/` : 50 fiches tirées systématiquement, rapport `REPORT.md`
(identification, composition, photo, note mesurées à part, et chaque fiche non résolue avec
sa cause). Les fiches du corpus viennent surtout de la catégorie « cat-food » : l'espèce y
est donc presque toujours reconnue ; ce n'est pas la mesure des fiches mal classées.

## Limites

- Pas de source fabricant ou distributeur branchée : sans GTIN sur la page, on ne peut pas
  prouver que c'est la même recette (le cas réel l'a montré : page poulet, sac saumon).
- Étiquettes en deux colonnes ou en plusieurs langues : la lecture automatique mélange les
  colonnes ; l'utilisateur corrige dans l'éditeur.
- Multipacks à plusieurs recettes : la première recette seulement.
