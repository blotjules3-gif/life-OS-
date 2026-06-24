# LifeOS — Super-app de vie (iOS, SwiftUI)

Une seule app, 15 pôles, ~6 300 lignes de Swift, 41 entités SwiftData, 142 écrans.

## Ouvrir & lancer

1. **Installe Xcode** (gratuit, App Store) — tu n'as actuellement que les Command Line Tools, qui ne suffisent pas pour compiler une app iOS.
2. Ouvre `LifeOS/LifeOS.xcodeproj`.
3. Sélectionne un simulateur iPhone (ou ton iPhone branché) puis **⌘R**.
4. Cible : iOS 17+. Le projet utilise les *groupes synchronisés* d'Xcode 16 (pas de conflits `.pbxproj` quand on bosse à plusieurs — voir plus bas).

## Activer les capteurs (optionnel mais recommandé)

Cible **LifeOS → Signing & Capabilities → + Capability → HealthKit**.
Sans ça, l'app compile et tourne, mais les modules pas / HRV / score de récup retombent sur la saisie manuelle. Les textes d'autorisation (caméra, micro, photos, position, santé) sont déjà configurés.

> Sur **simulateur**, les pas/HRV sont souvent vides → teste ces modules sur un vrai iPhone.

## Ce qui est 100% fonctionnel (sans IA ni banque)

Sommeil (cycles, power-nap, coucher progressif, journal de rêves **vocal**, score récup HealthKit) ·
Nutrition (jeûne intermittent, macros, frigo + suggestions recettes, courses, hydratation, compléments, allergènes) ·
Fitness (pas, muscu + **courbe de progression**, HIIT/Tabata, mobilité guidée, streaks) ·
Looksmaxx (skincare + rappels, photos avant/après, mewing/posture, garde-robe + outfit météo) ·
Mental (respiration/cohérence animée, méditation, humeur+gratitude, détox écran, briefing matin) ·
Productivité (to-do, **time-blocking auto**, habit tracker, focus/Pomodoro, notes) ·
Finances (comptes + alertes, budget enveloppes, abonnements, **split Tricount**, épargne) ·
Investissement (portefeuille + camembert, **net worth + projection FIRE**, immo + cashflow, **simulateur IR 2024**) ·
Carrière (candidatures, CV builder + export, skill gap, mock interview) ·
Apprentissage (**flashcards SM-2**, micro-learning, résumés, plan de skill) ·
Maison (anti-gaspi, recettes restes, tâches, **animaux/chats**, maintenance) ·
Mobilité (voiture : assurance/révision/conso/coût carburant) ·
Social (CRM relances, anniversaires + cadeaux, events) ·
Admin (coffre-fort docs **chiffré local**, échéances, **générateur de courriers**) ·
Voyage (itinéraire + budget, **checklist valise auto**).

## Modules « scaffoldés » (UI + données prêtes, intégration externe à brancher)

Chacun affiche précisément ce qu'il faut connecter et lesquelles sont **gratuites** :

| Module | Pourquoi pas direct | Piste branchable |
|---|---|---|
| Calories par photo (Cal AI) | modèle vision | API food-recognition multimodale |
| Scan code-barres (Yuka) | base produits/prix | **OpenFoodFacts (gratuit)** + VisionKit |
| Analyse faciale (Umax) | modèle ML contesté | **Vision (landmarks gratuits)** + ratios |
| Agrégation bancaire (Bankin) | **réglementation DSP2** | Bridge / Powens / Tink (agréé) |
| Cours live portefeuille | flux marché | **CoinGecko / Finnhub (gratuit)** |
| Matching offres (LinkedIn) | CGU fermées | **Adzuna API (gratuit)** |
| Carburant le moins cher | données stations | **prix-carburants.gouv.fr (gratuit)** |
| Itinéraire (Citymapper) | données transport | **Navitia (freemium)** |
| Suivi vols | données aériennes | AviationStack / Amadeus (freemium) |
| Scan & OCR docs | — (faisable !) | **VisionKit on-device (gratuit)** |
| Bloqueur d'apps (Forest) | autorisation Apple | Screen Time API (DeviceActivity) |

## Travailler à plusieurs sur ce projet

- Le projet utilise les **synchronized groups** : ajouter un fichier ne modifie pas `project.pbxproj` → quasi zéro conflit Git.
- Une **branche par personne**, et évitez d'éditer le même fichier `*Module.swift` en même temps (chaque pôle est isolé dans son fichier).
- Pour coder le même fichier en direct à deux : **VS Code Live Share**, chacun build dans son Xcode.

## Architecture

- `Core/` : design system (`Theme`), composants (`Components`), moteur de timer, notifications, HealthKit, stockage d'images, navigation (`AppCategory`, `RootView`).
- `Models/` : 41 entités SwiftData (persistance locale automatique).
- `Modules/` : un fichier par pôle, chacun = un hub + ses outils.
- Beaucoup de briques sont **réutilisées** (timer, anneaux de progression, photo picker, scaffold générique, moteur de recettes…) pour rester maintenable.
