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

// MARK: - Categorie du questionnaire ouvert

private struct SetupCategoryKey: EnvironmentKey {
    static let defaultValue: AppCategory? = nil
}
extension EnvironmentValues {
    /// Posee par `CategoryFlowView`: permet a la coquille commune de gerer l'etat,
    /// le brouillon et l'annulation sans toucher aux neuf questionnaires.
    var setupCategory: AppCategory? {
        get { self[SetupCategoryKey.self] }
        set { self[SetupCategoryKey.self] = newValue }
    }
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

    /// Effets en base que la coquille ne peut pas deviner (programme regenere...).
    var previewNotes: [String] = []
    /// Ce que les reponses vont changer, calcule par le module a partir de ses
    /// valeurs en cours (celles qui ne sont ecrites qu'a "Appliquer").
    var preview: (() -> [SetupSession.Change])? = nil
    /// Reponses a garder entre deux lancements (premier passage seulement).
    var draft: SetupDraftIO? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.setupCategory) private var category
    @State private var idx = 0
    @State private var session: SetupSession?
    @State private var changes: [SetupSession.Change] = []
    @State private var showPreview = false

    private var isLast: Bool { idx == pages.count - 1 }
    private var editing: Bool { session?.wasCompleted ?? false }

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
        .onAppear(perform: start)
        .onChange(of: idx) { _, _ in persistDraft() }
        // Une app tuee ne tape jamais "Plus tard": on garde tout des qu'elle
        // passe en arriere plan.
        .onChange(of: scenePhase) { _, phase in if phase != .active { persistDraft() } }
        .sheet(isPresented: $showPreview) { previewSheet }
    }

    private func start() {
        guard session == nil, let category else { return }
        let s = SetupSession(category: category)
        s.begin()
        session = s
        idx = CategorySetup.resumePage(category, pageCount: pages.count)
        // Le brouillon doit passer APRES le chargeur du module (son onAppear lit
        // les reglages en place). Mesure le 28 septembre: remis dans un `.task`,
        // il etait ecrase par ce chargeur. Le tour suivant de la boucle
        // principale vient apres tous les onAppear de cet ecran.
        DispatchQueue.main.async { restoreDraft() }
    }

    /// "Plus tard" sur un premier passage: les reponses deja donnees restent et
    /// l'etape est retenue. "Annuler" en modification: tout revient comme avant.
    private func leave() {
        if let session {
            if editing { session.cancel() } else { persistDraft() }
        }
        dismiss()
    }

    /// Page ET reponses. Rien en modification: un questionnaire termine se
    /// rouvre depuis les reglages appliques. Rien avant `ready`: le changement de
    /// page de l'ouverture ecraserait le brouillon avec les valeurs par defaut
    /// avant qu'il soit remis.
    private func persistDraft() {
        guard ready, let session, let category, !editing, !showPreview else { return }
        let answers = draft?.save() ?? SetupDraft()
        let touched = hadDraft || answers != baseline
        if touched { CategorySetup.saveAnswers(category, answers) }
        CategorySetup.saveDraft(category, page: idx, pageCount: pages.count,
                                answered: touched || !session.pendingChanges().isEmpty)
    }

    @State private var ready = false
    @State private var hadDraft = false
    /// Reponses a l'ouverture: ouvrir puis quitter n'est pas "avoir repondu".
    @State private var baseline = SetupDraft()

    private func restoreDraft() {
        guard !ready else { return }
        if let category, let draft, let saved = CategorySetup.loadAnswers(category) {
            draft.restore(saved)
            hadDraft = true
            baseline = saved
        } else {
            baseline = draft?.save() ?? SetupDraft()
        }
        ready = true
    }

    /// Montre ce qui va changer. Rien n'est encore ecrit en base.
    private func finish() {
        guard let session else { onComplete(); dismiss(); return }
        changes = session.pendingChanges() + (preview?() ?? [])
        showPreview = true
    }

    private func accept() {
        onComplete()
        if let category { CategorySetup.markCompleted(category); CategorySetup.clearAnswers(category) }
        showPreview = false
        dismiss()
    }

    private func discard() {
        session?.cancel()
        showPreview = false
        dismiss()
    }

    private var previewSheet: some View {
        NavigationStack {
            List {
                Section {
                    if changes.isEmpty {
                        Text(editing ? "Aucun réglage ne change." : "Tes réponses sont prêtes à être appliquées.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(changes) { c in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.label).font(.subheadline.weight(.semibold))
                            HStack(spacing: 6) {
                                Text(c.before).foregroundStyle(Theme.textSecondary).strikethrough(c.before != "—")
                                Image(systemName: "arrow.right").font(.caption).foregroundStyle(Theme.textSecondary)
                                Text(c.after).foregroundStyle(accent)
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text(editing ? "Ce qui change" : "Ce qui sera réglé")
                }
                if !previewNotes.isEmpty {
                    Section("Aussi") {
                        ForEach(previewNotes, id: \.self) { Text($0).font(.subheadline) }
                    }
                }
                Section {
                    Text("Tes journaux et séances déjà enregistrés ne sont pas modifiés.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Vérifie avant d'appliquer").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Modifier") { showPreview = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer") { accept() }.bold()
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(editing ? "Annuler les changements" : "Tout annuler", role: .destructive) { discard() }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
                Button(editing ? "Annuler" : "Plus tard") { leave() }
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
            if isLast { finish() }
            else { withAnimation { idx += 1 } }
            Haptics.soft()
        } label: {
            Text(isLast ? "Voir le résumé" : "Suivant")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                .background((pages[idx].canAdvance() ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.gray.opacity(0.3))),
                           in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
        }
        .disabled(!pages[idx].canAdvance())
        .padding(.horizontal, 18).padding(.bottom, 14).padding(.top, 6)
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
            // Glyphe choisi par luminance, jamais blanc en dur: l'accent vaut
            // NOIR en theme Classique et BLANC en Sombre, donc un blanc fixe
            // donnait tantot une tuile noire terne, tantot un carre vide.
            Image(systemName: icon).font(.system(size: 30, weight: .semibold))
                .foregroundStyle(accent.readableInk)
                .frame(width: 58, height: 58)
                .background(accent.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: accent.opacity(0.35), radius: 8, y: 4)
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
                    .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous)
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
                        .background(on ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(Color.clear),
                                   in: RoundedRectangle(cornerRadius: 12, style: .continuous)).raisedSurface(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Text("\(value)").font(AppFont.sans(size: 56, weight: .bold))
                    .foregroundStyle(accent).contentTransition(.numericText())
                Text(unit).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 16) {
                stepBtn("minus") { value = max(range.lowerBound, value - step) }
                stepBtn("plus")  { value = min(range.upperBound, value + step) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .raisedSurface(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 14)
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
        Group {
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
        .environment(\.setupCategory, category)
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
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 14).padding(.vertical, 9)
                                .glassControl(Capsule())
                        }.buttonStyle(PressableButtonStyle())
                    }
                }
            }
        }
        .padding(16)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius))
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
                        .font(.caption).foregroundStyle(done ? Theme.success : Theme.textSecondary)
                }
                Spacer()
                if has {
                    Image(systemName: done ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(done ? AnyShapeStyle(Theme.success) : AnyShapeStyle(Color.secondary))
                }
            }
            .padding(14)
            .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .opacity(has ? 1 : 0.5)
        }
        .buttonStyle(.plain).disabled(!has)
    }
}
