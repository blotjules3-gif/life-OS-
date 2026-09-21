import SwiftUI
import SwiftData

/// LifeOS sur Apple Watch.
///
/// La montre lit la MEME base iCloud que l'iPhone, l'iPad et le Mac: cocher
/// une habitude au poignet la coche partout, sans passer par le telephone.
@main
struct LifeOSWatchApp: App {
    private let container = WatchStore.make()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
        .modelContainer(container)
    }
}

enum WatchStore {
    /// iCloud d'abord. S'il echoue (montre sans compte iCloud, premier
    /// lancement hors ligne), la montre garde une base locale au lieu de
    /// refuser de s'ouvrir.
    static func make() -> ModelContainer {
        let schema = AppSchema.schema
        let cloud = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false,
                                       cloudKitDatabase: .automatic)
        if let c = try? ModelContainer(for: schema, configurations: [cloud]) { return c }
        let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        if let c = try? ModelContainer(for: schema, configurations: [local]) { return c }
        do {
            return try ModelContainer(for: schema, configurations: [
                ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        } catch {
            fatalError("LifeOS Watch: aucune base ouvrable (\(error))")
        }
    }
}

struct WatchRootView: View {
    var body: some View {
        TabView {
            TodayPage()
            HabitsPage()
            WaterPage()
            TabataPage()
        }
        .tabViewStyle(.verticalPage)
    }
}
