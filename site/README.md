# site/

Le vrai site de LifeOS ne vit PAS ici. Il est dans le depot
**leilajkaseme-hub/lifeos-site**, publie par GitHub Pages :

- https://leilajkaseme-hub.github.io/lifeos-site/
- https://leilajkaseme-hub.github.io/lifeos-site/privacy.html
- https://leilajkaseme-hub.github.io/lifeos-site/support.html
- https://leilajkaseme-hub.github.io/lifeos-site/terms.html

Ce dossier ne contient qu'un outil.

## set-store-urls.py

Pose l'URL de confidentialite et l'URL de support sur la fiche App Store.

    python3 set-store-urls.py <url-confidentialite> <url-support>

**Le piege qu'il evite :** les deux champs ne vivent pas au meme endroit chez
Apple. `privacyPolicyUrl` est sur `appInfoLocalizations` (la fiche de l'app),
`supportUrl` est sur `appStoreVersionLocalizations` (la version). Les ecrire au
meme endroit reussit pour l'un et echoue en silence pour l'autre.

Il ne touche que la version en `PREPARE_FOR_SUBMISSION`. Une version deja
envoyee ou en vente est refusee en ecriture par Apple (409 INVALID_STATE), ce
n'est pas un bug du script.
