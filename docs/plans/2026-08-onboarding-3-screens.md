# Plan — Refonte onboarding en 3 écrans

**Statut** : documenté pour session dédiée (skippé en Phase 3 autonome — trop risqué sans validation UX visuelle).

## État actuel

- `LifeOS/Core/OnboardingView.swift` : 1597 lignes
- `IntakeHubView` : présentée juste après onboarding (2ᵉ tunnel)
- Total flow user J1 : 8-10 étapes onboarding + 15 modules à setup dans IntakeHub
- Estimation abandon : ~60 % au J1 (industry standard sur ce type de tunnel)

## Cible

3 écrans max avant l'utilisateur voit la Home :

### Écran 1 — Identité + objectif
- Prénom (TextField)
- 1 choix parmi 5 objectifs principaux (Santé, Performance, Argent, Focus, Habitudes)
- Bouton "Suivant" (disabled tant que prénom vide)

### Écran 2 — Modules pré-cochés (décision inversée)
- 3 modules pré-cochés selon l'objectif choisi (ex. Santé → Sommeil, Nutrition, Fitness)
- L'user peut dé-cocher ceux qu'il ne veut pas + cocher d'autres parmi les 12 restants
- Message : "Tu pourras toujours en ajouter plus tard depuis le Profil"

### Écran 3 — Permission notifs (contexte)
- Pré-prompt clair : "LifeOS va te rappeler tes habitudes, ton coucher, tes séances"
- Bouton "Activer les notifications" (déclenche le prompt système)
- Bouton discret "Plus tard"

Puis direct dans la HomeView. Fini l'IntakeHubView.

## Découpe fichiers

```
LifeOS/Core/Onboarding/
├── OnboardingRouter.swift       # Flow, gestion des étapes
├── StepIdentity.swift           # Écran 1
├── StepModules.swift            # Écran 2
├── StepNotifications.swift      # Écran 3
└── OnboardingModels.swift       # Types partagés (Goal enum, ModuleSuggestions)
```

Remplacer `OnboardingView` dans `LifeOSApp.appContent` par `OnboardingRouter`.

## Setup modules progressif (remplace IntakeHubView)

Chaque hub de module non-configuré affiche un empty state avec un CTA "Configurer en 30 sec".
Le setup se fait au moment où l'user ouvre le module — pas en batch à la fin.

Modifier chaque `CategoryHubView(category:)` pour vérifier si un flag `moduleConfig_\(rawValue)` existe.
Si non → afficher `ModuleSetupPrompt(category:)` au top du hub avec bouton pour lancer `CategoryFlowView`.

## Risques identifiés

1. **Cassure des flags de setup** : `IntakeHubView` set des flags spécifiques. Il faut trouver toutes les branches qui lisent ces flags et les adapter.
2. **Régression sur les modules déjà setup** : les users existants ne doivent pas repasser par setup.
3. **Permission notifs** : le pré-prompt actuel est dans `IntakeHubView` — le déplacer sans casser le flow d'autorisation.
4. **Analytics** : les events `onboarding.step.completed` doivent être renommés / adaptés.

## Estimation

- Découpe fichiers + refactor : 5h
- Adaptation setup progressif par module (15 modules) : 3h
- Tests UI + validation flow : 2h
- Migration users existants (feature flag pour ne pas re-onboarder) : 2h

**Total : 12h** en session dédiée avec validation visuelle continue.

## Prérequis

- Validation avec Jules de la wording des 3 écrans (prénom, objectifs, modules recommandés)
- Screenshot de référence de l'onboarding cible (peut être Figma ou juste description)
- Test en simulateur après chaque écran extrait

## Pourquoi skippé en Phase 3 autonome

Cette refonte modifie le premier écran que voit tout nouvel utilisateur. Une régression subtile
(bouton disabled qui ne se ré-enable pas, flag qui ne se sauvegarde pas, permission qui ne se
demande pas) peut passer inaperçue au build mais casser l'app en usage réel.

Sans simulateur interactif + toi qui teste chaque étape, le risque est élevé.
