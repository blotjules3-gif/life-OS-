import Foundation

/// Registry central des partenaires disponibles.
///
/// **État actuel : catalogue VIDE.** Aucun partenaire n'est implémenté —
/// c'est volontaire. L'application fonctionne 100 % sans partenaire (§ 4
/// spec produit : "l'app doit être utile avant même d'avoir un partenaire").
///
/// Ajouter un partenaire = créer un nouveau fichier `MyPartner: Partner` +
/// l'enregistrer ici via `register(_:)`. Aucune modification du moteur.
@MainActor
final class PartnerCatalog {
    static let shared = PartnerCatalog()

    private var partners: [String: any Partner] = [:]

    private init() {
        // AUCUN partenaire enregistré — spec produit § 17 :
        // "Ne jamais inventer une API/partenariat/réduction/prix/disponibilité".
    }

    /// Enregistre un partenaire (à appeler par l'app au boot ou par un
    /// module partenaire dédié).
    func register(_ partner: any Partner) {
        partners[partner.id] = partner
    }

    /// Tous les partenaires d'une catégorie.
    func partners(for categoryRaw: String) -> [any Partner] {
        partners.values.filter { $0.categoryRaw == categoryRaw }
    }

    /// Partenaires exposant une capability donnée.
    func partners(with capability: PartnerCapability, in categoryRaw: String? = nil) -> [any Partner] {
        partners.values.filter { p in
            p.capabilities.contains(capability) &&
            (categoryRaw == nil || p.categoryRaw == categoryRaw)
        }
    }

    /// Récupère un partenaire par ID.
    func partner(id: String) -> (any Partner)? {
        partners[id]
    }

    /// Vrai si au moins un partenaire est enregistré (info debug/UI).
    var hasAnyPartner: Bool { !partners.isEmpty }
}
