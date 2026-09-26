import SwiftUI
import SwiftData

@main
struct LifeOSApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var alarm = AlarmManager.shared
    @State private var appLock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var container: ModelContainer?
    @State private var migrationFailed = false
    @State private var storeWasReset = false
    #if DEBUG
    @State private var debugHabitEditor = false
    #endif
    @AppStorage(AppStorageKeys.isAuthenticated) private var isAuthenticated = false
    @AppStorage(AppStorageKeys.onboardingDone) private var onboardingDone = false
    @AppStorage(AppStorageKeys.recommendedModules) private var recommendedModulesRaw = ""
    @AppStorage(AppStorageKeys.appTheme) private var appThemeRaw = "system"
    private var appTheme: AppTheme {
        let t = AppTheme(rawValue: appThemeRaw) ?? .system
        return t.isSelectable ? t : .system   // thème archivé → Système
    }
    @State private var showBriefingFromWidget = false
    @State private var showSleepCheckFromWidget = false
    @State private var showWeeklyBilan = false
    @State private var showIntake = false
    @State private var showFoodScan = false
    @State private var showTabata = false
    @AppStorage(AppStorageKeys.intakeShown) private var intakeShown = false

    private var recommendedModules: [AppCategory] {
        recommendedModulesRaw.split(separator: ",").compactMap { AppCategory(rawValue: String($0)) }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Theme.bg
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                if let container {
                    // L'app arrive en fondu en remontant tres legerement.
                    appContent(container: container)
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    // Le logo continue de grossir en s'effacant: on a
                    // l'impression d'entrer DANS l'app, pas de voir un ecran
                    // remplace par un autre.
                    SplashView()
                        .transition(.scale(scale: 1.35).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .zIndex(2)
                }

                if appLock.isLocked {
                    AppLockScreen()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            // Un peu plus lent que 0,3 s: le zoom du logo doit avoir le temps
            // de se lire, sinon on percoit une coupure et pas un mouvement.
            .animation(.easeInOut(duration: 0.55), value: container != nil)
            .animation(.easeInOut(duration: 0.25), value: appLock.isLocked)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { appLock.lockIfNeeded() }
            }
            .preferredColorScheme(appTheme.scheme)
            .tint(appTheme.accent)
            // Sans ca, la barre d'outils et le titre de fenetre sur Mac gardent
            // l'apparence du systeme pendant que le contenu suit le theme de l'app :
            // accent blanc du theme sombre sur une barre claire = glyphes invisibles.
            .syncWindowAppearance(appTheme.scheme)
            .task {
                appLock.lockIfNeeded()
                await buildContainer()
            }
            // Noms des outils, pilotes depuis Notion. En tache separee pour ne
            // jamais retarder l'ouverture, et relus a chaque retour dans l'app.
            .task { await ToolNames.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await ToolNames.refresh() } }
            }
            .alert("Problème de données", isPresented: $migrationFailed) {
                Button("Réessayer") { Task { await buildContainer() } }
                Button("Continuer (données perdues)", role: .destructive) { migrationFailed = false }
            } message: {
                Text("LifeOS n'a pas pu charger ta base de données. Tes données sont en sécurité — réessaie ou contacte le support.")
            }
            .alert("Données réinitialisées", isPresented: $storeWasReset) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Tes données n'ont pas pu être migrées après une mise à jour. Une copie de sauvegarde a été conservée sur l'appareil et l'app repart sur une base vide. Contacte le support pour restaurer la sauvegarde.")
            }
        }
    }

    // MARK: - Contenu principal

    @ViewBuilder
    private func appContent(container: ModelContainer) -> some View {
        ZStack {
            if !isAuthenticated {
                AuthView(initialMode: .login)
                    .transition(.opacity)
                    .zIndex(0)
            } else if !onboardingDone {
                OnboardingView()
                    .transition(.opacity)
                    .zIndex(1)
            } else {
                MainTabView()
                    .tint(appTheme.accent)
                    .transition(.opacity)
                    .zIndex(2)
                    .fullScreenCover(isPresented: $showIntake) { IntakeHubView() }
            }
        }
        .modelContainer(container)
        .animation(.easeInOut(duration: 0.35), value: isAuthenticated)
        .animation(.easeInOut(duration: 0.35), value: onboardingDone)
        .onChange(of: onboardingDone) { _, done in
            guard done else { return }
            // Après l'onboarding identité, propose l'intake complet (une fois).
            if !intakeShown { intakeShown = true; showIntake = true }
            // On demande les notifications ICI — une fois l'onboarding terminé, quand
            // l'utilisateur est engagé — et PAS au tout premier lancement (moins intrusif).
            Task.detached(priority: .background) {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted { await MainActor.run { ContextualNotifications.shared.reschedule() } }
            }
        }
        .onAppear {
            resetDailyValuesIfNeeded()
            EngagementTracker.shared.recordOpen()
            // Bootstrap du store profil (avant migration qui l'utilise).
            ProfileStore.shared.setContext(container.mainContext)
            // Bootstrap builder contexte — permet MemoryRetrieval scoré.
            UserContextBuilder.shared.setContext(container.mainContext)
            // Bootstrap context partagé pour les tools cross-domaines (Loop 9).
            SharedModelContextProvider.shared.setContext(container.mainContext)
            // Migration one-shot des données existantes vers ProfileField.
            ProfileMigration.runIfNeeded(context: container.mainContext)
            // Rattache les anciennes operations a un identifiant de compte stable et
            // reconstruit les soldes d'ouverture, sans changer les soldes affiches.
            LedgerService.migrateIfNeeded(container.mainContext)
            // Enregistrer les tools coach dans le ToolRegistry (Phase 1 branchée).
            CoachToolsBootstrap.registerAll()
            // Pas de demande de permission pendant l'onboarding : elle est faite
            // en contexte (pré-prompt) juste après la création des habitudes.
            guard onboardingDone else { return }
            #if DEBUG
            // Visual QA must not be dimmed by a system notification permission dialog.
            if ProcessInfo.processInfo.arguments.contains("-glassGallery") ||
                ProcessInfo.processInfo.arguments.contains("-skipPermissionPrompts") { return }
            #endif
            Task.detached(priority: .background) {
                let granted = await NotificationManager.shared.requestAuthorization()
                if granted {
                    await MainActor.run {
                        ContextualNotifications.shared.reschedule()
                        NotificationManager.shared.scheduleWeeklyBilan()
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            resetDailyValuesIfNeeded()
            MorningReminder.checkAndArm()
            Task { await HealthAutoSync.syncNow(container.mainContext) }
            // Regénère les notifs cross-pôles à partir de l'état actuel.
            SmartNotifications.refreshDaily(ctx: container.mainContext)
            // Publie le score énergie du jour dans App Group pour le widget.
            EnergyScore.publishToAppGroup(EnergyScore.today(container.mainContext))
            // Rejoue les toggles d'habitudes faits depuis le widget interactif.
            WidgetToggleReconciler.drainAndApply(ctx: container.mainContext)
            // Analytics — événement launch.
            Analytics.log("app.launch")
            // Coach proactif — piggy-back au foreground (fallback si BGTask
            // ne tourne pas encore sur ce device / permission refusée).
            Task { @MainActor in
                await CoachProactiveScheduler.runProactiveScan()
            }
            // Décroissance mémoire — cleanup 1/semaine (idempotent).
            MemoryDecayJob.runIfNeeded(context: container.mainContext)
            // Bilans quotidiens matin/soir — idempotent, re-schedule uniquement si config user changée
            CoachDailyBilan.scheduleAllIfNeeded()
            // Bilan mensuel (Loop 20) — notif le 1er du mois à 10h
            MonthlyReviewScheduler.scheduleIfNeeded()
        }
        .onChange(of: recommendedModulesRaw) { _, _ in
            ContextualNotifications.shared.reschedule()
        }
        .fullScreenCover(isPresented: Binding(get: { alarm.showAlarmScreen }, set: { if !$0 { alarm.stopRinging() } })) {
            AlarmFullScreenView()
        }
        .sheet(isPresented: $showSleepCheckFromWidget) {
            SleepCheckSheet {
                showSleepCheckFromWidget = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showBriefingFromWidget = true
                }
            }
        }
        .fullScreenCover(isPresented: $showBriefingFromWidget) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: false)
        }
        #if DEBUG
        // Crochet de verification. Le simulateur ne sait pas cliquer, donc sans ca on ne
        // peut pas prouver qu'un ecran s'ouvre sans planter. Sert a controler le
        // plantage Mac Catalyst de "Ajouter une habitude" (roue UIPickerView interdite).
        // Absent des builds Release.
        .sheet(isPresented: $debugHabitEditor) { HabitEditor() }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openHabitEditor") {
                debugHabitEditor = true
            }
        }
        #endif
        .onOpenURL { url in
            guard url.scheme == "lifeos" else { return }
            switch url.host {
            case "briefing":
                showSleepCheckFromWidget = true
            case "scan-food":
                showFoodScan = true
            case "tabata":
                showTabata = true
            default:
                break
            }
        }
        .fullScreenCover(isPresented: $showTabata) {
            TabataView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenFoodScan)) { _ in
            showFoodScan = true
        }
        .fullScreenCover(isPresented: $showFoodScan) {
            NavigationStack {
                PhotoCalorieView(autoOpenCamera: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Fermer") { showFoodScan = false }
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(get: { alarm.showSleepCheck }, set: { if !$0 { alarm.phase = .idle } })) {
            SleepCheckSheet { alarm.sleepCheckDone() }
        }
        .fullScreenCover(isPresented: Binding(get: { alarm.showBriefing }, set: { if !$0 { alarm.dismissBriefing() } })) {
            DailyBriefingView(modules: recommendedModules, speakOnAppear: true)
        }
        .sheet(isPresented: $showWeeklyBilan) {
            WeeklyBilanView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifeOSOpenWeeklyBilan)) { _ in
            showWeeklyBilan = true
        }
    }

    // MARK: - Reset journalier à minuit

    private func resetDailyValuesIfNeeded() {
        let key = "lifeos.daily.lastReset"
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard !Calendar.current.isDate(last, inSameDayAs: today) else { return }
        UserDefaults.standard.set(0,    forKey: "todayEnergyScore")
        UserDefaults.standard.set("",   forKey: "todayEnergyLabel")
        UserDefaults.standard.set(0,    forKey: "lastSleepQuality")
        UserDefaults.standard.set(0,    forKey: "lastSleepHours")
        UserDefaults.standard.set(0.0,  forKey: "lastSleepCheckDate")
        UserDefaults.standard.set(today, forKey: key)
    }

    // MARK: - Création container

    private func buildContainer() async {
        let schema = LocalStore.schema
        // Config CloudKit si l'user a opt-in ET si la capability Xcode iCloud
        // + relations SwiftData Optional sont prêtes (cf. CloudKitReadiness).
        // Si CloudKit foire au boot, on retombe automatiquement en local pur.
        let config = LocalStore.cloudKitEnabled
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
            : ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        let result = await Task.detached(priority: .userInitiated) {
            Result { try ModelContainer(for: schema, configurations: [config]) }
        }.value

        switch result {
        case .success(let mc):
            migrationFailed = false
            container = mc
            LocalStore.adopt(mc)
        case .failure:
            // Schéma incompatible (ex. colonnes ajoutées) — le store est déplacé
            // dans un backup horodaté, jamais supprimé : les données restent
            // récupérables et l'utilisateur est prévenu via storeWasReset.
            let storeURL = config.url
            let fm = FileManager.default
            let backupDir = storeURL
                .deletingLastPathComponent()
                .appendingPathComponent("LifeOSBackup-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
            try? fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            for suffix in ["", "-shm", "-wal"] {
                let src = URL(fileURLWithPath: storeURL.path + suffix)
                guard fm.fileExists(atPath: src.path) else { continue }
                let dst = backupDir.appendingPathComponent(src.lastPathComponent)
                if (try? fm.moveItem(at: src, to: dst)) == nil {
                    // Dernier recours : sans libérer le chemin, l'app ne démarre plus du tout.
                    try? fm.removeItem(at: src)
                }
            }

            if let fresh = try? ModelContainer(for: schema, configurations: [config]) {
                migrationFailed = false
                storeWasReset = true
                container = fresh
                LocalStore.adopt(fresh)
            } else {
                migrationFailed = true
                container = try? ModelContainer(
                    for: schema,
                    configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
                )
            }
        }
    }
}

// MARK: - Écran de chargement

/// Ouverture : le serpent seul, qui grandit et s'efface.
///
/// Plus de "sparkles", plus de nom ecrit, plus de roue qui tourne. Le logo
/// suffit, et une roue de chargement donne l'impression d'attendre meme quand
/// c'est instantane.
///
/// Le zoom continue pendant la disparition, ce qui donne l'impression d'entrer
/// DANS l'app plutot que de voir un ecran remplace par un autre.
struct SplashView: View {
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Le meme fond que l'app, sinon le raccord se voit au changement.
            Theme.screenBG.ignoresSafeArea()

            Image("SplashMark")
                .resizable()
                .scaledToFit()
                .frame(width: 190, height: 190)
                // Part legerement trop petit, finit legerement trop grand:
                // le mouvement ne s'arrete jamais avant le fondu.
                .scaleEffect(appeared ? 1.10 : 0.82)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.85), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

/// Fait apparaitre un element en fondu, avec un retard selon sa place.
///
/// Les ecrans se montaient d'un bloc, ce qui est brutal juste apres une
/// animation d'ouverture. Ici chaque bloc arrive un cran apres le precedent.
struct FadeIn: ViewModifier {
    let index: Int
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 8)
            .onAppear {
                withAnimation(.easeOut(duration: 0.45).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// `index` donne l'ordre d'arrivee, 0 en premier.
    func fadeIn(_ index: Int = 0) -> some View { modifier(FadeIn(index: index)) }
}
