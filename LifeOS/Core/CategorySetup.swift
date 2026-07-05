import SwiftUI

// MARK: - État de configuration des catégories (questionnaire « façon Typeform »)
// Quand on ouvre une catégorie pas encore configurée, on présente un formulaire
// étape par étape (Suivant → Suivant) qui pré-remplit tous ses outils.

enum CategorySetup {
    /// Catégories qui possèdent un flux de configuration (s'agrandit à chaque pass).
    static let flows: [AppCategory] = [.nutrition, .fitness, .sleep, .finance,
                                       .productivity, .mind, .looks, .cycle, .mobility]

    static func hasFlow(_ c: AppCategory) -> Bool { flows.contains(c) }
    static func isDone(_ c: AppCategory) -> Bool { UserDefaults.standard.bool(forKey: "setup.done.\(c.rawValue)") }
    static func markDone(_ c: AppCategory) { UserDefaults.standard.set(true, forKey: "setup.done.\(c.rawValue)") }
    static func reset(_ c: AppCategory) { UserDefaults.standard.set(false, forKey: "setup.done.\(c.rawValue)") }

    static func wasPrompted(_ c: AppCategory) -> Bool { UserDefaults.standard.bool(forKey: "setup.prompted.\(c.rawValue)") }
    static func markPrompted(_ c: AppCategory) { UserDefaults.standard.set(true, forKey: "setup.prompted.\(c.rawValue)") }
    /// Auto-présenter le formulaire une seule fois à la première ouverture.
    static func shouldAutoPrompt(_ c: AppCategory) -> Bool { hasFlow(c) && !isDone(c) && !wasPrompted(c) }

    static var doneCount: Int { flows.filter(isDone).count }
    static var fraction: Double { flows.isEmpty ? 0 : Double(doneCount) / Double(flows.count) }
    static var percent: Int { Int((fraction * 100).rounded()) }
}

// MARK: - Une page du formulaire

struct SetupPage {
    let content: AnyView
    var canAdvance: () -> Bool = { true }
    init<V: View>(canAdvance: @escaping () -> Bool = { true }, @ViewBuilder _ content: () -> V) {
        self.content = AnyView(content())
        self.canAdvance = canAdvance
    }
}

// MARK: - Coquille générique du formulaire (chrome : progression + Suivant/Précédent)

struct SetupFlow: View {
    let title: String
    let accent: Color
    let pages: [SetupPage]
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var idx = 0

    private var isLast: Bool { idx >= pages.count - 1 }
    // Sûr même si `pages` est vide (sinon pages[idx] crashe → index out of range).
    private var canAdvance: Bool { pages.indices.contains(idx) ? pages[idx].canAdvance() : true }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                TabView(selection: $idx) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                        ScrollView { page.content.padding(.horizontal, 4).padding(.top, 8) }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: idx)
                footer
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                if idx > 0 {
                    Button { withAnimation { idx -= 1 } } label: {
                        Image(systemName: "chevron.left").font(.headline).foregroundStyle(Theme.textSecondary)
                    }
                } else { Color.clear.frame(width: 22, height: 22) }
                Spacer()
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Button("Plus tard") { dismiss() }
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            // barre de progression segmentée
            HStack(spacing: 5) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(i <= idx ? AnyShapeStyle(accent) : AnyShapeStyle(Theme.bg2))
                        .frame(height: 5)
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 6)
    }

    private var footer: some View {
        Button {
            if isLast { onComplete(); dismiss() }
            else { withAnimation { idx += 1 } }
            Haptics.soft()
        } label: {
            Text(isLast ? "Terminer" : "Suivant")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background((canAdvance ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.gray.opacity(0.3))),
                           in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .disabled(!canAdvance)
        .padding(.horizontal, 18).padding(.bottom, 14).padding(.top, 6)
        // Un setup sans page ne sert à rien → on le termine directement (évite un écran vide).
        .onAppear { if pages.isEmpty { onComplete(); dismiss() } }
    }
}

// MARK: - Briques d'interface réutilisables

struct SetupHeader: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var accent: Color = .accentColor
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(title).font(.title.bold()).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle).font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14).padding(.bottom, 6)
    }
}

/// Choix unique — grandes cartes empilées.
struct SetupChoice: View {
    let options: [String]
    @Binding var selection: String
    var accent: Color = .accentColor
    var icons: [String] = []
    var body: some View {
        VStack(spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.element) { i, opt in
                Button { selection = opt; Haptics.soft() } label: {
                    HStack(spacing: 12) {
                        if icons.indices.contains(i) {
                            Image(systemName: icons[i]).foregroundStyle(selection == opt ? accent : Theme.textSecondary).frame(width: 24)
                        }
                        Text(opt).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: selection == opt ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection == opt ? AnyShapeStyle(accent) : AnyShapeStyle(Color.secondary.opacity(0.4)))
                    }
                    .padding(16)
                    .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(selection == opt ? accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Choix multiple — puces (chips) sélectionnables.
struct SetupMultiChoice: View {
    let options: [String]
    @Binding var selection: Set<String>
    var accent: Color = .accentColor
    private let cols = [GridItem(.adaptive(minimum: 104), spacing: 10)]
    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            ForEach(options, id: \.self) { opt in
                let on = selection.contains(opt)
                Button {
                    if on { selection.remove(opt) } else { selection.insert(opt) }
                    Haptics.soft()
                } label: {
                    Text(opt).font(.subheadline.weight(.medium))
                        .foregroundStyle(on ? .white : Theme.textPrimary)
                        .frame(maxWidth: .infinity).padding(.vertical, 11).padding(.horizontal, 6)
                        .background(on ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Theme.card),
                                   in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(on ? .clear : Theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
    }
}

/// Saisie numérique avec gros affichage + stepper.
struct SetupNumber: View {
    @Binding var value: Int
    let unit: String
    let range: ClosedRange<Int>
    var step: Int = 1
    var accent: Color = .accentColor
    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(value)").font(.system(size: 56, weight: .black, design: .rounded))
                    .foregroundStyle(accent).contentTransition(.numericText())
                Text(unit).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 16) {
                stepBtn("minus") { value = max(range.lowerBound, value - step) }
                stepBtn("plus")  { value = min(range.upperBound, value + step) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 14)
    }
    private func stepBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.soft() } label: {
            Image(systemName: icon).font(.title2.weight(.bold)).foregroundStyle(.white)
                .frame(width: 56, height: 56).background(accent.gradient, in: Circle())
        }.buttonStyle(.plain)
    }
}

// MARK: - Vue de configuration centrale pour une catégorie

struct CategoryFlowView: View {
    let category: AppCategory
    var body: some View {
        switch category {
        case .nutrition:    NutritionSetupView()
        case .fitness:      FitnessSetupView()
        case .sleep:        SleepSetupView()
        case .finance:      FinanceSetupView()
        case .productivity: ProductivitySetupView()
        case .mind:         MentalSetupView()
        case .looks:        LooksSetupView()
        case .cycle:        CycleSetupView()
        case .mobility:     MobilitySetupView()
        default:            EmptyView()
        }
    }
}

// MARK: - Carte de progression du profil (Profil / Accueil)

struct ProfileCompletionCard: View {
    @State private var refresh = false   // force le recalcul à l'apparition
    @State private var launch: AppCategory?
    private var pct: Int { CategorySetup.percent }
    private var remaining: [AppCategory] { CategorySetup.flows.filter { !CategorySetup.isDone($0) } }

    var body: some View {
        Group {
            // Disparaît une fois le profil 100% configuré — plus rien à remplir.
            if CategorySetup.fraction >= 1.0 { EmptyView() } else { card }
        }
        .id(refresh)
        .onAppear { refresh.toggle() }
        .fullScreenCover(item: $launch) { c in CategoryFlowView(category: c) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Theme.bg2, lineWidth: 7).frame(width: 54, height: 54)
                    Circle().trim(from: 0, to: CGFloat(max(0.02, CategorySetup.fraction)))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90)).frame(width: 54, height: 54)
                    Text("\(pct)%").font(.caption.bold().monospacedDigit()).foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Profil optimisé à \(pct)%")
                        .font(.system(size: 16, weight: .black)).textCase(.uppercase).kerning(-0.2)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Réponds à quelques questions pour des recommandations sur-mesure.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(remaining) { c in
                        Button { launch = c; Haptics.soft() } label: {
                            Label("Configurer \(c.title)", systemImage: c.icon)
                                .font(.system(size: 12, weight: .black)).textCase(.uppercase).kerning(0.3)
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .background(Color.accentColor, in: Capsule())
                        }.buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

// MARK: - Intake d'onboarding : configure tous les pôles, reprenable & idempotent

struct IntakeHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launch: AppCategory?
    @State private var refresh = false

    /// Les 16 pôles dans l'ordre, ceux qui ont un flux d'abord.
    private var poles: [AppCategory] {
        AppCategory.allCases.sorted { a, b in
            CategorySetup.hasFlow(a) && !CategorySetup.hasFlow(b)
        }
    }
    private var doneN: Int { CategorySetup.doneCount }
    private var totalN: Int { CategorySetup.flows.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 16) {
                        headerCard
                        VStack(spacing: 8) {
                            ForEach(poles) { c in row(c) }
                        }
                    }
                    .padding(16).padding(.bottom, 30)
                }
            }
            .navigationTitle("Configurer ton profil").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Terminer") { dismiss() } } }
            .fullScreenCover(item: $launch) { c in CategoryFlowView(category: c) }
            .id(refresh)
            .onAppear { refresh.toggle() }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.bg2, lineWidth: 9).frame(width: 84, height: 84)
                Circle().trim(from: 0, to: CGFloat(max(0.02, CategorySetup.fraction)))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90)).frame(width: 84, height: 84)
                Text("\(CategorySetup.percent)%").font(.title3.bold().monospacedDigit())
            }
            Text("\(doneN) / \(totalN) pôles configurés")
                .font(.system(size: 17, weight: .black)).textCase(.uppercase).kerning(-0.2)
            Text("Réponds aux questions pour que chaque outil s'ouvre déjà rempli. Tu peux passer une section et y revenir.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(20)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    @ViewBuilder private func row(_ c: AppCategory) -> some View {
        let has = CategorySetup.hasFlow(c)
        let done = CategorySetup.isDone(c)
        Button { if has { launch = c; Haptics.soft() } } label: {
            HStack(spacing: 14) {
                Image(systemName: c.icon).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background((has ? c.tint : Color.gray).gradient, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text(has ? (done ? "Configuré" : "À configurer") : "Bientôt")
                        .font(.caption).foregroundStyle(done ? Color.green : Theme.textSecondary)
                }
                Spacer()
                if has {
                    Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(done ? AnyShapeStyle(Color.green) : AnyShapeStyle(Color.secondary))
                }
            }
            .padding(14)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14))
            .opacity(has ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(!has)
    }
}
