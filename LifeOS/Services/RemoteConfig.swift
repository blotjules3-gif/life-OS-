import Foundation

/// Feature flags — depuis Option C (100 % local), plus de kill switch distant :
/// le coach tourne on-device et n'a pas besoin d'un serveur pour être activé
/// ou désactivé côté produit. On garde la même API `chatEnabled` pour ne
/// casser aucun appelant existant.
@Observable
@MainActor
final class RemoteConfig {
    static let shared = RemoteConfig()

    private(set) var chatEnabled: Bool = true

    private init() {}

    /// Conservée pour compatibilité — no-op depuis Option C.
    func refreshIfNeeded() async {}

    /// Conservée pour compatibilité — no-op depuis Option C.
    func refresh() async {}
}
