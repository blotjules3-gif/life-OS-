import SwiftUI
#if os(iOS) && !targetEnvironment(macCatalyst)
import FamilyControls
import ManagedSettings
#endif

/// Blocage reel d'applications (Screen Time API d'Apple).
///
/// Etat au 30 sept. 2026 : le code est pret, mais l'autorisation de DISTRIBUTION
/// "Family Controls" n'est pas encore accordee au compte developpeur. Sans elle,
/// `requestAuthorization` echoue et l'ecran le dit, au lieu de faire semblant.
/// Quand Apple l'accorde : ajouter `com.apple.developer.family-controls` a
/// LifeOS.entitlements et regenerer le profil. Rien d'autre a changer ici.
///
/// Limite assumee de cette premiere etape : sans extension DeviceActivity, la fin
/// d'une session est appliquee a la prochaine ouverture de LifeOS (ou par le bouton
/// Debloquer), pas a la seconde pres en arriere-plan.
@MainActor
final class ScreenTimeBlocker: ObservableObject {
    static let shared = ScreenTimeBlocker()

    enum Status: Equatable {
        case unsupported            // Mac, simulateur sans Screen Time...
        case notDetermined
        case denied(String)
        case approved
    }

    @Published private(set) var status: Status = .notDetermined
    @Published private(set) var sessionEnd: Date?
    @Published var lastError: String?

    private static let endKey = "screenBlock.end"
    private static let selectionKey = "screenBlock.selection"

    #if os(iOS) && !targetEnvironment(macCatalyst)
    @Published var selection = FamilyActivitySelection() {
        didSet { saveSelection() }
    }
    private let store = ManagedSettingsStore(named: .init("lifeos.focus"))

    var hasSelection: Bool { !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty }
    var selectionSummary: String {
        let a = selection.applicationTokens.count, c = selection.categoryTokens.count
        return "\(a) app\(a > 1 ? "s" : ""), \(c) catégorie\(c > 1 ? "s" : "")"
    }
    #else
    var hasSelection: Bool { false }
    var selectionSummary: String { "" }
    #endif

    private init() {
        let t = UserDefaults.standard.double(forKey: Self.endKey)
        sessionEnd = t > 0 ? Date(timeIntervalSince1970: t) : nil
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if let data = UserDefaults.standard.data(forKey: Self.selectionKey),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = sel
        }
        refreshStatus()
        #else
        status = .unsupported
        #endif
    }

    func refreshStatus() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: status = .approved
        case .denied: status = .denied("Autorisation refusée : Réglages > Temps d'écran.")
        default: if case .denied = status {} else { status = .notDetermined }
        }
        #endif
    }

    func requestAuthorization() async {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshStatus()
        } catch {
            status = .denied(Self.explain(error))
        }
        #endif
    }

    /// Message lisible. L'erreur la plus probable aujourd'hui est l'absence de
    /// l'autorisation Apple dans l'app elle-meme, pas un refus de l'utilisateur.
    static func explain(_ error: Error) -> String {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if let fc = error as? FamilyControlsError {
            switch fc {
            case .authorizationCanceled: return "Demande annulée. Tu peux réessayer quand tu veux."
            case .restricted: return "Temps d'écran est limité sur cet appareil (contrôle parental ou profil)."
            case .invalidAccountType: return "Il faut être connecté à iCloud avec un compte adulte pour autoriser Temps d'écran."
            case .authenticationMethodUnavailable: return "Active un code sur l'appareil pour autoriser Temps d'écran."
            default: break
            }
        }
        #endif
        if String(describing: error).lowercased().contains("entitlement") {
            return "Le blocage réel attend l'autorisation « Family Controls » d'Apple pour LifeOS. En attendant, le suivi manuel ci-dessous reste disponible."
        }
        return "Temps d'écran n'a pas pu être autorisé : \(error.localizedDescription). Sans l'autorisation Apple « Family Controls », c'est attendu ; le suivi manuel reste disponible."
    }

    /// Bloque la selection pendant `minutes`. Refuse s'il n'y a rien a bloquer.
    func block(minutes: Int) {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        guard status == .approved else { lastError = "Autorise d'abord Screen Time."; return }
        guard hasSelection else { lastError = "Choisis d'abord les apps à bloquer."; return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        let end = Date().addingTimeInterval(TimeInterval(max(1, minutes) * 60))
        sessionEnd = end
        UserDefaults.standard.set(end.timeIntervalSince1970, forKey: Self.endKey)
        lastError = nil
        #endif
    }

    func unblock() {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        store.clearAllSettings()
        #endif
        sessionEnd = nil
        UserDefaults.standard.removeObject(forKey: Self.endKey)
    }

    /// A appeler a l'ouverture : leve un blocage dont l'heure de fin est passee.
    func expireIfNeeded(now: Date = .now) {
        if let end = sessionEnd, end <= now { unblock() }
    }

    #if os(iOS) && !targetEnvironment(macCatalyst)
    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            UserDefaults.standard.set(data, forKey: Self.selectionKey)
        }
    }
    #endif
}

/// Carte "Blocage d'apps" de l'outil Opale.
struct ScreenBlockCard: View {
    @ObservedObject private var blocker = ScreenTimeBlocker.shared
    @State private var showPicker = false
    @State private var minutes = 60
    @Environment(\.scenePhase) private var phase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocage d'apps").font(.headline)
            switch blocker.status {
            case .unsupported:
                Text("Le blocage d'apps se règle sur iPhone ou iPad.").font(.caption).foregroundStyle(.secondary)
            case .denied(let why):
                Label(why, systemImage: "lock.trianglebadge.exclamationmark").font(.caption).foregroundStyle(.secondary)
                Button("Réessayer") { Task { await blocker.requestAuthorization() } }
                    .buttonStyle(LifeOSGlassButtonStyle())
            case .notDetermined:
                Text("Bloque pour de vrai les apps qui te prennent du temps, pendant une durée choisie. Apple demande ton accord Temps d'écran.")
                    .font(.caption).foregroundStyle(.secondary)
                Button { Task { await blocker.requestAuthorization() } } label: {
                    Label("Autoriser Temps d'écran", systemImage: "hourglass").frame(maxWidth: .infinity)
                }.buttonStyle(LifeOSGlassButtonStyle(prominent: true))
            case .approved:
                approvedControls
            }
            if let e = blocker.lastError { Text(e).font(.caption).foregroundStyle(Theme.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear { blocker.refreshStatus(); blocker.expireIfNeeded() }
        .onChange(of: phase) { _, p in if p == .active { blocker.expireIfNeeded() } }
    }

    @ViewBuilder private var approvedControls: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst)
        if let end = blocker.sessionEnd {
            Label("Bloqué jusqu'à \(end.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
                .font(.subheadline.weight(.semibold))
            Button(role: .destructive) { blocker.unblock() } label: {
                Text("Débloquer maintenant").frame(maxWidth: .infinity)
            }.buttonStyle(LifeOSGlassButtonStyle())
            Text("La fin est appliquée à la prochaine ouverture de LifeOS.").font(.caption2).foregroundStyle(.secondary)
        } else {
            Button { showPicker = true } label: {
                Label(blocker.hasSelection ? "Apps choisies : \(blocker.selectionSummary)" : "Choisir les apps à bloquer",
                      systemImage: "square.grid.3x3").frame(maxWidth: .infinity)
            }.buttonStyle(LifeOSGlassButtonStyle())
            Stepper("Durée : \(minutes) min", value: $minutes, in: 15...480, step: 15)
            Button { blocker.block(minutes: minutes) } label: {
                Label("Bloquer maintenant", systemImage: "lock.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
            .disabled(!blocker.hasSelection)
        }
        EmptyView().familyActivityPicker(isPresented: $showPicker, selection: $blocker.selection)
        #endif
    }
}
