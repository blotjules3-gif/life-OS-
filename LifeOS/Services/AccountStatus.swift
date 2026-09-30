import Foundation

/// Ce que le profil a le droit d'afficher sur le compte et la synchronisation.
///
/// Avant (brief du 28 septembre): "Synchronisation active", "Chiffrement bout en
/// bout · Temps réel · Actif", des appareils "Prêt", et un badge "Compte vérifié &
/// actif" deduit de la simple presence d'un email. Or cette version n'a aucun
/// compte en ligne (seul le mode local existe) et aucune capacite iCloud: tout
/// reste sur l'appareil. Chaque libelle vient maintenant d'un etat reel.
enum AccountStatus {

    /// Aucun compte en ligne ne peut etre cree dans cette version (voir AuthView).
    static let onlineAccountsAvailable = false

    struct Storage: Equatable {
        let title: String
        let detail: String
        let synced: Bool
    }

    static func storage(syncActive: Bool) -> Storage {
        syncActive
            ? Storage(title: "iCloud",
                      detail: "Tes données sont copiées dans ton compte iCloud et arrivent sur tes autres appareils connectés au même compte, avec un délai.",
                      synced: true)
            : Storage(title: "Sur cet appareil",
                      detail: "Pas de synchronisation entre appareils dans cette version. Pour garder une copie ou changer d'appareil, utilise l'export de tes données.",
                      synced: false)
    }

    enum Account: Equatable {
        case local
        case online(provider: String)
    }

    /// Un email ou un fournisseur restes d'une ancienne version ne font PAS un
    /// compte verifie.
    static func account(isAuthenticated: Bool, provider: String, email: String) -> Account {
        guard onlineAccountsAvailable, isAuthenticated,
              ["apple", "google", "facebook", "email"].contains(provider), !email.isEmpty
        else { return .local }
        return .online(provider: provider)
    }

    static func label(_ a: Account) -> String {
        switch a {
        case .local: return "Session locale"
        case .online(let p): return "Connecté avec \(p.capitalized)"
        }
    }
}
