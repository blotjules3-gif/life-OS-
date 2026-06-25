import SwiftUI

/// Onglet Catégories — liste groupée sobre des 15 pôles, organisée en rubriques (façon Réglages).
struct CategoriesView: View {
    private let sections: [(String, [AppCategory])] = [
        ("Santé & corps", [.sleep, .nutrition, .fitness, .looks, .cycle]),
        ("Esprit & focus", [.mind, .productivity, .learning]),
        ("Argent", [.finance, .invest, .career]),
        ("Quotidien", [.home, .mobility, .social, .admin, .travel])
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.0) { section in
                    Section(section.0) {
                        ForEach(section.1) { cat in
                            NavigationLink {
                                cat.destination
                            } label: {
                                CategoryRow(category: cat)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Catégories")
        }
    }
}

/// Ligne de catégorie : petite icône carrée colorée + titre + sous-titre discret.
struct CategoryRow: View {
    let category: AppCategory
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(category.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(category.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
