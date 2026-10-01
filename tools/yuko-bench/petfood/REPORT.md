# Corpus Yuko aliments chat (méthode Animaux 2.0)

Corpus construit le 2026-10-01 par `build_corpus.py` (échantillon systématique, pas trié).
Rapport écrit par `PetFoodCorpusTests` : chaque fiche passe dans le vrai code de l'app.
Quatre mesures séparées, comme demandé :

- **Identification** (espèce reconnue) : 56/63
- **Composition** disponible : 38/63 (dont lue sur l'étiquette : 15/63)
- **Photo** : face 59/63, étiquette 39/63
- **Note /100** : 35/63

Fiches SANS catégorie chat ni chien (comme « one junior ») : 15 tirées.
Espèce reconnue 9
(chat 8, chien 1),
ambiguë 0, autre animal 0,
notées 6. Ici l'identification se mesure vraiment : le reste du
corpus vient de la catégorie « aliment pour chat », donc l'espèce y est donnée par la base.

| Code | Produit | Tirage | Identité | Composition | Photos | Note | Confiance |
|---|---|---|---|---|---|---|---|
| 3700260216148 | Chats stérilisés adultes | cat-food France, rang 1/732 | chat · adulte · type ? | base | face + étiquette | 62/100 | low |
| 3560070828425 | Companino Vitalive JUNIOR 2-12 MOIS | cat-food France, rang 21/732 | chat · jeune · complet | base | face + étiquette | 39/100 | low |
| 3560071522483 | Simpl Terrine* *pour chat | cat-food France, rang 41/732 | chat · stade ? · type ? | base | face | 50/100 | low |
| 85610850 | sélection de poisson en gelée | cat-food France, rang 61/732 | chat · stade ? · type ? | absente | face | pas de note | — |
| 3700260205883 | Ultima adulte Stérilisé | cat-food France, rang 81/732 | chat · adulte · type ? | base | face + étiquette | 53/100 | low |
| 5900951014093 | Whiskas + 1 years | cat-food France, rang 101/732 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 3250391075799 | Netto Lait Pour Chat 3* | cat-food France, rang 121/732 | chat · stade ? · type ? | absente | face | pas de note | — |
| 3560071522520 | Simpl Terrine* *pour chat | cat-food France, rang 141/732 | chat · stade ? · type ? | base | face | 50/100 | low |
| 0029263884707 | Friandise pour chats | cat-food France, rang 161/732 | chat · stade ? · friandise | base | face + étiquette | 100/100 | low |
| 0052742935102 | Produit sans nom | cat-food France, rang 181/732 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 4250078909293 | Produit sans nom | cat-food France, rang 201/732 | chat · stade ? · type ? | absente | face | pas de note | — |
| 3564700801895 | Sauce pour chat Lycat Viande menus gourmands | cat-food France, rang 221/732 | chat · stade ? · type ? | absente | aucune | pas de note | — |
| 4017721837231 | carny | cat-food France, rang 241/732 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 3596710530113 | Terrine au saumon | cat-food France, rang 261/732 | chat · stade ? · type ? | base | face | 54/100 | low |
| 0831405278127 | Tenders Effilés | cat-food France, rang 281/732 | chat · adulte · complet | étiquette lue | face + étiquette | 48/100 | medium |
| 3256222713120 | Croquettes Pour Chat Au Saumon Et Au Thon U, | cat-food France, rang 301/732 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 3596710268368 | Adult - Délices en duo - Terrine et Emincés - à  | cat-food France, rang 321/732 | chat · adulte · type ? | base | face | 53/100 | low |
| 3560070117659 | Companino Vitalive Terrine* *pour chat | cat-food France, rang 341/732 | chat · stade ? · type ? | base | face | 35/100 | low |
| 3256220173865 | Terrine Boeuf 400 G | cat-food France, rang 361/732 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 3263855393018 | Terrine à la volaille & aux rognons | cat-food France, rang 381/732 | chat · stade ? · type ? | base | face + étiquette | 53/100 | low |
| 3560070822928 | Produit sans nom | cat-food France, rang 401/732 | chat · stade ? · complet | étiquette lue | face + étiquette | 65/100 | medium |
| 8714831002943 | Biofood Kattenvoer Control | cat-food France, rang 421/732 | chat · stade ? · type ? | étiquette lue | étiquette | 73/100 | medium |
| 3245390184092 | Produit sans nom | cat-food France, rang 441/732 | chat · stade ? · type ? | absente | face | pas de note | — |
| 3560070562695 | Produit sans nom | cat-food France, rang 461/732 | chat · stade ? · type ? | absente | face | pas de note | — |
| 3336025821922 | Sticks moelleux avec de l'Agneau | cat-food France, rang 481/732 | chat · stade ? · friandise | absente | face | pas de note | — |
| 7613034996480 | Chat stérilisé dinde | cat-food France, rang 501/732 | chat · adulte · complet | étiquette lue | face + étiquette | 70/100 | medium |
| 3275970001112 | Chaton mousses à la dinde | cat-food France, rang 521/732 | chat · jeune · type ? | absente | face | pas de note | — |
| 4011905426822 | Creamy Snack avec des crevettes | cat-food France, rang 541/732 | chat · stade ? · friandise | absente | face | pas de note | — |
| 0052742933900 | Sterilised cat young adult with tuna | cat-food France, rang 561/732 | chat · adulte · complet | étiquette lue | face + étiquette | 46/100 | medium |
| 3182550724388 | Royal Canin - Croquettes Veterinary Care Young F | cat-food France, rang 581/732 | ambigu chat/chien | base | étiquette | pas de note | — |
| 3344951102756 | IRC Hypoallergénique -  Chat stérilisé | cat-food France, rang 601/732 | chat · stade ? · type ? | base | face + étiquette | 44/100 | high |
| 3256220739115 | Croquettes Pour Chat Stérilisé Premium U, | cat-food France, rang 641/732 | chat · stade ? · type ? | base | face + étiquette | 55/100 | low |
| 4008239367549 | Freija soft snack à la viande et au fromage | cat-food France, rang 661/732 | chat · stade ? · complémentaire | étiquette lue | face + étiquette | 19/100 | low |
| 0052742223209 | Hill's SciCroquettes Pour Chat Sénior 11+ | cat-food France, rang 681/732 | chat · senior · type ? | étiquette lue | face + étiquette | 56/100 | medium |
| 3700654000032 | Aliment complet pour chat | cat-food France, rang 701/732 | chat · stade ? · complet | absente | face | pas de note | — |
| 3256220174008 | Les émincés en sauce | cat-food France, rang 721/732 | chat · stade ? · type ? | base | face + étiquette | 51/100 | low |
| 5998749117774 | Friandises au poulet pour chat et chaton | cat-treats, rang 1/41 | chat · jeune · friandise | base | face + étiquette | 43/100 | low |
| 4047777170877 | Crunchy Snack | cat-treats, rang 8/41 | chat · adulte · complémentaire | base | face + étiquette | 92/100 | low |
| 5998749146477 | Knuspertaschen mit Lachs | cat-treats, rang 15/41 | chat · stade ? · type ? | absente | face + étiquette | pas de note | — |
| 0810037580396 | Whimzees | cat-treats, rang 22/41 | chat · adulte · friandise | étiquette lue | face + étiquette | 65/100 | low |
| 0023100141459 | Temptations Kitten Salmon & Dairy Flavor | cat-treats, rang 29/41 | chat · jeune · friandise | étiquette lue | face + étiquette | 55/100 | low |
| 4002064409801 | Käse-Rollis | cat-treats, rang 36/41 | chat · stade ? · type ? | base | face + étiquette | 48/100 | low |
| 3564706535855 | Boisson lactée pour chats et chatons de plus de  | recherche « chaton », rang 4 | chat · jeune · type ? | absente | face | pas de note | — |
| 4047777125013 | Wilderness Kitten True Country | recherche « chaton », rang 7 | chat · jeune · type ? | base | face + étiquette | 94/100 | high |
| 3250391140053 | Bouchées En Sauce Pour Chaton, Les 12 Bouchées D | recherche « chaton », rang 10 | chat · jeune · type ? | base | étiquette | 65/100 | medium |
| 3250391800872 | Croquettes Chaton | recherche « chaton », rang 13 | chat · jeune · type ? | absente | face + étiquette | pas de note | — |
| 3250391945191 | Terrine pour Chaton de la marque Canaillou | recherche « chaton », rang 16 | chat · jeune · type ? | base | face | 58/100 | high |
| 5900951308154 | Perfect fit senior +7 chats stérilisés | fiche sans catégorie chat/chien, rang 1/190 | chat · senior · type ? | étiquette lue | face + étiquette | 48/100 | medium |
| 7613036724272 | Dentalife Daily Oral Care Treats | fiche sans catégorie chat/chien, rang 3/190 | chat · adulte · complémentaire | étiquette lue | face + étiquette | 64/100 | low |
| 3760080533450 | Physyo | fiche sans catégorie chat/chien, rang 5/190 | espèce inconnue | base | face + étiquette | pas de note | — |
| 7613287328366 | Félix | fiche sans catégorie chat/chien, rang 7/190 | chat · stade ? · type ? | absente | face | pas de note | — |
| 5010394984577 | pedigree | fiche sans catégorie chat/chien, rang 9/190 | chien · stade ? · type ? | base | face + étiquette | 60/100 | medium |
| 7613036885300 | Purina beyond | fiche sans catégorie chat/chien, rang 11/190 | espèce inconnue | absente | face | pas de note | — |
| 8445290497987 | Félix tendres effilés | fiche sans catégorie chat/chien, rang 13/190 | chat · adulte · complet | étiquette lue | face + étiquette | 53/100 | medium |
| 5425039484389 | Succulent poulet et dinde | fiche sans catégorie chat/chien, rang 15/190 | espèce inconnue | base | face + étiquette | pas de note | — |
| 3564700563700 | Aliment complet pour chat | fiche sans catégorie chat/chien, rang 17/190 | chat · adulte · complet | étiquette lue | face + étiquette | 61/100 | medium |
| 7613035114890 | adult small&mini sensitive skin | fiche sans catégorie chat/chien, rang 19/190 | espèce inconnue | absente | face | pas de note | — |
| 8712113501603 | Produit sans nom | fiche sans catégorie chat/chien, rang 21/190 | espèce inconnue | absente | face | pas de note | — |
| 8715342043616 | Delicious cat treats | fiche sans catégorie chat/chien, rang 23/190 | chat · stade ? · friandise | absente | face | pas de note | — |
| 7613036514279 | Purina One MEDIUM&gt;10kg Sensitive | fiche sans catégorie chat/chien, rang 25/190 | espèce inconnue | absente | face | pas de note | — |
| 8445290949400 | Croq Chat Stérilisé 3kg | fiche sans catégorie chat/chien, rang 27/190 | chat · stade ? · type ? | absente | face | pas de note | — |
| 5407009641206 | paté pour chats 1dultes sans céréal | fiche sans catégorie chat/chien, rang 29/190 | chat · adulte · complet | étiquette lue | face + étiquette | 100/100 | medium |
| 8445290938091 | one junior | produit de l'utilisateur (« one junior ») | chat · jeune · complet | étiquette lue | face + étiquette | 77/100 | medium |

## Fiches non résolues ou partielles, avec la cause

| Code | Produit | Cause |
|---|---|---|
| 3700260216148 | Chats stérilisés adultes | note partielle, manque : constituants analytiques |
| 3560070828425 | Companino Vitalive JUNIOR 2-12 MOIS | note partielle, manque : constituants analytiques |
| 3560071522483 | Simpl Terrine* *pour chat | note partielle, manque : constituants analytiques |
| 85610850 | sélection de poisson en gelée | manque : composition (aucune photo d'étiquette dans la base) |
| 3700260205883 | Ultima adulte Stérilisé | note partielle, manque : constituants analytiques |
| 5900951014093 | Whiskas + 1 years | manque : composition (étiquette lue, composition non trouvée) |
| 3250391075799 | Netto Lait Pour Chat 3* | manque : composition (aucune photo d'étiquette dans la base) |
| 3560071522520 | Simpl Terrine* *pour chat | note partielle, manque : constituants analytiques |
| 0052742935102 | Produit sans nom | manque : composition (étiquette lue, composition non trouvée) |
| 4250078909293 | Produit sans nom | manque : composition (aucune photo d'étiquette dans la base) |
| 3564700801895 | Sauce pour chat Lycat Viande menus gourmands | manque : composition (aucune photo d'étiquette dans la base) |
| 4017721837231 | carny | manque : composition (étiquette lue, composition non trouvée) |
| 3596710530113 | Terrine au saumon | note partielle, manque : constituants analytiques |
| 3256222713120 | Croquettes Pour Chat Au Saumon Et Au Thon U, | manque : composition (étiquette lue, composition non trouvée) |
| 3596710268368 | Adult - Délices en duo - Terrine et Emincés - à  | note partielle, manque : constituants analytiques |
| 3560070117659 | Companino Vitalive Terrine* *pour chat | note partielle, manque : constituants analytiques |
| 3256220173865 | Terrine Boeuf 400 G | manque : composition (étiquette lue, composition non trouvée) |
| 3263855393018 | Terrine à la volaille & aux rognons | note partielle, manque : humidité (ou préciser croquettes / pâtée) |
| 3245390184092 | Produit sans nom | manque : composition (aucune photo d'étiquette dans la base) |
| 3560070562695 | Produit sans nom | manque : composition (aucune photo d'étiquette dans la base) |
| 3336025821922 | Sticks moelleux avec de l'Agneau | manque : composition (aucune photo d'étiquette dans la base) |
| 3275970001112 | Chaton mousses à la dinde | manque : composition (aucune photo d'étiquette dans la base) |
| 4011905426822 | Creamy Snack avec des crevettes | manque : composition (aucune photo d'étiquette dans la base) |
| 3182550724388 | Royal Canin - Croquettes Veterinary Care Young F | manque : espèce (la fiche parle de chat ET de chien) |
| 3256220739115 | Croquettes Pour Chat Stérilisé Premium U, | note partielle, manque : constituants analytiques |
| 3700654000032 | Aliment complet pour chat | manque : composition (aucune photo d'étiquette dans la base) |
| 3256220174008 | Les émincés en sauce | note partielle, manque : humidité (ou préciser croquettes / pâtée) |
| 5998749146477 | Knuspertaschen mit Lachs | manque : composition (étiquette lue, composition non trouvée) |
| 4002064409801 | Käse-Rollis | note partielle, manque : constituants analytiques |
| 3564706535855 | Boisson lactée pour chats et chatons de plus de  | manque : composition (aucune photo d'étiquette dans la base) |
| 3250391800872 | Croquettes Chaton | manque : composition (étiquette lue, composition non trouvée) |
| 3760080533450 | Physyo | manque : espèce (chat ou chien) |
| 7613287328366 | Félix | manque : composition (aucune photo d'étiquette dans la base) |
| 7613036885300 | Purina beyond | manque : espèce (chat ou chien), composition (aucune photo d'étiquette dans la base) |
| 5425039484389 | Succulent poulet et dinde | manque : espèce (chat ou chien) |
| 7613035114890 | adult small&mini sensitive skin | manque : espèce (chat ou chien), composition (aucune photo d'étiquette dans la base) |
| 8712113501603 | Produit sans nom | manque : espèce (chat ou chien), composition (aucune photo d'étiquette dans la base) |
| 8715342043616 | Delicious cat treats | manque : composition (aucune photo d'étiquette dans la base) |
| 7613036514279 | Purina One MEDIUM&gt;10kg Sensitive | manque : espèce (chat ou chien), composition (aucune photo d'étiquette dans la base) |
| 8445290949400 | Croq Chat Stérilisé 3kg | manque : composition (aucune photo d'étiquette dans la base) |
