# Diagnostic Problèmes → Solutions — LifeOS Coach IA

## RÈGLE D'UTILISATION (lire en premier)

Quand un utilisateur exprime un problème :
1. Identifier le problème dans ce fichier
2. Lister TOUTES les solutions disponibles (pas juste une)
3. Vérifier "Modules actifs" dans le snapshot utilisateur
4. Pour chaque solution :
   - Si le module [MODULE: xxx] est DÉJÀ actif → proposer d'optimiser via update_module_config
   - Si le module [MODULE: xxx] N'EST PAS actif → proposer de l'ajouter via add_module
5. Toujours proposer au moins 2 solutions (idéalement 3), en couvrant des modules différents
6. Ne jamais proposer add_module pour un module déjà dans "Modules actifs"

Format des tags : [MODULE: clé_module] correspond aux clés : fitness, nutrition, sleep, mind, productivity, finance, invest, career, learning, looks, social, home, admin, cycle

---

## FITNESS / SPORT

**Problème : "je suis trop fatigué pour m'entraîner / je n'ai pas d'énergie"**
- Séance légère adaptée à la fatigue (marche 20min, mobilité, yoga) [MODULE: fitness]
- Vérifier la qualité du sommeil et ajuster les horaires [MODULE: sleep]
- Suivre l'énergie journalière pour repérer les patterns [MODULE: mind]
- Vérifier les apports protéinés et caloriques (sous-alimentation = fatigue) [MODULE: nutrition]

**Problème : "je saute mes séances / je n'arrive pas à m'y tenir"**
- Réduire la fréquence (commencer par 2x/semaine), déclencheur fixe [MODULE: fitness]
- Créer une habitude liée à un moment ancré (après le café, après le boulot) [MODULE: productivity]
- Défi court (21 jours) pour recréer une dynamique [MODULE: fitness]
- Vérifier si la surcharge mentale empêche la discipline [MODULE: mind]

**Problème : "je ne vois pas de progrès"**
- Activer le suivi des séances (poids, reps, temps) [MODULE: fitness]
- Vérifier la surcharge progressive (augmenter graduellement l'intensité) [MODULE: fitness]
- Optimiser la nutrition autour des entraînements (protéines +) [MODULE: nutrition]
- Vérifier la qualité du sommeil (récupération insuffisante = stagnation) [MODULE: sleep]

**Problème : "je manque de temps pour faire du sport"**
- HIIT 20min ou séances courtes à domicile [MODULE: fitness]
- Réorganiser le planning pour bloquer créneaux sport [MODULE: productivity]
- Intégrer des micro-activités dans la journée (escaliers, marche) [MODULE: fitness]

**Problème : "j'ai mal aux articulations / blessure"**
- Adapter les séances (low-impact : natation, vélo, yoga) [MODULE: fitness]
- Programmer des rappels de récupération et étirements [MODULE: fitness]
- Suivre les symptômes dans le journal de santé [MODULE: mind]

---

## NUTRITION

**Problème : "je mange mal / je sais pas quoi manger"**
- Activer le suivi des repas avec objectifs kcal et protéines [MODULE: nutrition]
- Batch cooking le dimanche, meal prep hebdomadaire [MODULE: nutrition]
- Organiser la liste de courses dans l'app [MODULE: home]
- Suivre les habitudes alimentaires (heure, qualité) [MODULE: productivity]

**Problème : "je tiens pas mon jeûne"**
- Ajuster la fenêtre de jeûne (16h → 14h pour commencer) [MODULE: nutrition]
- Programmer des rappels pendant les heures difficiles [MODULE: nutrition]
- Identifier les déclencheurs émotionnels (stress, ennui) [MODULE: mind]

**Problème : "j'ai des fringales / je grignote"**
- Augmenter les protéines au petit-déj (satiété) [MODULE: nutrition]
- Identifier le stress ou l'ennui comme déclencheur [MODULE: mind]
- Avoir des alternatives saines planifiées dans les courses [MODULE: home]

**Problème : "je perds pas de poids malgré les efforts"**
- Calibrer le déficit calorique (données nutrition précises) [MODULE: nutrition]
- Augmenter le NEAT (activité non-sportive dans la journée) [MODULE: fitness]
- Vérifier la qualité du sommeil (mauvais sommeil = prise de poids) [MODULE: sleep]
- Vérifier le stress chronique (cortisol = rétention de graisse) [MODULE: mind]

---

## SOMMEIL

**Problème : "je n'arrive pas à m'endormir"**
- Créer une routine du soir (luminosité basse, écrans -1h) [MODULE: sleep]
- Respiration ou méditation guidée avant de dormir [MODULE: mind]
- Éviter les stimulants (café après 14h, sport le soir) [MODULE: nutrition]
- Optimiser l'environnement (température, bruit, lumière) [MODULE: sleep]

**Problème : "je me réveille la nuit"**
- Traquer les patterns de réveil (heure, durée) [MODULE: sleep]
- Réduire l'alcool et les repas tardifs [MODULE: nutrition]
- Gérer le stress du soir (journaling, cohérence cardiaque) [MODULE: mind]

**Problème : "je suis fatigué le matin / j'ai du mal à me lever"**
- Reculer l'heure de coucher de 30min chaque soir [MODULE: sleep]
- Lumière naturelle dès le réveil (lampe de luminothérapie) [MODULE: sleep]
- Suivre l'énergie matinale pour identifier les patterns [MODULE: productivity]
- Vérifier si le manque de motivation est plus profond [MODULE: mind]

**Problème : "je dors trop peu (moins de 6h)"**
- Identifier les voleurs de sommeil (réseaux sociaux, séries) [MODULE: productivity]
- Alarme de coucher + rituel fixe [MODULE: sleep]
- Évaluer la charge mentale (surmenage = vol de sommeil) [MODULE: mind]
- Vérifier si les finances / le travail génèrent de l'anxiété nocturne [MODULE: finance]

---

## MENTAL / BIEN-ÊTRE

**Problème : "je suis stressé / sous pression"**
- Cohérence cardiaque guidée 5min, 3x/jour [MODULE: mind]
- Identifier la source de stress (pro, perso, finances, santé) [MODULE: mind]
- Vérifier si la charge de travail est trop haute [MODULE: productivity]
- Vérifier l'état des finances (stress financier très fréquent) [MODULE: finance]
- Mouvement physique (le sport réduit le cortisol) [MODULE: fitness]

**Problème : "je me sens anxieux / je rumine"**
- Méditation ou respiration guidée quotidienne [MODULE: mind]
- Gratitude journalière (3 éléments positifs/j) [MODULE: mind]
- Limiter les nouvelles négatives et les réseaux sociaux [MODULE: productivity]
- Parler de la situation à quelqu'un, planifier un contact social [MODULE: social]

**Problème : "je me sens déprimé / down"**
- Sortir dehors (lumière naturelle, marche) [MODULE: fitness]
- Suivi de l'humeur pour identifier les patterns [MODULE: mind]
- Planifier des activités sociales pour briser l'isolement [MODULE: social]
- Si durable : encourager à consulter un professionnel [MODULE: mind]

**Problème : "j'ai du mal à me concentrer"**
- Technique Pomodoro (25min focus / 5min pause) [MODULE: productivity]
- Désactiver les notifications pendant les blocs de travail [MODULE: productivity]
- Vérifier la qualité du sommeil (manque = concentration réduite de 30%) [MODULE: sleep]
- Vérifier l'alimentation (glycémie stable = concentration stable) [MODULE: nutrition]

**Problème : "je me sens submergé / overwhelmed"**
- Triage des tâches (1 seule priorité absolue par jour) [MODULE: productivity]
- Audit des engagements (en supprimer quelques-uns) [MODULE: productivity]
- Prendre du recul sur les finances (source fréquente de stress caché) [MODULE: finance]
- Déléguer, dire non, réduire les obligations sociales [MODULE: social]

**Problème : "je me sens seul / isolé"**
- Planifier 1 sortie sociale par semaine minimum [MODULE: social]
- Renouer avec d'anciens contacts (message simple) [MODULE: social]
- Rejoindre un club ou une activité de groupe [MODULE: fitness]
- Évaluer si le travail / le logement favorise l'isolement [MODULE: career]

---

## PRODUCTIVITÉ / HABITUDES

**Problème : "je ne fais pas mes habitudes"**
- Réduire à 3 habitudes max, ancrage sur des moments fixes [MODULE: productivity]
- Vérifier si les habitudes sont réalistes ou trop ambitieuses [MODULE: productivity]
- Déclencheur visuel (post-it, rappel, widget) [MODULE: productivity]
- Vérifier si la fatigue mentale est la cause (manque de sommeil) [MODULE: sleep]

**Problème : "je procrastine sur tout"**
- Règle des 2 minutes (si <2min → faire maintenant) [MODULE: productivity]
- Diviser chaque tâche en micro-étapes de 5min [MODULE: productivity]
- Identifier si c'est de la peur (de rater, de mal faire) → travail mental [MODULE: mind]

**Problème : "j'ai trop de todos, rien n'avance"**
- MoSCoW (Must/Should/Could/Won't) : garder 3 priorités max par jour [MODULE: productivity]
- Nettoyer la liste : supprimer ou reporter tout ce qui n'est pas urgent [MODULE: productivity]
- Vérifier si la charge pro est trop haute → discussion carrière [MODULE: career]

**Problème : "mon planning s'effondre toujours"**
- Bloquer du temps vide intentionnel dans le planning (buffer) [MODULE: productivity]
- Revue hebdo le dimanche (15min) pour recalibrer [MODULE: productivity]
- Vérifier si les imprévus viennent de l'organisation de la maison [MODULE: home]

---

## FINANCES

**Problème : "je dépense trop / je gère mal mon argent"**
- Activer le suivi des dépenses et catégoriser [MODULE: finance]
- Méthode des enveloppes (budget par catégorie) [MODULE: finance]
- Délai 24h avant tout achat non planifié >50€ [MODULE: finance]
- Vérifier si les achats compulsifs sont liés au stress [MODULE: mind]

**Problème : "je sais pas où part mon argent"**
- Audit complet des dépenses du dernier mois [MODULE: finance]
- Catégoriser et identifier les "fuites" (abonnements oubliés) [MODULE: finance]
- Audit des abonnements actifs [MODULE: admin]

**Problème : "j'arrive pas à épargner"**
- Virement automatique J+1 du salaire sur compte épargne séparé [MODULE: finance]
- Définir un objectif d'épargne concret dans LifeOS [MODULE: finance]
- Réduire les abonnements non utilisés pour libérer du cash [MODULE: admin]

**Problème : "j'ai des dettes"**
- Méthode avalanche (taux le plus haut en premier) ou boule de neige [MODULE: finance]
- Renégocier les taux d'intérêt avec la banque [MODULE: finance]
- Activer un suivi strict des dépenses pour dégager du budget [MODULE: finance]

---

## INVESTISSEMENT

**Problème : "je sais pas par où commencer à investir"**
- PEA + ETF monde (MSCI World) en investissement mensuel régulier (DCA) [MODULE: invest]
- Ouvrir d'abord un livret A + fonds d'urgence (3-6 mois de dépenses) [MODULE: finance]
- Commencer par l'apprentissage des bases (ETF, intérêts composés) [MODULE: learning]

**Problème : "j'ai peur de perdre de l'argent"**
- Diversification multi-actifs (ETF > actions individuelles) [MODULE: invest]
- N'investir que l'argent dont on n'a pas besoin à court terme [MODULE: invest]
- Comprendre la volatilité vs le risque réel sur longue période [MODULE: learning]

**Problème : "j'ai perdu de l'argent sur des placements"**
- Analyser la cause (mauvais timing, choix, panique) [MODULE: invest]
- Journal de trading pour éviter les erreurs émotionnelles [MODULE: invest]
- Diversifier davantage pour réduire le risque concentré [MODULE: invest]

---

## CARRIÈRE

**Problème : "je me sens pas valorisé au travail"**
- Documenter ses réussites (brag doc) et préparer une discussion salariale [MODULE: career]
- Demander un feedback structuré à son manager [MODULE: career]
- Évaluer si le problème est le poste ou l'entreprise [MODULE: career]

**Problème : "j'ai pas d'évolution professionnelle"**
- Identifier le gap de compétences et créer un plan de formation [MODULE: career]
- Formation en parallèle (online, certifications) [MODULE: learning]
- Chercher un mentor interne ou externe [MODULE: career]

**Problème : "je cherche un emploi"**
- Activer le suivi des candidatures [MODULE: career]
- 5 candidatures par semaine, LinkedIn actif [MODULE: career]
- Travailler les soft skills et la présentation [MODULE: learning]

**Problème : "je veux changer de carrière"**
- Bilan de compétences et identification des transferts [MODULE: career]
- Tester en parallèle (freelance, side project, formation) [MODULE: learning]
- Vérifier que les finances permettent une transition sereine [MODULE: finance]

---

## APPRENTISSAGE

**Problème : "j'apprends mais j'oublie vite"**
- Répétition espacée (flashcards LifeOS activées) [MODULE: learning]
- Enseigner ce qu'on vient d'apprendre (méthode Feynman) [MODULE: learning]
- Appliquer immédiatement dans un projet concret [MODULE: productivity]

**Problème : "j'arrive pas à lire / à me former"**
- 10 pages/j minimum, le matin avant les écrans [MODULE: learning]
- Micro-apprentissage en déplacement (podcasts, résumés) [MODULE: learning]
- Remplacer 15min de réseaux sociaux par 15min de lecture [MODULE: productivity]

**Problème : "je me disperse sur trop de sujets"**
- 1 seul sujet par mois, finir avant de commencer [MODULE: learning]
- Note "à apprendre plus tard" pour ne pas perdre les idées [MODULE: productivity]

---

## CORPS / LOOKSMAXX

**Problème : "ma peau est en mauvais état"**
- Routine visage (nettoyant + hydratant + SPF) 2x/j [MODULE: looks]
- Augmenter l'eau (objectif 2L/j minimum) [MODULE: nutrition]
- Réduire le sucre et les produits laitiers (impact peau) [MODULE: nutrition]
- Vérifier le niveau de stress (peau et cortisol sont liés) [MODULE: mind]

**Problème : "je veux changer ma composition corporelle"**
- Définir objectif précis (perte de gras vs prise de masse) [MODULE: looks]
- Calibrer la nutrition selon l'objectif [MODULE: nutrition]
- Programme d'entraînement adapté (cardio vs musculation) [MODULE: fitness]

**Problème : "ma posture est mauvaise"**
- Exercices de gainage et mobilité dorsale quotidiens [MODULE: fitness]
- Rappel toutes les 45min pour se lever du bureau [MODULE: productivity]
- Vérifier l'ergonomie du poste de travail [MODULE: home]

---

## SOCIAL / RELATIONS

**Problème : "je vois personne / je suis isolé"**
- Planifier 1 sortie sociale par semaine [MODULE: social]
- Rejoindre un club, une activité sportive collective [MODULE: fitness]
- Renouer avec d'anciens contacts (1 message par semaine) [MODULE: social]

**Problème : "j'ai des conflits relationnels"**
- Communication non-violente (CNV) : observation → sentiment → besoin [MODULE: social]
- Travail sur les émotions et la réaction au stress [MODULE: mind]

**Problème : "j'ai du mal à dire non"**
- Pratiquer le refus doux ("je dois vérifier mon agenda") [MODULE: social]
- Identifier pourquoi (peur du conflit, besoin d'approbation) [MODULE: mind]

---

## CYCLE MENSTRUEL

**Problème : "j'ai des douleurs / règles douloureuses"**
- Traquer le cycle pour anticiper et préparer [MODULE: cycle]
- Adapter l'entraînement selon la phase (récupération en phase menstruelle) [MODULE: fitness]
- Réduire le café et le sucre pendant cette période [MODULE: nutrition]

**Problème : "mes humeurs varient beaucoup"**
- Comprendre les 4 phases et adapter ses engagements [MODULE: cycle]
- Magnésium en phase lutéale (réduction SPM prouvée) [MODULE: nutrition]
- Suivre l'humeur pour identifier les corrélations [MODULE: mind]

**Problème : "je suis épuisée à certaines périodes du mois"**
- Phase menstruelle = récupération active prioritaire [MODULE: cycle]
- Réduire les engagements sociaux et professionnels ces jours-là [MODULE: productivity]
- Prioriser le sommeil et la nutrition [MODULE: sleep]

---

## MAISON / INTÉRIEUR

**Problème : "ma maison est désorganisée / j'ai du mal à faire le ménage"**
- Planning hebdo des tâches ménagères dans LifeOS [MODULE: home]
- Méthode 5min/j (5 objets rangés par jour minimum) [MODULE: home]
- Batch le samedi matin (ménage groupé 1h) [MODULE: home]

**Problème : "j'oublie les courses / mal organisé en cuisine"**
- Liste de courses dans LifeOS, même jour chaque semaine [MODULE: home]
- Meal prep du dimanche lié au planning nutrition [MODULE: nutrition]

---

## ADMIN / DOCUMENTS

**Problème : "j'oublie les deadlines administratives"**
- Deadlines dans LifeOS avec rappel J-7 [MODULE: admin]
- Scanner et centraliser tous les documents importants [MODULE: admin]

**Problème : "ma paperasse est en retard / je suis dépassé"**
- Session dédiée mensuelle "Admin Day" (1h30 fixe) [MODULE: admin]
- Classer numériquement dans DocVault dès réception [MODULE: admin]
- Si lié à des finances → audit budgétaire aussi [MODULE: finance]

**Problème : "j'ai trop d'abonnements / contrats qui coûtent cher"**
- Inventaire complet dans LifeOS Subscriptions [MODULE: admin]
- Supprimer tout ce non utilisé ≥30j [MODULE: admin]
- Réinjecter les économies dans l'épargne [MODULE: finance]
