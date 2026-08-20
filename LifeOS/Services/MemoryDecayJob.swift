import Foundation
import SwiftData

/// Nettoie et fait décroître la confidence des entrées mémoire trop anciennes.
///
/// Règles :
/// - MemoryEntry > 6 mois sans re-mention → si pas pinnée, isPinned reste false et content marqué "obsolète:"
/// - MemoryEntry > 12 mois → archivé (supprimé du contexte injecté)
/// - ProfileFieldRevision > 12 mois → supprimé (garde uniquement les 12 dernières révisions du field)
///
/// À appeler périodiquement — au boot app (limite fréquence 7j) ou depuis
/// `CoachProactiveScheduler` en piggy-back.
@MainActor
enum MemoryDecayJob {

    private static let lastRunKey = "memory.decay.lastRun"
    private static let minInterval: TimeInterval = 7 * 86400 // 7 jours

    /// Point d'entrée idempotent — no-op si tourné il y a moins de 7 jours.
    static func runIfNeeded(context: ModelContext) {
        let ud = UserDefaults.standard
        if let last = ud.object(forKey: lastRunKey) as? Date,
           Date().timeIntervalSince(last) < minInterval {
            return
        }
        runFull(context: context)
        ud.set(Date(), forKey: lastRunKey)
    }

    /// Force exécution (bouton debug).
    static func runFull(context: ModelContext) {
        cleanupOldMemories(context: context)
        cleanupOldRevisions(context: context)
    }

    // MARK: - Memory cleanup

    private static func cleanupOldMemories(context: ModelContext) {
        let now = Date()
        let sixMonthsAgo = now.addingTimeInterval(-180 * 86400)
        let twelveMonthsAgo = now.addingTimeInterval(-365 * 86400)

        let all = (try? context.fetch(FetchDescriptor<MemoryEntry>())) ?? []
        var toDelete: [MemoryEntry] = []
        for entry in all {
            if entry.isPinned { continue }
            if entry.created < twelveMonthsAgo {
                toDelete.append(entry)
            } else if entry.created < sixMonthsAgo, !entry.content.hasPrefix("[obsolète]") {
                entry.content = "[obsolète] " + entry.content
            }
        }
        for entry in toDelete {
            context.delete(entry)
        }
        LifeOSTry(try context.save(), context: "MemoryDecayJob cleanupOldMemories", category: AppLog.data)
    }

    // MARK: - Revision cleanup

    private static func cleanupOldRevisions(context: ModelContext) {
        // Garde max 12 révisions par ProfileField
        let all = (try? context.fetch(FetchDescriptor<ProfileField>())) ?? []
        for field in all {
            guard field.history.count > 12 else { continue }
            let sorted = field.history.sorted { $0.changedAt > $1.changedAt }
            let toRemove = Array(sorted.dropFirst(12))
            for rev in toRemove {
                context.delete(rev)
            }
        }
        LifeOSTry(try context.save(), context: "MemoryDecayJob cleanupOldRevisions", category: AppLog.data)
    }
}
