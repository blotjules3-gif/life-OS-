import SwiftUI

// MARK: - Preferences de Mes espaces (logique pure)

/// Domaine favori et domaines prioritaires. Le favori choisi a la main gagne ;
/// sinon il suit le premier domaine prioritaire choisi a l'accueil, puis l'ancien
/// "2e onglet au choix", puis les modules recommandes.
enum SpacesPreferences {
    static let favoriteKey = "spaces.favoriteDomain"
    static let openFavoriteKey = "spaces.openFavoriteDirectly"
    static let classicViewKey = "spaces.classicBubbles"
    /// Ecrit par l'accueil (PriorityDomains) : "nutrition,fitness,productivity".
    static let priorityKey = PriorityDomains.storageKey

    static let fallbackOrder: [AppCategory] = [.productivity, .nutrition, .fitness, .sleep, .finance, .mind]

    static func parse(_ raw: String) -> [AppCategory] {
        var seen = Set<AppCategory>()
        return raw.split(separator: ",")
            .compactMap { AppCategory(rawValue: $0.trimmingCharacters(in: .whitespaces)) }
            .filter { seen.insert($0).inserted }
    }

    /// Ancien 2e onglet : une categorie, ou le Reveil qui vit dans Sommeil.
    static func legacySecondTab(_ raw: String) -> AppCategory? {
        guard !raw.isEmpty, let t = SecondTab(rawValue: raw) else { return nil }
        return t.category
    }

    static func favorite(storedRaw: String, priorityRaw: String, secondTabRaw: String, recommendedRaw: String) -> AppCategory {
        if let c = AppCategory(rawValue: storedRaw) { return c }
        if let c = parse(priorityRaw).first { return c }
        if let c = legacySecondTab(secondTabRaw) { return c }
        if let c = parse(recommendedRaw).first { return c }
        return fallbackOrder[0]
    }

    /// Les deux autres domaines prioritaires (jamais le favori, jamais deux fois le meme).
    static func others(favorite: AppCategory, priorityRaw: String, recommendedRaw: String, count: Int = 2) -> [AppCategory] {
        var out: [AppCategory] = []
        for c in parse(priorityRaw) + parse(recommendedRaw) + fallbackOrder where c != favorite && !out.contains(c) {
            out.append(c)
            if out.count == count { break }
        }
        return out
    }
}

// MARK: - Onglet Mes espaces

struct SpacesView: View {
    var onOpen: (AppCategory) -> Void
    var onSearch: () -> Void

    @AppStorage(SpacesPreferences.favoriteKey) private var favoriteRaw = ""
    @AppStorage(SpacesPreferences.openFavoriteKey) private var openFavoriteDirectly = false
    @AppStorage(SpacesPreferences.classicViewKey) private var classicBubbles = false
    @AppStorage(SpacesPreferences.priorityKey) private var priorityRaw = ""
    @AppStorage(AppStorageKeys.secondTab) private var secondTabRaw = ""
    @AppStorage(AppStorageKeys.recommendedModules) private var recommendedRaw = ""
    @AppStorage(ToolNames.storageKey) private var toolNamesRaw = ""
    @ObservedObject private var orderManager = CategoryOrderManager.shared

    @State private var showOrder = false
    @State private var showIntake = false

    private var favorite: AppCategory {
        SpacesPreferences.favorite(storedRaw: favoriteRaw, priorityRaw: priorityRaw,
                                   secondTabRaw: secondTabRaw, recommendedRaw: recommendedRaw)
    }
    private var priorities: [AppCategory] {
        SpacesPreferences.others(favorite: favorite, priorityRaw: priorityRaw, recommendedRaw: recommendedRaw)
    }
    private var rest: [AppCategory] {
        let shown = Set([favorite] + priorities)
        let ordered = orderManager.order.isEmpty ? AppCategory.allCases : orderManager.order
        return ordered.filter { !shown.contains($0) }
    }

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                searchPill
                favoriteCard
                if !priorities.isEmpty {
                    sectionTitle("Tes priorités")
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(priorities) { cat in spaceTile(cat, prominent: true) }
                    }
                }
                if CategorySetup.fraction < 1.0 { intakeCard }
                sectionTitle("Tous les espaces")
                LazyVGrid(columns: cols, spacing: 12) {
                    ForEach(rest) { cat in spaceTile(cat, prominent: false) }
                }
            }
            .padding(.horizontal, Theme.pad)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .floatingBarClearance()
        .sheet(isPresented: $showOrder) { CategoryOrderSheet() }
        .fullScreenCover(isPresented: $showIntake) { IntakeHubView() }
    }

    // MARK: En-tete

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mes espaces")
                .font(AppFont.heading(size: 32, weight: .black))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Picker("Espace favori", selection: Binding(get: { favorite }, set: { favoriteRaw = $0.rawValue })) {
                    ForEach(AppCategory.allCases) { c in Label(c.title, systemImage: c.icon).tag(c) }
                }
                Toggle("Ouvrir mon favori directement", isOn: $openFavoriteDirectly)
                Divider()
                Button { showOrder = true } label: { Label("Trier les espaces", systemImage: "arrow.up.arrow.down") }
                Toggle(isOn: $classicBubbles) { Label("Vue en bulles", systemImage: "circle.grid.3x3") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 44, height: 44)
                    .raisedSurface(Circle())
            }
            .accessibilityLabel("Réglages de Mes espaces")
        }
    }

    private var searchPill: some View {
        Button { Haptics.tap(); onSearch() } label: {
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").font(.body.weight(.semibold))
                Text("Outil, tâche, note, contact…").font(.body)
                Spacer()
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rechercher dans LifeOS")
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Favori

    private var favoriteCard: some View {
        let cat = favorite
        let quick = Array(cat.tools.prefix(3))
        return VStack(alignment: .leading, spacing: 14) {
            Button { Haptics.tap(); onOpen(cat) } label: {
                HStack(spacing: 14) {
                    IconBadge(icon: cat.icon, tint: cat.tint, size: 52).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Favori", systemImage: "star.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                        Text(cat.title)
                            .font(AppFont.heading(size: 22, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Text(cat.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Espace favori, \(cat.title)")

            if !quick.isEmpty {
                HStack(spacing: 8) {
                    ForEach(quick) { tool in
                        Button {
                            Haptics.tap()
                            DeepLinkRouter.shared.send(.tool(cat, tool.defaultTitle))
                        } label: {
                            Label(tool.title, systemImage: tool.icon)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .frame(maxWidth: .infinity)
                                .raisedSurface(Capsule(), .nested)
                        }
                        .buttonStyle(LifeOSPressStyle(scale: 0.95))
                        .accessibilityLabel("Ouvrir \(tool.title)")
                    }
                }
            }
        }
        .padding(Theme.pad)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous), .floating)
    }

    // MARK: Tuiles

    private func spaceTile(_ cat: AppCategory, prominent: Bool) -> some View {
        Button { Haptics.tap(); onOpen(cat) } label: {
            VStack(alignment: .leading, spacing: prominent ? 12 : 8) {
                IconBadge(icon: cat.icon, tint: cat.tint, size: prominent ? 40 : 32).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cat.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if prominent {
                        Text(cat.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: prominent ? 118 : 84, alignment: .topLeading)
            .padding(14)
            .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall + 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(cat.title)
        .accessibilityHint(cat.subtitle)
    }

    private var intakeCard: some View {
        Button { showIntake = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Complète ton profil").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(CategorySetup.doneCount)/\(CategorySetup.flows.count)")
                        .font(.footnote.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: CategorySetup.fraction)
                    .tint(Color.accentColor)
                Text("Réponds aux questions des espaces qui te manquent. Tu peux reprendre plus tard.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .card(padding: 14)
        }
        .buttonStyle(PressableButtonStyle())
    }
}
