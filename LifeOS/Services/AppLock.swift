import Foundation
import LocalAuthentication
import SwiftUI

/// Verrou optionnel de l'app par Face ID / Touch ID / code.
/// Verrouille au passage en arrière-plan, déverrouille via LocalAuthentication.
@Observable
final class AppLock {
    static let shared = AppLock()

    var isLocked = false
    var isAuthenticating = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "appLockEnabled") }
        set {
            UserDefaults.standard.set(newValue, forKey: "appLockEnabled")
            if !newValue { isLocked = false }
        }
    }

    /// Vrai si l'appareil peut authentifier (Face ID, Touch ID ou code).
    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var biometryLabel: String {
        switch LAContext().biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "Code de l'appareil"
        }
    }

    private init() {}

    func lockIfNeeded() {
        guard isEnabled else { return }
        isLocked = true
    }

    @MainActor
    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = "Annuler"
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Déverrouille LifeOS pour accéder à tes données."
            )
            if ok { isLocked = false }
        } catch {
            // Annulé ou échec : on reste verrouillé, l'utilisateur peut réessayer.
        }
    }
}

/// Écran opaque affiché par-dessus l'app tant qu'elle est verrouillée.
struct AppLockScreen: View {
    @State private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                VStack(spacing: 6) {
                    Text("LifeOS est verrouillé")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("Tes données restent privées.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Déverrouiller", systemImage: "faceid")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .task { await lock.unlock() }
    }
}
