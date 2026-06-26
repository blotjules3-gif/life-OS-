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

    @State private var step = 0
    @State private var name = ""
    @State private var gender = ""
    @State private var goals: Set<OnboardingGoal> = []
    @State private var interests: Set<AppCategory> = []
    @State private var wakeHour = 7
    @State private var wakeMinute = 0

    private var recommendations: [AppCategory] {
        var seen = Set<AppCategory>()
        var result: [AppCategory] = []
        let goalModules = OnboardingGoal.allCases
            .filter { goals.contains($0) }
            .flatMap { $0.modules }
        // Intérêts explicites EN PREMIER, puis modules dérivés des objectifs
        for cat in Array(interests) + goalModules {
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

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Barre de progression (steps 1–4)
                if step >= 1 && step <= 4 {
                    HStack(spacing: 6) {
                        ForEach(1...4, id: \.self) { s in
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

                // Bouton retour (steps 2–4)
                if step >= 2 && step <= 4 {
                    HStack {
                        Button {
                            withAnimation(.spring(duration: 0.35)) { step -= 1 }
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
                Group {
                    switch step {
                    case 0:
                        OnboardingWelcome {
                            withAnimation(.spring(duration: 0.4)) { step = 1 }
                        }
                    case 1:
                        OnboardingName(name: $name, gender: $gender) {
                            savedName = name.trimmingCharacters(in: .whitespaces)
                            savedGender = gender
                            withAnimation(.spring(duration: 0.4)) { step = 2 }
                        }
                    case 2:
                        OnboardingGoalStep(selected: $goals) {
                            withAnimation(.spring(duration: 0.4)) { step = 3 }
                        }
                    case 3:
                        OnboardingInterests(selected: $interests) {
                            withAnimation(.spring(duration: 0.4)) { step = 4 }
                        }
                    case 4:
                        OnboardingWakeTime(hour: $wakeHour, minute: $wakeMinute) {
                            savedWakeupHour = wakeHour
                            savedWakeupMinute = wakeMinute
                            savedWakeupEnabled = true
                            withAnimation(.spring(duration: 0.4)) { step = 5 }
                        }
                    case 5:
                        OnboardingResults(
                            name: savedName,
                            recommendations: recommendations,
                            onDone: {
                                recommendedModulesRaw = recommendations.map { $0.rawValue }.joined(separator: ",")
                                onboardingGoalsRaw = Array(goals).map { $0.rawValue }.joined(separator: ",")
                                if !recommendations.isEmpty {
                                    homeShortcuts = buildShortcuts(from: recommendations)
                                }
                                onboardingDone = true
                            }
                        )
                    default:
                        EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .id(step)
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
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { focused = true }
        }
    }
}

// MARK: - Étape 2 : Objectif

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
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Spacer(minLength: 16)

                    VStack(spacing: 10) {
                        Text(name.isEmpty ? "Parfait !" : "Parfait, \(name) !")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text("Voici tes modules pour démarrer.\nTu pourras tout explorer ensuite dans Catégories.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 28)

                    VStack(spacing: 10) {
                        ForEach(recommendations) { cat in
                            HStack(spacing: 14) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(cat.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.title)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(cat.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.system(size: 18))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 22)

                    Spacer(minLength: 16)
                }
            }

            OnboardingButton(label: "Commencer LifeOS", enabled: true, action: onDone)
                .padding(.horizontal, 28)
                .padding(.bottom, 52)
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
