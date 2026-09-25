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

    /// On RETIENT le container, pas seulement le context.
    ///
    /// Un `ModelContext` ne garde pas son `ModelContainer` en vie. Si le container meurt
    /// pendant que ce singleton pointe encore sur son context, la lecture suivante ne
    /// rend pas nil : SwiftData **plante** (SIGTRAP), et aucun `try?` ne l'attrape, on
    /// n'attrape pas un trap.
    ///
    /// Mesure : `CoachInsights.habitConsistency()` faisait tomber le lanceur de tests via
    /// ce chemin (LifeOS-2026-09-25-125352.ips). Meme defaut que ProfileStore.
    private var container: ModelContainer?

    private init() {}

    func setContext(_ ctx: ModelContext) {
        self.context = ctx
        self.container = ctx.container
    }

    /// Detache le fournisseur. A appeler dans le tearDown d'un test qui a pose un context.
    func clearContext() {
        self.context = nil
        self.container = nil
    }
}
