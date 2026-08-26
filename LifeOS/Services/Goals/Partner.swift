import Foundation

/// Abstraction d'un partenaire externe (salle de sport, supermarché, banque,
/// coach, nutritionniste, etc.).
///
/// **Règle absolue** (spéc produit user) : ne JAMAIS coder en dur un
/// partenaire dans le moteur. Chaque partenaire doit être un module/adaptateur
/// séparé qui déclare ses capabilities. Le moteur affiche uniquement les
/// actions réellement supportées.
///
/// Aucun partenaire réel n'est implémenté à ce jour — cette architecture
/// est prête pour Phase 2+ (ajout progressif de partenaires).
protocol Partner: Sendable {
    /// ID stable unique (kebab-case). Utilisé dans `Recommendation.partnerID`.
    var id: String { get }
    /// Nom affichable ("Ma Salle Paris 15", "Auchan Drive"…).
    var displayName: String { get }
    /// Catégorie principale (`AppCategory.rawValue`).
    var categoryRaw: String { get }
    /// Description courte user-facing.
    var description: String { get }
    /// Capacités exposées — l'UI adapte les boutons disponibles selon ce set.
    var capabilities: Set<PartnerCapability> { get }
    /// Niveau d'intégration réel (0 à 4). Voir enum.
    var integrationLevel: PartnerIntegrationLevel { get }
    /// URL publique pour redirect si `.canRedirect` (App Store, site web…).
    var externalURL: URL? { get }
}

/// Capacités qu'un partenaire peut exposer. Le moteur adapte l'UI en fonction.
enum PartnerCapability: String, Sendable, Codable {
    case canRecommend        // Peut être proposé comme option dans un plan
    case canRedirect         // Lien externe fonctionnel
    case canSearchProducts   // Recherche catalogue produits (nécessite API)
    case canCreateCart       // Création panier (nécessite API + auth user)
    case canBook             // Réservation (nécessite API + auth user)
    case canSync             // Sync données (nécessite OAuth + API)
    case canPay              // Paiement (nécessite intégration paiement réelle)
    case canRetrieveData     // Récupère data user existante
}

/// Niveaux d'intégration réels (spec produit user § 3.1-3.5).
enum PartnerIntegrationLevel: Int, Sendable, Codable {
    case none = 0         // Aucun partenariat — pas affiché
    case externalLink = 1 // Redirect vers site officiel
    case commercial = 2   // Partenariat commercial — codes promo, offres
    case api = 3          // Intégration API officielle
    case execution = 4    // User peut valider une action directe

    var displayName: String {
        switch self {
        case .none:         return "Aucun partenariat"
        case .externalLink: return "Lien externe"
        case .commercial:   return "Partenariat commercial"
        case .api:          return "Intégration API"
        case .execution:    return "Exécution directe"
        }
    }
}
