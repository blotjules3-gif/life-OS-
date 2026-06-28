import SwiftUI

/// Les 15 pôles de LifeOS. Pilotent la grille du tableau de bord et la navigation.
enum AppCategory: String, CaseIterable, Identifiable {
    case sleep, nutrition, fitness, looks, mind, productivity, finance,
         invest, career, learning, home, mobility, social, admin, travel, cycle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: return "Sommeil & réveil"
        case .nutrition: return "Nutrition"
        case .fitness: return "Sport & fitness"
        case .looks: return "Looksmaxx"
        case .mind: return "Mental & focus"
        case .productivity: return "Productivité"
        case .finance: return "Finances perso"
        case .invest: return "Investissement"
        case .career: return "Carrière"
        case .learning: return "Apprentissage"
        case .home: return "Maison & quotidien"
        case .mobility: return "Mobilité"
        case .social: return "Social & relations"
        case .admin: return "Admin & paperasse"
        case .travel: return "Voyage"
        case .cycle: return "Cycle menstruel"
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "moon.stars.fill"
        case .nutrition: return "fork.knife"
        case .fitness: return "figure.run"
        case .looks: return "face.smiling"
        case .mind: return "brain.head.profile"
        case .productivity: return "checklist"
        case .finance: return "creditcard.fill"
        case .invest: return "chart.line.uptrend.xyaxis"
        case .career: return "briefcase.fill"
        case .learning: return "graduationcap.fill"
        case .home: return "house.fill"
        case .mobility: return "tram.fill"
        case .social: return "person.2.fill"
        case .admin: return "folder.fill"
        case .travel: return "airplane"
        case .cycle: return "drop.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep: return Color(hex: 0x6C7BF1)
        case .nutrition: return Color(hex: 0x4CC38A)
        case .fitness: return Color(hex: 0xF1746C)
        case .looks: return Color(hex: 0xE0A23C)
        case .mind: return Color(hex: 0x9B6CF1)
        case .productivity: return Color(hex: 0x3CB2E0)
        case .finance: return Color(hex: 0x4CC38A)
        case .invest: return Color(hex: 0x46C9A8)
        case .career: return Color(hex: 0xE07B3C)
        case .learning: return Color(hex: 0xF97316)
        case .home: return Color(hex: 0x6CA0F1)
        case .mobility: return Color(hex: 0x3CD0C8)
        case .social: return Color(hex: 0xF16CB0)
        case .admin: return Color(hex: 0x8A93A8)
        case .travel: return Color(hex: 0x6C9BF1)
        case .cycle: return Color(hex: 0xE85D9A)
        }
    }

    var subtitle: String {
        switch self {
        case .sleep: return "Cycles, réveil malin, sieste"
        case .nutrition: return "Calories, jeûne, courses"
        case .fitness: return "Pas, muscu, HIIT, streaks"
        case .looks: return "Skincare, mewing, garde-robe"
        case .mind: return "Méditation, humeur, focus"
        case .productivity: return "To-do, habitudes, notes"
        case .finance: return "Budget, abonnements, split"
        case .invest: return "Portefeuille, FIRE, immo"
        case .career: return "Candidatures, CV, entretien"
        case .learning: return "Flashcards, skills, résumés"
        case .home: return "Anti-gaspi, animaux, tâches"
        case .mobility: return "Trajets, voiture, carburant"
        case .social: return "CRM, anniversaires, events"
        case .admin: return "Coffre-fort, échéances"
        case .travel: return "Itinéraire, valise, vols"
        case .cycle: return "Règles, ovulation, symptômes"
        }
    }

    @ViewBuilder
    var destination: some View {
        // Hub data-driven : rend les outils dans le mode d'affichage actif
        // (bulles / icônes / liste), comme la grille de catégories. Voir CategoryHub.swift.
        CategoryHubView(category: self)
    }
}

/// Brique de navigation interne à un hub : une ligne native qui pousse une vue.
struct ToolRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String = ""
    var tint: Color = Theme.accent
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 3)
        }
    }
}

/// Conteneur standard d'un hub : liste groupée sobre.
struct HubScaffold<Content: View>: View {
    let category: AppCategory
    @ViewBuilder var content: () -> Content
    var body: some View {
        List {
            content()
        }
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
