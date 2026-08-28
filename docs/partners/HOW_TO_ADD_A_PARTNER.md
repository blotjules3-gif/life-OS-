# Ajouter un partenaire à LifeOS

**Règle absolue** : ne jamais coder en dur un partenaire dans le moteur `GoalPlanTemplate` ou dans les vues. Un partenaire = un adaptateur isolé qui déclare ses capacités.

## Architecture

```
UserGoal
  ↓
GoalPlanTemplate  (neutre, aucune ref partenaire hardcodée)
  ↓
enrichWithPartners()  ← consulte PartnerCatalog dynamiquement
  ↓
GoalPlan (avec Recommendations neutres + partenaires marquées)
  ↓
GoalPlanPreviewSheet (UI marque clairement "neutre" vs "partenaire")
  ↓
GoalPlanExecutor.apply()
```

## Étape 1 — Créer le module partenaire

Créer un fichier dans `LifeOS/Services/Goals/Partners/MyGymPartner.swift` :

```swift
import Foundation

struct MyGymPartner: Partner {
    let id = "mygym.paris15"
    let displayName = "Ma Salle Paris 15"
    let categoryRaw = "fitness"  // AppCategory.fitness.rawValue
    let description = "Salle premium 24/7 avec coachs certifiés."
    var capabilities: Set<PartnerCapability> {
        [.canRecommend, .canRedirect]
        // Ajouter .canBook uniquement si l'API réelle existe.
    }
    var integrationLevel: PartnerIntegrationLevel { .externalLink }
    var externalURL: URL? { URL(string: "https://mygym-paris.com") }
}
```

## Étape 2 — Enregistrer au boot

Dans `LifeOSApp.swift` ou un fichier `PartnerBootstrap.swift` :

```swift
PartnerCatalog.shared.register(MyGymPartner())
```

## Étape 3 — C'est tout

Le moteur `GoalPlanTemplate.enrichWithPartners()` va automatiquement :
- Détecter le partenaire dans les modules concernés (`.fitness` ici)
- Ajouter une `Recommendation` marquée `partnerID: "mygym.paris15"`
- L'UI `GoalPlanPreviewSheet` marque "Offre partenaire — mygym.paris15" en orange

## Règles absolues (§17 spec produit)

- ❌ **Ne jamais** déclarer `.canBook` / `.canPay` / `.canCreateCart` si l'API réelle n'existe pas
- ❌ **Ne jamais** afficher un prix / réduction / disponibilité sans données vérifiables
- ❌ **Ne jamais** simuler une action réussie ("commande envoyée !") sans backend qui l'a exécutée
- ✅ Toujours partir de la capability la plus faible (`.canRecommend`) et monter graduellement

## Niveaux d'intégration graduels

| Niveau | Enum | Ce que ça permet |
|---|---|---|
| 0 | `.none` | Rien (partenaire absent du catalogue) |
| 1 | `.externalLink` | Recommandation + redirect URL |
| 2 | `.commercial` | Offres, codes promo (visuel spécifique UI) |
| 3 | `.api` | Recherche produits, création panier, etc. |
| 4 | `.execution` | Action réelle après validation user (paiement, réservation) |

Monter d'un niveau nécessite :
- Contrat commercial signé (`.commercial`)
- Auth API + clé serveur (`.api`)
- Auth OAuth user + PCI DSS si paiement (`.execution`)

## Tests obligatoires

Ajouter dans `LifeOSTests/PartnerCatalogTests.swift` :

```swift
func testMyGym_registeredWithCorrectCapabilities() {
    PartnerCatalog.shared.register(MyGymPartner())
    let p = PartnerCatalog.shared.partner(id: "mygym.paris15")
    XCTAssertNotNil(p)
    XCTAssertTrue(p!.capabilities.contains(.canRecommend))
    XCTAssertFalse(p!.capabilities.contains(.canPay), "Ne pas déclarer canPay sans intégration paiement réelle")
}
```

## Vérification finale

Après enregistrement, tape dans le chat "je veux prendre du muscle" → sheet plan → tu dois voir dans "Conseils" une ligne "Ma Salle Paris 15" marquée **Offre partenaire — mygym.paris15**.
