import Foundation
import SwiftData

/// Fournit un accès partagé au `ModelContext` SwiftData pour les services
/// non-View (tools, orchestrateurs, background tasks).
///
/// Pattern : injecté au boot par LifeOSApp via `setContext(...)`. Les tools
/// (CrossDomainTools) peuvent ensuite fetch sans avoir à passer le context
/// à chaque appel.
///
/// Nil si l'app n'a pas encore bootstrapé — les tools skippent silencieusement.
@MainActor
final class SharedModelContextProvider {
    static let shared = SharedModelContextProvider()

    private(set) var context: ModelContext?

    private init() {}

    func setContext(_ ctx: ModelContext) {
        self.context = ctx
    }
}
