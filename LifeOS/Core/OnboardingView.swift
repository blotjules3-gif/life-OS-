import SwiftUI

// MARK: - Objectif principal

enum OnboardingGoal: String, CaseIterable, Identifiable {
    case health, performance, money, mind, habits
    var id: String { rawValue }

    var label: String {
        switch self {
        case .health:      return "Santé & forme"
        case .performance: return "Performance"
        case .money:       return "Argent & carrière"
        case .mind:        return "Focus & bien-être"
        case .habits:      return "Meilleures habitudes"
        }
    }

    var icon: String {
        switch self {
        case .health:      return "heart.fill"
        case .performance: return "bolt.fill"
        case .money:       return "chart.line.uptrend.xyaxis"
        case .mind:        return "brain.head.profile"
        case .habits:      return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .health:      return Color(hex: 0xF1746C)
        case .performance: return Color(hex: 0xE0A23C)
        case .money:       return Color(hex: 0x4CC38A)
        case .mind:        return Color(hex: 0x9B6CF1)
        case .habits:      return Color(hex: 0x3CB2E0)
        }
    }

    var modules: [AppCategory] {
        switch self {
        case .health:      return [.fitness, .nutrition, .sleep, .looks]
        case .performance: return [.fitness, .productivity, .learning, .mind]
        case .money:       return [.finance, .invest, .career, .admin]
        case .mind:        return [.mind, .productivity, .sleep, .social]
        case .habits:      return [.productivity, .fitness, .sleep, .nutrition]
        }
    }
}

// MARK: - Conteneur onboarding

struct OnboardingView: View {
    @AppStorage("userName") private var savedName = ""
    @AppStorage("userGender") private var savedGender = ""
    @AppStorage("onboardingDone") private var onboardingDone = false

    @AppStorage("homeShortcuts") private var homeShortcuts = "tabata,calories,scan,todo,fasting,water,habits,mood"
    @AppStorage("recommendedModules") private var recommendedModulesRaw = ""
    @AppStorage("onboardingGoalsRaw") private var onboardingGoalsRaw = ""
    @AppStorage("wakeupHour") private var savedWakeupHour = 7
    @AppStorage("wakeupMinute") private var savedWakeupMinute = 0
    @AppStorage("wakeupEnabled") private var savedWakeupEnabled = false
    @AppStorage("habitModulesRaw") private var habitModulesRaw = ""

    @AppStorage("lifeProfile") private var savedLifeProfile = ""
    @AppStorage("userHasCycle") private var savedHasCycle = false
    @AppStorage("userHormonalContext") private var savedHormonalContext = ""
    @Environment(\.modelContext) private var ctx

    @State private var step = 0
    @State private var goingBack = false
    @State private var name = ""
    @State private var gender = ""
    @State private var hasCycle = false
    @State private var hormonalContext = ""
    @State private var lifeProfile: LifeProfile? = nil
    @State private var goals: Set<OnboardingGoal> = []
    @State private var interests: Set<AppCategory> = []
    @State private var wakeHour = 7
    @State private var wakeMinute = 0

    private var recommendations: [AppCategory] {
        var seen = Set<AppCategory>()
        var result: [AppCategory] = []
        let profileModules = lifeProfile?.priorityModules ?? []
        let goalModules = OnboardingGoal.allCases
            .filter { goals.contains($0) }
            .flatMap { $0.modules }
        // Intérêts explicites EN PREMIER, puis profil de vie, puis objectifs
        for cat in Array(interests) + profileModules + goalModules {
            if seen.insert(cat).inserted { result.append(cat) }
        }
        var recs = Array(result.prefix(8))
        if gender == "femme" || gender == "autre" {
            recs.removeAll { $0 == .cycle }
            recs = Array(recs.prefix(7))
            recs.insert(.cycle, at: 0)
        }
        return recs
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: goingBack ? .leading : .trailing)
                .combined(with: .opacity)
                .animation(.spring(response: 0.38, dampingFraction: 0.88).delay(0.08)),
            removal: .move(edge: goingBack ? .trailing : .leading)
                .combined(with: .opacity)
                .animation(.spring(response: 0.28, dampingFraction: 0.9))
        )
    }

    private func advance(to next: Int) {
        goingBack = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { step = next }
    }

    private func goBack() {
        goingBack = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { step -= 1 }
    }

    private func buildShortcuts(from cats: [AppCategory]) -> String {
        let mapping: [AppCategory: [ShortcutTool]] = [
            .fitness:      [.tabata, .habits],
            .nutrition:    [.calories, .fasting, .water, .scan],
            .sleep:        [.bedtime, .nap],
            .looks:        [.progressPhotos],
            .mind:         [.focus, .mood, .breathing],
            .productivity: [.todo, .focus],
            .finance:      [.budget],
            .invest:       [.portfolio],
            .learning:     [.flashcards],
        ]
        var seen = Set<ShortcutTool>()
        var tools: [ShortcutTool] = []
        for cat in cats {
            for tool in (mapping[cat] ?? []) where seen.insert(tool).inserted {
                tools.append(tool)
            }
        }
        return tools.prefix(8).map { $0.rawValue }.joined(separator: ",")
    }

    private func applyGenderDefaults(gender: String) {
        switch gender {
        case "femme":
            UserDefaults.standard.set(1800, forKey: "kcalGoal")
            UserDefaults.standard.set(110,  forKey: "proteinGoal")
            UserDefaults.standard.set(2000, forKey: "waterGoal")
        case "homme":
            UserDefaults.standard.set(2200, forKey: "kcalGoal")
            UserDefaults.standard.set(150,  forKey: "proteinGoal")
            UserDefaults.standard.set(2500, forKey: "waterGoal")
        default:
            UserDefaults.standard.set(2000, forKey: "kcalGoal")
            UserDefaults.standard.set(130,  forKey: "proteinGoal")
            UserDefaults.standard.set(2200, forKey: "waterGoal")
        }
    }

    private func createPendingHabits() {
        let modules = habitModulesRaw.split(separator: ",").map(String.init)
        HabitDefaults.insertPendingHabits(for: modules, into: ctx)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Barre de progression (steps 1–7)
                if step >= 1 && step <= 7 {
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { s in
                            Capsule()
                                .fill(step >= s ? Color.accentColor : Color.primary.opacity(0.1))
                                .frame(height: 4)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 56)
                    .padding(.bottom, 16)
                    .animation(.spring(duration: 0.35), value: step)
                }

                // Bouton retour (steps 2–7)
                if step >= 2 && step <= 7 {
                    HStack {
                        Button {
                            goBack()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(10)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
                }

                // Étape active
                ZStack {
                    switch step {
                    case 0:
                        OnboardingWelcome {
                            advance(to: 1)
                        }
                        .transition(stepTransition)
                    case 1:
                        OnboardingName(name: $name, gender: $gender) {
                            savedName = name.trimmingCharacters(in: .whitespaces)
                            savedGender = gender
                            advance(to: (gender == "femme" || gender == "autre") ? 2 : 3)
                        }
                        .transition(stepTransition)
                    case 2:
                        OnboardingHormonalContext(hasCycle: $hasCycle, hormonalContext: $hormonalContext) {
                            savedHasCycle = hasCycle
                            savedHormonalContext = hormonalContext
                            advance(to: 3)
                        }
                        .transition(stepTransition)
                    case 3:
                        OnboardingLifeProfile(selected: $lifeProfile) {
                            savedLifeProfile = lifeProfile?.rawValue ?? ""
                            if let p = lifeProfile { UserDefaults.standard.set(p.sportHour, forKey: "sportHour") }
                            advance(to: 4)
                        }
                        .transition(stepTransition)
                    case 4:
                        OnboardingGoalStep(selected: $goals) { advance(to: 5) }
                            .transition(stepTransition)
                    case 5:
                        OnboardingInterests(selected: $interests) { advance(to: 6) }
                            .transition(stepTransition)
                    case 6:
                        OnboardingModuleSetup(modules: Array(interests)) { moduleAnswers in
                            for (module, config) in moduleAnswers {
                                if let data = try? JSONSerialization.data(withJSONObject: config),
                                   let str = String(data: data, encoding: .utf8) {
                                    UserDefaults.standard.set(str, forKey: "moduleConfig_\(module)")
                                }
                            }
                            advance(to: 7)
                        }
                        .transition(stepTransition)
                    case 7:
                        OnboardingWakeTime(hour: $wakeHour, minute: $wakeMinute) {
                            savedWakeupHour = wakeHour
                            savedWakeupMinute = wakeMinute
                            savedWakeupEnabled = true
                            advance(to: 8)
                        }
                        .transition(stepTransition)
                    case 8:
                        OnboardingResults(
                            name: savedName,
                            recommendations: recommendations,
                            onDone: { finalModules in
                                recommendedModulesRaw = finalModules.map { $0.rawValue }.joined(separator: ",")
                                onboardingGoalsRaw = Array(goals).map { $0.rawValue }.joined(separator: ",")
                                if !finalModules.isEmpty { homeShortcuts = buildShortcuts(from: finalModules) }
                                applyGenderDefaults(gender: savedGender)
                                createPendingHabits()
                                NotificationManager.shared.scheduleAfter(
                                    id: "lifeos.ai.welcome",
                                    title: "LifeOS",
                                    body: "Ton assistant t'a envoyé un message",
                                    seconds: 5
                                )
                                onboardingDone = true
                            }
                        )
                        .transition(stepTransition)
                    default:
                        EmptyView()
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
        }
    }
}

// MARK: - Étape 0 : Bienvenue

struct OnboardingWelcome: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 104, height: 104)
                    Image(systemName: "sparkles")
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 12) {
                    Text("Bienvenue sur LifeOS")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Ton système personnel pour tout\norganiser et progresser chaque jour.")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }
            }

            Spacer()

            OnboardingButton(label: "Commencer", enabled: true, action: onNext)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Étape 1 : Prénom + Genre

struct OnboardingName: View {
    @Binding var name: String
    @Binding var gender: String
    let onNext: () -> Void
    @FocusState private var focused: Bool

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !gender.isEmpty
    }

    private let genderOptions: [(label: String, value: String, icon: String, color: Color)] = [
        ("Femme",  "femme",  "person.fill",       Color(hex: 0xE85D9A)),
        ("Homme",  "homme",  "person.fill",       Color(hex: 0x3CB2E0)),
        ("Autre",  "autre",  "person.fill.questionmark", Color(hex: 0x9B6CF1)),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Prénom
                VStack(spacing: 10) {
                    Text("Comment tu t'appelles ?")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Pour personnaliser ton expérience.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Ton prénom…", text: $name)
                    .font(.system(size: 20, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .focused($focused)
                    .onSubmit { if canContinue { onNext() } }
                    .submitLabel(.done)

                // Genre
                VStack(spacing: 10) {
                    Text("Tu es…")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(genderOptions, id: \.value) { opt in
                            Button {
                                withAnimation(.spring(duration: 0.2)) { gender = opt.value }
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: opt.icon)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(gender == opt.value ? .white : opt.color)
                                        .frame(width: 52, height: 52)
                                        .background(
                                            gender == opt.value ? opt.color : opt.color.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        )
                                    Text(opt.label)
                                        .font(.system(size: 13, weight: gender == opt.value ? .semibold : .regular))
                                        .foregroundStyle(gender == opt.value ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(gender == opt.value ? opt.color : Color.clear, lineWidth: 2)
                                )
                                .scaleEffect(gender == opt.value ? 1.03 : 1.0)
                                .animation(.spring(duration: 0.2), value: gender)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            Spacer()

            OnboardingButton(label: "Continuer", enabled: canContinue, action: onNext)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 28)
        .task {
            // Attendre que la transition (320ms) soit terminée avant d'ouvrir le clavier
            try? await Task.sleep(for: .milliseconds(650))
            focused = true
        }
    }
}

// MARK: - Étape 2 : Contexte hormonal (femme / autre uniquement)

struct OnboardingHormonalContext: View {
    @Binding var hasCycle: Bool
    @Binding var hormonalContext: String
    let onNext: () -> Void

    private let contextOptions: [(id: String, label: String, icon: String)] = [
        ("natural",      "Cycle naturel",          "waveform.path.ecg"),
        ("pill",         "Pilule contraceptive",   "pills.fill"),
        ("iud_hormonal", "Stérilet hormonal",      "cross.circle.fill"),
        ("pcos",         "SOPK",                   "exclamationmark.triangle.fill"),
        ("endometriosis","Endométriose",            "heart.slash.fill"),
        ("menopause",    "Ménopause / Péri",        "sun.max.fill"),
        ("no_cycle",     "Pas de cycle",            "xmark.circle.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text("Ton contexte hormonal")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Pour adapter tes recommandations nutrition, fitness et suppléments au plus près de ta réalité.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                VStack(spacing: 10) {
                    ForEach(contextOptions, id: \.id) { opt in
                        Button {
                            hormonalContext = opt.id
                            hasCycle = (opt.id != "no_cycle" && opt.id != "menopause")
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(hormonalContext == opt.id ? .white : Color(hex: 0xE85D9A))
                                    .frame(width: 38, height: 38)
                                    .background(
                                        hormonalContext == opt.id ? Color(hex: 0xE85D9A) : Color(hex: 0xE85D9A).opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                Text(opt.label)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(hormonalContext == opt.id ? .primary : .secondary)
                                Spacer()
                                if hormonalContext == opt.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color(hex: 0xE85D9A))
                                        .font(.system(size: 20))
                                        .contentTransition(.symbolEffect(.replace))
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(hormonalContext == opt.id ? Color(hex: 0xE85D9A) : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            VStack(spacing: 10) {
                OnboardingButton(label: "Continuer", enabled: !hormonalContext.isEmpty, action: onNext)
                Button("Préférer ne pas répondre") {
                    hormonalContext = "undisclosed"
                    hasCycle = false
                    onNext()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 52)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Profil de vie

enum LifeProfile: String, CaseIterable, Identifiable {
    case student, employee, entrepreneur, athlete, retired, jobseeker, custom
    var id: String { rawValue }

    var label: String {
        switch self {
        case .student:      return "Étudiant"
        case .employee:     return "Salarié"
        case .entrepreneur: return "Entrepreneur"
        case .athlete:      return "Sportif"
        case .retired:      return "Retraité"
        case .jobseeker:    return "En recherche"
        case .custom:       return "Personnalisé"
        }
    }

    var icon: String {
        switch self {
        case .student:      return "graduationcap.fill"
        case .employee:     return "briefcase.fill"
        case .entrepreneur: return "flame.fill"
        case .athlete:      return "figure.run"
        case .retired:      return "sun.max.fill"
        case .jobseeker:    return "magnifyingglass"
        case .custom:       return "slider.horizontal.3"
        }
    }

    var color: Color {
        switch self {
        case .student:      return Color(hex: 0x9B6CF1)
        case .employee:     return Color(hex: 0x3CB2E0)
        case .entrepreneur: return Color(hex: 0xE0A23C)
        case .athlete:      return Color(hex: 0xF1746C)
        case .retired:      return Color(hex: 0x4CC38A)
        case .jobseeker:    return Color(hex: 0x618EF1)
        case .custom:       return Color(hex: 0x6D6A63)
        }
    }

    // Modules prioritaires selon le profil
    var priorityModules: [AppCategory] {
        switch self {
        case .student:      return [.learning, .productivity, .sleep, .fitness, .mind]
        case .employee:     return [.productivity, .fitness, .finance, .sleep, .mind]
        case .entrepreneur: return [.productivity, .finance, .invest, .career, .fitness]
        case .athlete:      return [.fitness, .nutrition, .sleep, .mind]
        case .retired:      return [.mind, .fitness, .social, .sleep, .looks]
        case .jobseeker:    return [.career, .learning, .productivity, .mind, .finance]
        case .custom:       return []
        }
    }

    // Heure de sport recommandée (pour notifications)
    var sportHour: Int {
        switch self {
        case .student:      return 17
        case .employee:     return 18
        case .entrepreneur: return 7
        case .athlete:      return 9
        case .retired:      return 10
        case .jobseeker:    return 16
        case .custom:       return 18
        }
    }
}

// MARK: - Étape 2 : Profil de vie

struct OnboardingLifeProfile: View {
    @Binding var selected: LifeProfile?
    let onNext: () -> Void
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Text("Ton profil de vie")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                    Text("Ça aide à adapter les recommandations et les horaires à ta réalité.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(LifeProfile.allCases) { profile in
                        Button { selected = profile } label: {
                            VStack(spacing: 10) {
                                Image(systemName: profile.icon)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(selected == profile ? .white : profile.color)
                                Text(profile.label)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(selected == profile ? .white : .primary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(
                                selected == profile
                                ? profile.color
                                : profile.color.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(
                                        selected == profile ? Color.clear : profile.color.opacity(0.2),
                                        lineWidth: 1.5
                                    )
                            )
                            .scaleEffect(selected == profile ? 0.97 : 1.0)
                            .animation(.spring(response: 0.2), value: selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            OnboardingButton(label: "Continuer", enabled: selected != nil, action: onNext)
                .padding(.bottom, 52)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Étape 3 : Objectif (ancienne étape 2)

struct OnboardingGoalStep: View {
    @Binding var selected: Set<OnboardingGoal>
    let onNext: () -> Void
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Quels sont tes objectifs ?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Sélectionne tout ce qui te correspond.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)

            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(OnboardingGoal.allCases) { g in
                    GoalCard(goal: g, isSelected: selected.contains(g)) {
                        withAnimation(.spring(duration: 0.2)) {
                            if selected.contains(g) { selected.remove(g) } else { selected.insert(g) }
                        }
                        Haptics.tap()
                    }
                }
            }
            .padding(.horizontal, 22)

            Spacer()

            OnboardingButton(
                label: selected.isEmpty ? "Continuer" : "Continuer (\(selected.count))",
                enabled: !selected.isEmpty,
                action: onNext
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
            .animation(.spring(duration: 0.2), value: selected.count)
        }
    }
}

struct GoalCard: View {
    let goal: OnboardingGoal
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : goal.color)
                    .frame(width: 54, height: 54)
                    .background(
                        isSelected ? goal.color : goal.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                Text(goal.label)
                    .font(.system(size: 13, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Étape 3 : Centres d'intérêt

struct OnboardingInterests: View {
    @Binding var selected: Set<AppCategory>
    let onNext: () -> Void
    private let cols = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Qu'est-ce qui t'intéresse ?")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("Sélectionne autant que tu veux.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(AppCategory.allCases) { cat in
                        InterestChip(category: cat, isSelected: selected.contains(cat)) {
                            if selected.contains(cat) {
                                selected.remove(cat)
                            } else {
                                selected.insert(cat)
                            }
                            Haptics.tap()
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 12)
            }

            OnboardingButton(
                label: selected.isEmpty ? "Passer" : "Continuer (\(selected.count))",
                enabled: true,
                action: onNext
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
            .animation(.spring(duration: 0.2), value: selected.count)
        }
    }
}

struct InterestChip: View {
    let category: AppCategory
    let isSelected: Bool
    let onTap: () -> Void

    private var shortLabel: String {
        category.title.components(separatedBy: " & ").first?
            .components(separatedBy: " ").first ?? category.title
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : category.tint)
                    .frame(width: 42, height: 42)
                    .background(
                        isSelected ? category.tint : category.tint.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                Text(shortLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? category.tint : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isSelected ? 1.03 : 1.0)
            .animation(.spring(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Étape 4 : Heure de réveil

struct OnboardingWakeTime: View {
    @Binding var hour: Int
    @Binding var minute: Int
    let onNext: () -> Void

    private var timeDate: Binding<Date> {
        Binding(
            get: {
                var c = Calendar.current.dateComponents([.year, .month, .day], from: .now)
                c.hour = hour; c.minute = minute
                return Calendar.current.date(from: c) ?? .now
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                hour = c.hour ?? 7; minute = c.minute ?? 0
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.1))
                            .frame(width: 80, height: 80)
                        Image(systemName: "sunrise.fill")
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    VStack(spacing: 10) {
                        Text("À quelle heure tu te lèves ?")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("On activera ton réveil malin à cette heure.\nTu pourras le changer à tout moment.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                }

                DatePicker("", selection: timeDate, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .environment(\.locale, Locale(identifier: "fr_FR"))
            }

            Spacer()

            VStack(spacing: 12) {
                OnboardingButton(label: "Activer mon réveil à \(String(format: "%02d:%02d", hour, minute))", enabled: true, action: onNext)
                Button("Passer cette étape") {
                    onNext()
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 52)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Étape 5 : Modules recommandés

struct OnboardingResults: View {
    let name: String
    let recommendations: [AppCategory]
    let onDone: ([AppCategory]) -> Void

    @State private var selected: Set<AppCategory> = []

    private var preferencesSummary: [(module: AppCategory, bullets: [String])] {
        recommendations.compactMap { cat -> (module: AppCategory, bullets: [String])? in
            guard let configStr = UserDefaults.standard.string(forKey: "moduleConfig_\(cat.rawValue)"),
                  let data = configStr.data(using: .utf8),
                  let config = try? JSONDecoder().decode([String: String].self, from: data),
                  !config.isEmpty else { return nil }
            let labelMap: [String: [String: [String: String]]] = [
                "fitness": ["location": ["gym":"En salle","home":"A la maison","outdoor":"Dehors","mixed":"Mixte"],
                            "frequency": ["1_2":"1-2x/sem","3":"3x/sem","4p":"4x+/sem"],
                            "goal": ["loss":"Perte de poids","muscle":"Muscle","cardio":"Cardio","flex":"Souplesse"]],
                "nutrition": ["diet": ["omni":"Omnivore","vege":"Vegetarien","vegan":"Vegan","gf":"Sans gluten"],
                              "goal": ["loss":"Perdre du poids","mass":"Prise de masse","balance":"Equilibrer","energy":"Energie"]],
                "sleep": ["bedtime": ["early":"Avant 22h","normal":"22h-23h","late":"23h-0h","verylate":"Apres minuit"]],
                "mind": ["stress": ["low":"Faible","medium":"Modere","high":"Eleve","vhigh":"Tres eleve"]],
                "productivity": ["peak": ["morning":"Le matin","afternoon":"Apres-midi","evening":"Le soir"]],
                "invest": ["level": ["beginner":"Debutant","intermediate":"Intermediaire","expert":"Experimente"],
                           "risk": ["low":"Faible","medium":"Modere","high":"Eleve"]],
            ]
            let bullets: [String] = config.compactMap { (key, value) in
                let values = value.split(separator: ",").map(String.init)
                let moduleMap = labelMap[cat.rawValue]?[key] ?? [:]
                let labels = values.compactMap { moduleMap[$0] ?? $0 }
                return labels.isEmpty ? nil : labels.joined(separator: ", ")
            }
            guard !bullets.isEmpty else { return nil }
            return (module: cat, bullets: bullets)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    VStack(spacing: 10) {
                        Text(name.isEmpty ? "Parfait !" : "Parfait, \(name) !")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Voici tes modules pour démarrer.\nCoche ou décoche selon tes envies.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 28)

                    if !preferencesSummary.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TES PREFERENCES")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .kerning(1.2)
                                .padding(.horizontal, 4)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(preferencesSummary, id: \.module) { item in
                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(spacing: 6) {
                                                Image(systemName: item.module.icon)
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(item.module.tint)
                                                Text(item.module.title)
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(.primary)
                                            }
                                            ForEach(item.bullets, id: \.self) { b in
                                                HStack(spacing: 4) {
                                                    Circle()
                                                        .fill(item.module.tint)
                                                        .frame(width: 4, height: 4)
                                                    Text(b)
                                                        .font(.system(size: 11))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(
                                            item.module.tint.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .stroke(item.module.tint.opacity(0.2), lineWidth: 1)
                                        )
                                        .frame(minWidth: 130)
                                    }
                                }
                                .padding(.horizontal, 22)
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.horizontal, 22)
                    }

                    VStack(spacing: 10) {
                        ForEach(recommendations) { cat in
                            let isOn = selected.contains(cat)
                            Button {
                                withAnimation(.spring(duration: 0.2)) {
                                    if isOn { selected.remove(cat) } else { selected.insert(cat) }
                                }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 38, height: 38)
                                        .background(isOn ? cat.tint : Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(isOn ? .primary : .secondary)
                                        Text(cat.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.4))
                                        .font(.system(size: 22))
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .opacity(isOn ? 1 : 0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 22)

                    Spacer(minLength: 16)
                }
            }

            OnboardingButton(
                label: selected.isEmpty ? "Sélectionne au moins un module" : "Commencer LifeOS",
                enabled: !selected.isEmpty,
                action: { onDone(recommendations.filter { selected.contains($0) }) }
            )
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
        .onAppear {
            selected = Set(recommendations)
        }
    }
}

// MARK: - Module setup data

struct ModuleQuestion: Identifiable {
    let id: String
    let question: String
    let options: [ModuleOption]
    let multiSelect: Bool

    init(_ id: String, _ question: String, _ options: [ModuleOption], multiSelect: Bool = false) {
        self.id = id; self.question = question; self.options = options; self.multiSelect = multiSelect
    }
}

struct ModuleOption: Identifiable {
    let id: String
    let label: String
    let icon: String

    init(_ id: String, _ label: String, _ icon: String = "") {
        self.id = id; self.label = label; self.icon = icon
    }
}

let moduleSetupQuestions: [AppCategory: [ModuleQuestion]] = [
    .fitness: [
        ModuleQuestion("location", "Ou tu t'entraines ?", [
            ModuleOption("gym",     "En salle",    "building.2"),
            ModuleOption("home",    "A la maison", "house"),
            ModuleOption("outdoor", "Dehors",      "leaf"),
            ModuleOption("mixed",   "Mixte",       "shuffle"),
        ]),
        ModuleQuestion("frequency", "Frequence par semaine ?", [
            ModuleOption("1_2", "1 – 2 fois", "1.circle"),
            ModuleOption("3",   "3 fois",     "3.circle"),
            ModuleOption("4p",  "4 fois +",   "bolt"),
        ]),
        ModuleQuestion("goal", "Ton objectif sport ?", [
            ModuleOption("loss",   "Perte de poids",  "scalemass"),
            ModuleOption("muscle", "Prise de muscle", "dumbbell"),
            ModuleOption("cardio", "Cardio",           "heart.circle"),
            ModuleOption("flex",   "Souplesse",        "figure.mind.and.body"),
        ]),
    ],
    .nutrition: [
        ModuleQuestion("diet", "Regime alimentaire ?", [
            ModuleOption("omni",  "Omnivore",   "fork.knife"),
            ModuleOption("vege",  "Vegetarien", "leaf"),
            ModuleOption("vegan", "Vegan",      "sparkles"),
            ModuleOption("gf",    "Sans gluten","exclamationmark.circle"),
        ]),
        ModuleQuestion("goal", "Objectif nutrition ?", [
            ModuleOption("loss",    "Perdre du poids",    "arrow.down.circle"),
            ModuleOption("mass",    "Prendre de la masse","arrow.up.circle"),
            ModuleOption("balance", "Equilibrer",          "equal.circle"),
            ModuleOption("energy",  "Plus d'energie",     "bolt"),
        ]),
    ],
    .sleep: [
        ModuleQuestion("bedtime", "Tu te couches habituellement a ?", [
            ModuleOption("early",    "Avant 22h",   "moon.stars"),
            ModuleOption("normal",   "22h – 23h",   "moon"),
            ModuleOption("late",     "23h – 0h",    "cloud.moon"),
            ModuleOption("verylate", "Apres minuit","moon.zzz"),
        ]),
        ModuleQuestion("issue", "Problemes de sommeil ?", [
            ModuleOption("falling", "Endormissement",  "zzz"),
            ModuleOption("waking",  "Reveils nocturnes","alarm"),
            ModuleOption("none",    "Aucun",            "checkmark.circle"),
        ], multiSelect: true),
    ],
    .mind: [
        ModuleQuestion("stress", "Niveau de stress actuel ?", [
            ModuleOption("low",    "Faible",     "leaf"),
            ModuleOption("medium", "Modere",     "minus.circle"),
            ModuleOption("high",   "Eleve",      "exclamationmark.triangle"),
            ModuleOption("vhigh",  "Tres eleve", "flame"),
        ]),
        ModuleQuestion("practice", "Tu pratiques deja ?", [
            ModuleOption("meditation", "Meditation", "brain.head.profile"),
            ModuleOption("journaling", "Journal",    "book"),
            ModuleOption("sport",      "Sport",      "figure.run"),
            ModuleOption("nothing",    "Rien encore","circle"),
        ], multiSelect: true),
    ],
    .productivity: [
        ModuleQuestion("peak", "Quand es-tu le plus productif ?", [
            ModuleOption("morning",   "Le matin",    "sunrise"),
            ModuleOption("afternoon", "L'apres-midi","sun.max"),
            ModuleOption("evening",   "Le soir",     "sunset"),
        ]),
        ModuleQuestion("method", "Methode de travail ?", [
            ModuleOption("pomodoro", "Pomodoro",  "timer"),
            ModuleOption("tasks",    "To-do list","checklist"),
            ModuleOption("block",    "Timeblock", "calendar"),
            ModuleOption("free",     "Flux libre","wand.and.stars"),
        ]),
    ],
    .finance: [
        ModuleQuestion("goal", "Objectif principal ?", [
            ModuleOption("save",   "Epargner plus",     "banknote"),
            ModuleOption("debt",   "Rembourser dettes", "arrow.down.circle"),
            ModuleOption("budget", "Suivre le budget",  "chart.pie"),
            ModuleOption("invest", "Investir",           "chart.line.uptrend.xyaxis"),
        ]),
    ],
    .invest: [
        ModuleQuestion("level", "Ton niveau en investissement ?", [
            ModuleOption("beginner",     "Debutant",     "star"),
            ModuleOption("intermediate", "Intermediaire","star.leadinghalf.filled"),
            ModuleOption("expert",       "Experimente",  "star.fill"),
        ]),
        ModuleQuestion("risk", "Appetit au risque ?", [
            ModuleOption("low",    "Faible", "shield"),
            ModuleOption("medium", "Modere", "shield.lefthalf.filled"),
            ModuleOption("high",   "Eleve",  "bolt.shield"),
        ]),
    ],
    .career: [
        ModuleQuestion("goal", "Ton objectif carriere ?", [
            ModuleOption("promotion", "Promotion",           "arrow.up.circle"),
            ModuleOption("change",    "Changer de domaine",  "arrow.right.circle"),
            ModuleOption("startup",   "Creer mon activite",  "flame"),
            ModuleOption("job",       "Trouver un emploi",   "magnifyingglass"),
        ]),
    ],
    .learning: [
        ModuleQuestion("domain", "Domaine principal ?", [
            ModuleOption("tech",      "Tech / Code","laptopcomputer"),
            ModuleOption("business",  "Business",   "briefcase"),
            ModuleOption("languages", "Langues",    "globe"),
            ModuleOption("other",     "Autre",      "ellipsis.circle"),
        ]),
        ModuleQuestion("time", "Temps dispo par jour ?", [
            ModuleOption("15",  "15 min","timer"),
            ModuleOption("30",  "30 min","timer"),
            ModuleOption("60",  "1h",    "clock"),
            ModuleOption("60p", "1h+",   "infinity"),
        ]),
    ],
    .looks: [
        ModuleQuestion("goal", "Ton objectif ?", [
            ModuleOption("loss",     "Perte de poids",    "arrow.down.circle"),
            ModuleOption("mass",     "Prise de masse",    "arrow.up.circle"),
            ModuleOption("tone",     "Tonifier",           "bolt"),
            ModuleOption("wellness", "Bien-etre general",  "heart"),
        ]),
        ModuleQuestion("skincare", "Suivi skincare ?", [
            ModuleOption("yes",  "Oui, routine complete", "checkmark.circle"),
            ModuleOption("basic","Basique seulement",     "minus.circle"),
            ModuleOption("no",   "Non",                   "xmark.circle"),
        ]),
    ],
    .social: [
        ModuleQuestion("type", "Tu es plutot ?", [
            ModuleOption("intro", "Introverti",    "person"),
            ModuleOption("extro", "Extraverti",    "person.3"),
            ModuleOption("mixed", "Entre les deux","person.2"),
        ]),
        ModuleQuestion("goal", "Objectif social ?", [
            ModuleOption("meet",   "Rencontrer du monde",     "person.badge.plus"),
            ModuleOption("deepen", "Ameliorer mes relations", "heart.circle"),
            ModuleOption("both",   "Les deux",                "sparkles"),
        ]),
    ],
    .home: [
        ModuleQuestion("type", "Type de logement ?", [
            ModuleOption("apartment", "Appartement","building.2"),
            ModuleOption("house",     "Maison",     "house"),
            ModuleOption("studio",    "Studio",     "squareshape"),
            ModuleOption("shared",    "Colocation", "person.2"),
        ]),
    ],
    .mobility: [
        ModuleQuestion("vehicle", "Transport principal ?", [
            ModuleOption("car",     "Voiture",    "car"),
            ModuleOption("moto",    "Moto",       "figure.outdoor.cycle"),
            ModuleOption("bike",    "Velo",       "bicycle"),
            ModuleOption("transit", "Transports", "bus"),
        ]),
    ],
    .admin: [
        ModuleQuestion("priority", "Ta priorite admin ?", [
            ModuleOption("docs",      "Documents",  "doc.text"),
            ModuleOption("taxes",     "Impots",     "eurosign.circle"),
            ModuleOption("insurance", "Assurances", "shield"),
            ModuleOption("all",       "Tout gerer", "tray.full"),
        ]),
    ],
    .travel: [
        ModuleQuestion("style", "Tu voyages plutot ?", [
            ModuleOption("solo",    "Solo",      "person"),
            ModuleOption("couple",  "En couple", "person.2"),
            ModuleOption("family",  "En famille","person.3"),
            ModuleOption("friends", "Entre amis","person.3.fill"),
        ]),
    ],
    .cycle: [
        ModuleQuestion("goal", "Ton objectif ?", [
            ModuleOption("tracking",   "Suivi cycle",      "calendar"),
            ModuleOption("fertility",  "Fertilite",         "heart.circle"),
            ModuleOption("pain",       "Gestion douleurs",  "cross.circle"),
            ModuleOption("understand", "Mieux comprendre",  "book"),
        ]),
    ],
]

// MARK: - Etape 5 : Setup par module

struct OnboardingModuleSetup: View {
    let modules: [AppCategory]
    let skipHabitStep: Bool
    let onNext: ([String: [String: String]]) -> Void

    init(modules: [AppCategory], skipHabitStep: Bool = false, onNext: @escaping ([String: [String: String]]) -> Void) {
        self.modules = modules
        self.skipHabitStep = skipHabitStep
        self.onNext = onNext
    }

    @State private var currentIndex = 0
    @State private var answers: [String: [String: String]] = [:]
    @State private var showHabitPicker = false
    @State private var selectedHabitModules: Set<String> = []

    private var modulesWithQuestions: [AppCategory] {
        modules.filter { moduleSetupQuestions[$0]?.isEmpty == false }
    }

    private var currentModule: AppCategory? {
        guard currentIndex < modulesWithQuestions.count else { return nil }
        return modulesWithQuestions[currentIndex]
    }

    private var currentQuestions: [ModuleQuestion] {
        guard let m = currentModule else { return [] }
        return moduleSetupQuestions[m] ?? []
    }

    private var canAdvance: Bool {
        guard let m = currentModule else { return true }
        let dict = answers[m.rawValue] ?? [:]
        return currentQuestions.filter { !$0.multiSelect }.allSatisfy { dict[$0.id] != nil }
    }

    var body: some View {
        if modulesWithQuestions.isEmpty {
            Color.clear.onAppear { onNext([:]) }
        } else if showHabitPicker {
            habitPickerView
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        } else {
            VStack(spacing: 0) {
                subProgress
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)

                if let m = currentModule {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            moduleHeader(m)
                            ForEach(currentQuestions) { q in
                                questionBlock(q, module: m)
                            }
                            Color.clear.frame(height: 8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }

                OnboardingButton(
                    label: currentIndex < modulesWithQuestions.count - 1 ? "Module suivant" : "Configurer mes habitudes",
                    enabled: canAdvance
                ) {
                    advance()
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
                .animation(.spring(duration: 0.2), value: canAdvance)
            }
        }
    }

    private var habitPickerView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Tes habitudes a creer")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text("On les prepare pour toi, desactivees.\nTu les actives quand tu veux.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(modulesWithQuestions) { m in
                        let on = selectedHabitModules.contains(m.rawValue)
                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                if on { selectedHabitModules.remove(m.rawValue) }
                                else { selectedHabitModules.insert(m.rawValue) }
                            }
                            Haptics.tap()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: m.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(
                                        on ? m.tint : Color.primary.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(on ? .primary : .secondary)
                                    Text(m.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(on ? m.tint : Color.secondary.opacity(0.4))
                                    .font(.system(size: 22))
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .opacity(on ? 1 : 0.6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 16)
            }

            OnboardingButton(label: "Demarrer LifeOS", enabled: true) {
                UserDefaults.standard.set(
                    selectedHabitModules.joined(separator: ","),
                    forKey: "habitModulesRaw"
                )
                onNext(answers)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
        .onAppear {
            if selectedHabitModules.isEmpty {
                selectedHabitModules = Set(modulesWithQuestions.map { $0.rawValue })
            }
        }
    }

    private var subProgress: some View {
        HStack(spacing: 6) {
            ForEach(modulesWithQuestions.indices, id: \.self) { i in
                Capsule()
                    .fill(i <= currentIndex ? modulesWithQuestions[i].tint : Color.primary.opacity(0.1))
                    .frame(height: 3)
            }
        }
        .animation(.spring(duration: 0.3), value: currentIndex)
    }

    private func moduleHeader(_ m: AppCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(m.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Module \(currentIndex + 1) sur \(modulesWithQuestions.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func questionBlock(_ q: ModuleQuestion, module: AppCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(q.question)
                .font(.system(size: 15, weight: .semibold))

            let raw = (answers[module.rawValue] ?? [:])[q.id] ?? ""
            let selected = Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(q.options) { opt in
                    let on = selected.contains(opt.id)
                    Button {
                        pick(opt, question: q, module: module)
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 8) {
                            if !opt.icon.isEmpty {
                                Image(systemName: opt.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? .white : module.tint)
                            }
                            Text(opt.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(on ? .white : .primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            on ? module.tint : module.tint.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(on ? Color.clear : module.tint.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(on ? 0.97 : 1.0)
                        .animation(.spring(duration: 0.18), value: on)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ opt: ModuleOption, question q: ModuleQuestion, module: AppCategory) {
        var dict = answers[module.rawValue] ?? [:]
        if q.multiSelect {
            var set = Set((dict[q.id] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty })
            if set.contains(opt.id) {
                set.remove(opt.id)
            } else if opt.id == "nothing" {
                set = ["nothing"]
            } else {
                set.remove("nothing")
                set.insert(opt.id)
            }
            dict[q.id] = set.joined(separator: ",")
        } else {
            dict[q.id] = opt.id
        }
        answers[module.rawValue] = dict
    }

    private func advance() {
        if currentIndex < modulesWithQuestions.count - 1 {
            withAnimation(.spring(duration: 0.35)) { currentIndex += 1 }
        } else if !skipHabitStep {
            withAnimation(.spring(duration: 0.35)) { showHabitPicker = true }
        } else {
            onNext(answers)
        }
    }
}

// MARK: - Bouton CTA commun

struct OnboardingButton: View {
    let label: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    enabled ? Color.accentColor : Color.primary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
