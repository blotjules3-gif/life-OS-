import SwiftUI

// MARK: - Sélecteur d'icônes intelligent (Vue SwiftUI)

public struct SmartIconPicker: View {

    @Binding public var selectedIcon: String
    public var queryText: String
    public var accentColor: Color = Color.accentColor

    @State private var showFullCatalog = false

    public init(selectedIcon: Binding<String>, queryText: String, accentColor: Color = Color.accentColor) {
        self._selectedIcon = selectedIcon
        self.queryText = queryText
        self.accentColor = accentColor
    }

    private var proposedIcons: [String] {
        var list = IconSuggestionEngine.suggest(for: queryText, limit: 20)
        // S'assurer que l'icône couramment sélectionnée apparaît dans les 20 propositions
        if !list.contains(selectedIcon) && !list.isEmpty {
            list[list.count - 1] = selectedIcon
        }
        return list
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Grille de 20 propositions (4 lignes de 5)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(proposedIcons, id: \.self) { iconName in
                    iconCell(iconName)
                }
            }

            // Bouton vers le catalogue complet
            Button {
                showFullCatalog = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Choisir parmi toutes les icônes (1 100+)")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .sheet(isPresented: $showFullCatalog) {
            FullIconCatalogSheet(selectedIcon: $selectedIcon, accentColor: accentColor)
        }
    }

    private func iconCell(_ iconName: String) -> some View {
        let isSelected = selectedIcon == iconName
        let bg = isSelected ? accentColor.opacity(0.25) : Color(uiColor: .secondarySystemFill).opacity(0.6)
        let strokeColor = isSelected ? accentColor : Color.clear
        let fg = isSelected ? accentColor : Color.primary

        return Button {
            withAnimation(.spring(duration: 0.25)) {
                selectedIcon = iconName
            }
            Haptics.soft()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1.5)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(fg)
                    .scaleEffect(isSelected ? 1.08 : 1.0)
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(iconName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Catalogue complet d'icônes avec recherche multi-mots

public struct FullIconCatalogSheet: View {

    @Binding public var selectedIcon: String
    public var accentColor: Color = Color.accentColor
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategoryFilter: String? = nil

    public init(selectedIcon: Binding<String>, accentColor: Color = Color.accentColor) {
        self._selectedIcon = selectedIcon
        self.accentColor = accentColor
    }

    private var totalIconCount: Int {
        IconSuggestionEngine.catalog.reduce(0) { $0 + $1.icons.count }
    }

    private var searchResults: [String] {
        IconSuggestionEngine.search(query: searchText, limit: 120)
    }

    private var filteredCategories: [(category: String, icons: [String])] {
        let clean = IconSuggestionEngine.normalize(searchText)
        if !clean.isEmpty {
            let matched = Set(searchResults)
            var filtered: [(category: String, icons: [String])] = []
            for cat in IconSuggestionEngine.catalog {
                let matching = cat.icons.filter { matched.contains($0) }
                if !matching.isEmpty {
                    filtered.append((cat.category, matching))
                }
            }
            return filtered
        }

        if let filter = selectedCategoryFilter {
            return IconSuggestionEngine.catalog.filter { $0.category == filter }
        }
        return IconSuggestionEngine.catalog
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filtres par catégorie
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedCategoryFilter = nil
                            } label: {
                                Text("Toutes (\(totalIconCount))")
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedCategoryFilter == nil ? accentColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(selectedCategoryFilter == nil ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)

                            ForEach(IconSuggestionEngine.catalog, id: \.category) { cat in
                                let isSel = selectedCategoryFilter == cat.category
                                Button {
                                    selectedCategoryFilter = cat.category
                                } label: {
                                    Text("\(cat.category) (\(cat.icons.count))")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isSel ? accentColor : Color(uiColor: .tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(isSel ? Color.white : Color.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    Divider()
                } else {
                    HStack {
                        Text("\(searchResults.count) icônes trouvées pour « \(searchText) »")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    Divider()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !searchText.isEmpty && searchResults.isEmpty {
                            emptyView
                        } else {
                            ForEach(filteredCategories, id: \.category) { category, icons in
                                categorySection(category: category, icons: icons)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Toutes les icônes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Recherche multi-mots (ex: muscu dos, vélo, café)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Aucune icône trouvée")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func categorySection(category: String, icons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                ForEach(icons, id: \.self) { iconName in
                    catalogCell(iconName: iconName)
                }
            }
        }
    }

    private func catalogCell(iconName: String) -> some View {
        let isSelected = selectedIcon == iconName
        let bg = isSelected ? accentColor.opacity(0.25) : Color(uiColor: .secondarySystemFill).opacity(0.6)
        let strokeColor = isSelected ? accentColor : Color.clear
        let fg = isSelected ? accentColor : Color.primary

        return Button {
            selectedIcon = iconName
            Haptics.soft()
            dismiss()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1.5)
                    )

                Image(systemName: iconName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(fg)
            }
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(iconName)
    }
}
