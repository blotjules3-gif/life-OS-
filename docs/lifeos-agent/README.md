# LifeOS Supervisor — à la demande

## Lancer

Dans cette tâche Codex, avec GPT-6 Astra sélectionné :

> Lance un lot LifeOS selon `docs/lifeos-agent/SUPERVISOR.md`. Claude construit, tu vérifies. Un lot et au maximum deux corrections. Reprends state.json et enregistre les preuves. Ne relance pas un audit complet.

Ensuite le superviseur prépare le lot, appelle Claude Code et vérifie son résultat sans transfert manuel. Le bridge ne pilote pas une conversation Claude Desktop : il ouvre une session CLI dédiée, avec l’authentification Claude Code déjà configurée.

## Mémoire

- PRODUCT-BRIEF.md : brief maître de la conversation.
- MODULES-88.md : inventaire détaillé des outils et critères.
- REQUIREMENTS-2026-09-30.md : quatre thèmes, navigation personnalisable, Tabata durable et séquence visible.
- SUPERVISOR.md : boucle, budget de passages, critères de preuve.
- state.json : position du chantier, dépendances et prochain lot.
- jobs/<id>/ : brief, compteur, résultats et preuves du lot.

## État de livraison

Retour automatique ajouté le 30 septembre : `auto_loop.py` attend localement la fin de Claude et ses fichiers `HANDOFF.md` / `result-status.json`, puis appelle Astra une fois avec un dossier borné. Astra ne lance pas de commandes ni de tests : Claude en est responsable. Les corrections sont renvoyées automatiquement à Claude dans la limite de trois passages constructeur au total et trois revues. Une réponse inexploitable ou un blocage arrête le lot sans répétition coûteuse.

Le lot Tabata actuel utilise déjà ses trois passages constructeur (premier passage + deux reprises). Le retour automatique fera donc la revue finale et conservera les défauts éventuels, sans lancer un quatrième passage. Un nouveau lot démarre avec son propre budget de trois passages. Il n’y a pas de relance quotidienne ni de passage au lot suivant sans demande.

Suivi actuel : `jobs/2026-09-30-tabata/loop-state.json`, puis `LOOP-RESULT.md` à la fin. Notification macOS locale en fin de boucle si les notifications sont autorisées. Le processus attend sans appels IA ; un appel à Astra sera fait lorsque le dossier complet sera prêt. Tests gratuits d’orchestration : `python3 docs/lifeos-agent/test_auto_loop.py`. Ils utilisent des réponses simulées, pas les modèles. Le premier retour réel reste à constater à la fin du constructeur.

Arrêt entre deux phases : créer le fichier `STOP` dans le dossier du lot. Cela ne coupe pas un appel déjà engagé. Une extinction de la machine interrompt le processus ; les compteurs et résultats persistent. Ne pas relancer aveuglément une phase `reviewing`/`building` après interruption : le runner s’arrête pour éviter une double facturation. Le script doit être exécuté sur un Mac disponible ; aucune garantie de fonctionnement pendant l’extinction.

Le nombre d’appels et leur durée sont bornés ; ce n’est pas un plafond garanti de crédits. Le modèle du superviseur dépend de la tâche qui le lance ; un fichier ne confère pas les capacités d’Astra à un autre modèle. Le bridge ne remplace pas les autorisations d’outils, les credentials fournisseurs ou l’accès aux appareils.

Le verrou protège les appels de CE bridge. Il ne bloque pas une session Claude humaine externe : ne pas lancer deux constructeurs sur les mêmes fichiers. Un appareil inaccessible reste non testé. Une interruption laisse les modifications sur disque et doit être auditée avant reprise.
