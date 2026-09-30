import SwiftUI
import SwiftData

/// Local access is available. Remote identity providers must not report success
/// until a real provider exchange and server-side verification are implemented.
struct AuthView: View {
    var isModal: Bool = false
    var initialMode: AuthMode = .login
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @AppStorage(AppStorageKeys.isAuthenticated) private var isAuthenticated = false
    @AppStorage(AppStorageKeys.userEmail) private var userEmail = ""
    @AppStorage(AppStorageKeys.authProvider) private var authProvider = ""
    @AppStorage(AppStorageKeys.userId) private var userId = ""
    @AppStorage(AppStorageKeys.userName) private var userName = ""
    @AppStorage(AppStorageKeys.userDisplayName) private var userDisplayName = ""
    @AppStorage(AppStorageKeys.recommendedModules) private var recommendedModulesRaw = ""
    @AppStorage(AppStorageKeys.homeShortcuts) private var homeShortcuts = ""
    @State private var localName = ""
    @State private var showAccountInfo = false

    enum AuthMode: String, CaseIterable {
        case login = "Connexion"
        case signup = "Inscription"
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    if isModal {
                        HStack {
                            Spacer()
                            Button("Fermer", systemImage: "xmark") { dismiss() }
                                .labelStyle(.iconOnly)
                                .buttonStyle(LifeOSGlassButtonStyle())
                        }
                    }
                    Image(systemName: "infinity")
                        .font(.system(size: 48, weight: .bold))
                        .frame(width: 96, height: 96)
                        .raisedSurface(Circle())
                    Text("LifeOS").font(.largeTitle.bold())
                    Text("Ton espace personnel, sur cet appareil.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Mode local").font(.headline)
                        Text("Utilise les outils de LifeOS sans compte en ligne. Ce mode ne connecte aucun compte Apple, Google, Facebook ou email.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextField("Ton prénom (facultatif)", text: $localName)
                            .textContentType(.givenName)
                            .padding(14)
                            .raisedSurface(RoundedRectangle(cornerRadius: 14), .nested)
                        Button(action: enterLocalMode) {
                            Text("Continuer en mode local")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .applePreviewPill(height: 48)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .applePreviewCard(cornerRadius: 24)
                    Button("À propos des comptes en ligne") { showAccountInfo = true }
                        .buttonStyle(LifeOSGlassButtonStyle())
                    Text("La connexion et la récupération de compte en ligne ne sont pas encore disponibles dans cette version.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear { localName = userDisplayName }
        .alert("Comptes en ligne indisponibles", isPresented: $showAccountInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Apple, Google, Facebook et email nécessitent une connexion vérifiée. Aucun compte en ligne n'est créé par le mode local. Tes données locales restent disponibles.")
        }
    }

    private func enterLocalMode() {
        let name = localName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            userDisplayName = name
            if userName.isEmpty { userName = name }
        }
        userEmail = ""
        authProvider = "guest"
        if userId.isEmpty { userId = UUID().uuidString }
        // Choisir le mode local n'est PAS avoir repondu au questionnaire: la racine de
        // l'app enchaine sur l'onboarding tant qu'onboardingDone est faux.
        ensureUserDataIsReady()
        // Existing app flag means the local root can be entered, not remote verification.
        isAuthenticated = true
        Haptics.success()
        dismiss()
    }

    private func ensureUserDataIsReady() {
        if recommendedModulesRaw.isEmpty {
            recommendedModulesRaw = "fitness,nutrition,sleep,productivity,finance,mind"
        }
        if homeShortcuts.isEmpty {
            homeShortcuts = "tabata,calories,scan,todo,fasting,water,habits,mood"
        }
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        if habits.isEmpty {
            QuickStart.apply(goal: "performance", ctx: ctx)
        } else {
            do { try ctx.save() } catch { }
        }
    }
}
