import Foundation
import SwiftData
import UserNotifications

/// Suppression complete des donnees utilisateur (guideline 5.1.1(v), droit a l'oubli).
///
/// Audit du 28 septembre: l'ancienne version supprimait 52 types sur 54 (oubliait
/// `ProfileField` et `ProfileFieldRevision`), laissait `Documents/Yuko`, le cache
/// produits et les listes en memoire, cherchait les copies de securite dans le
/// mauvais dossier, n'annulait pas une restauration en attente (les donnees
/// revenaient au lancement suivant), et annoncait "efface" meme quand une etape
/// echouait. Ici tout part d'UN inventaire (`StorageInventory`), chaque etape rend
/// son echec, et l'ecran n'annonce le succes que si le rapport est vide.
enum DataEraser {

    /// Tous les endroits ou LifeOS range quelque chose.
    struct StorageInventory {
        var documents: URL          // photos, pages, audio, journaux, Yuko
        var support: URL            // copies de securite, restauration en attente
        var caches: URL             // cache produits
        var defaults: UserDefaults
        var groupDefaults: UserDefaults?
        var defaultsDomain: String?

        static var app: StorageInventory {
            StorageInventory(documents: AppPaths.documents, support: AppPaths.support, caches: AppPaths.caches,
                             defaults: .standard, groupDefaults: UserDefaults(suiteName: FullBackup.groupSuite),
                             defaultsDomain: Bundle.main.bundleIdentifier)
        }
    }

    struct Report {
        var failures: [String] = []
        var succeeded: Bool { failures.isEmpty }
    }

    /// Cles gardees par "recommencer a zero" (prenom, theme, onboarding).
    static let onboardingKeys: Set<String> = [
        AppStorageKeys.onboardingDone, AppStorageKeys.appTheme, AppStorageKeys.userName,
        AppStorageKeys.userGender, AppStorageKeys.lifeProfile, AppStorageKeys.recommendedModules,
    ]

    @MainActor @discardableResult
    static func eraseAllData(container: ModelContainer, inventory: StorageInventory = .app) -> Report {
        erase(container: container, keepKeys: [], inventory: inventory)
    }

    @MainActor @discardableResult
    static func eraseAndKeepOnboarding(container: ModelContainer, inventory: StorageInventory = .app) -> Report {
        erase(container: container, keepKeys: onboardingKeys, inventory: inventory)
    }

    @MainActor
    static func erase(container: ModelContainer, keepKeys: Set<String>, inventory inv: StorageInventory) -> Report {
        var report = Report()
        func step(_ name: String, _ body: () throws -> Void) {
            do { try body() } catch { report.failures.append("\(name) : \(error.localizedDescription)") }
        }

        // 1. Une restauration en attente ferait revenir les donnees au lancement suivant.
        step("restauration en attente") {
            let pending = inv.support.appendingPathComponent("LifeOSPendingRestore", isDirectory: true)
            if FileManager.default.fileExists(atPath: pending.path) { try FileManager.default.removeItem(at: pending) }
        }
        // 2. Base: TOUS les types du schema, puis verification qu'il n'en reste rien.
        step("base de données") { try eraseModels(container.mainContext) }
        // 3. Fichiers internes (photos, pages, audio, Yuko...). Le dossier est celui
        //    de LifeOS (AppPaths), jamais le ~/Documents d'un Mac sans sandbox.
        step("fichiers") { try FullBackup.checkRoot(inv.documents); try emptyDirectory(inv.documents) }
        step("copies de sécurité") { try removeChildren(of: inv.support, prefix: "LifeOSBackup-") }
        step("cache produits") {
            let yuko = inv.caches.appendingPathComponent("Yuko", isDirectory: true)
            if FileManager.default.fileExists(atPath: yuko.path) { try FileManager.default.removeItem(at: yuko) }
        }
        URLCache.shared.removeAllCachedResponses()
        step("listes Yuko en mémoire") { try ProductStore.shared.eraseAll() }
        step("cours Trilingo et progression") { try TrilingoStore.shared.eraseAll() }
        step("nuits et extraits sonores") { try NightStore.shared.eraseAll() }
        // 4. Reglages (sauf ceux a garder) et groupe des widgets.
        eraseDefaults(inv.defaults, domain: inv.defaultsDomain, keep: keepKeys)
        if let group = inv.groupDefaults {
            for key in group.dictionaryRepresentation().keys { group.removeObject(forKey: key) }
        }
        // 5. Rappels programmes et deja affiches.
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        // 6. Artefacts IA et caches en memoire.
        eraseAIArtifacts()
        AppLog.data.info("DataEraser: \(report.succeeded ? "effacement complet" : "effacement INCOMPLET: \(report.failures.count) échec(s)")")
        return report
    }

    /// Supprime chaque type du schema, enregistre, puis recompte.
    @MainActor
    static func eraseModels(_ ctx: ModelContext) throws {
        for type in LocalStore.modelTypes { try deleteAll(type, ctx) }
        try ctx.save()
        let left = try LocalStore.modelTypes.map { try count($0, ctx) }.reduce(0, +)
        guard left == 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "\(left) élément(s) encore présents"]) }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) throws {
        try ctx.delete(model: type)
    }

    static func count<T: PersistentModel>(_ type: T.Type, _ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<T>())
    }

    /// Vide un dossier. Un dossier illisible est une erreur, pas un succes.
    static func emptyDirectory(_ dir: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        for item in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            try fm.removeItem(at: item)
        }
    }

    private static func removeChildren(of dir: URL, prefix: String) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return }
        for item in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where item.lastPathComponent.hasPrefix(prefix) {
            try fm.removeItem(at: item)
        }
    }

    /// Supprime les reglages de l'app. Avec un domaine (cas reel), c'est le domaine
    /// de l'app qui est vide, donc aucune cle systeme n'est touchee.
    private static func eraseDefaults(_ ud: UserDefaults, domain: String?, keep: Set<String>) {
        let keys: [String]
        if let domain, let dict = ud.persistentDomain(forName: domain) { keys = Array(dict.keys) }
        else { keys = Array(ud.dictionaryRepresentation().keys).filter { !$0.hasPrefix("com.apple.") && !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") } }
        for key in keys where !keep.contains(key) { ud.removeObject(forKey: key) }
    }

    /// Artefacts IA locaux (feedback coach, rapports, compteurs).
    @MainActor
    static func eraseAIArtifacts() {
        CoachFeedbackStore.reset()
        try? FileManager.default.removeItem(at: AppPaths.documents.appendingPathComponent("coach_reports.jsonl"))
        AIActivityLogger.shared.clear()
        AIProviderUsageTracker.shared.resetAll()
        AICostGuardPreference.shared.reset()
        CoachUpgradeSuggestion.shared.reset()
        CoachVoiceMode.shared.reset()
        MonthlyReviewScheduler.cancel()
        UserContextBuilder.shared.invalidateCache()
    }

    // MARK: - Export JSON

    /// Export léger : dump des UserDefaults non-système + compte des entités SwiftData.
    /// Permet à l'user d'avoir un aperçu textuel de ses données avant suppression.
    /// Version 1 : JSON minimal, pas les blobs images.
    @MainActor
    static func exportBackup(container: ModelContainer) -> Data? {
        let ctx = container.mainContext
        var payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: .now),
            "version": 1
        ]

        // UserDefaults (filtrés)
        let ud = UserDefaults.standard.dictionaryRepresentation()
        var udExport: [String: Any] = [:]
        for (k, v) in ud where !k.hasPrefix("com.apple.") && !k.hasPrefix("NS") && !k.hasPrefix("Apple") {
            if v is String || v is NSNumber || v is Bool || v is Int || v is Double {
                udExport[k] = v
            }
        }
        payload["preferences"] = udExport

        // Compte des entités
        var counts: [String: Int] = [:]
        counts["habits"]    = (try? ctx.fetchCount(FetchDescriptor<Habit>())) ?? 0
        counts["moods"]     = (try? ctx.fetchCount(FetchDescriptor<MoodEntry>())) ?? 0
        counts["sleeps"]    = (try? ctx.fetchCount(FetchDescriptor<SleepNight>())) ?? 0
        counts["foods"]     = (try? ctx.fetchCount(FetchDescriptor<FoodEntry>())) ?? 0
        counts["workouts"]  = (try? ctx.fetchCount(FetchDescriptor<WorkoutSet>())) ?? 0
        counts["notes"]     = (try? ctx.fetchCount(FetchDescriptor<Note>())) ?? 0
        counts["todos"]     = (try? ctx.fetchCount(FetchDescriptor<TodoItem>())) ?? 0
        counts["photos"]    = (try? ctx.fetchCount(FetchDescriptor<ProgressPhoto>())) ?? 0
        counts["chatMessages"] = (try? ctx.fetchCount(FetchDescriptor<AIMessage>())) ?? 0
        payload["entityCounts"] = counts

        return try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
