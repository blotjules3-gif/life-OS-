import SwiftUI

/// Les 15 pôles de LifeOS. Pilotent la grille du tableau de bord et la navigation.
enum AppCategory: String, CaseIterable, Identifiable {
    case sleep, nutrition, fitness, looks, mind, productivity, finance,
         invest, career, learning, home, mobility, social, admin, travel, cycle, medical

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
        case .medical: return "Santé médicale"
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
        case .medical: return "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sleep:        return Theme.sleep
        case .nutrition:    return Theme.nutrition
        case .fitness:      return Theme.fitness
        case .looks:        return Theme.looks
        case .mind:         return Theme.mind
        case .productivity: return Theme.productivity
        case .finance:      return Theme.finance
        case .invest:       return Theme.invest
        case .career:       return Theme.career
        case .learning:     return Theme.learning
        case .home:         return Theme.home
        case .mobility:     return Theme.mobility
        case .social:       return Theme.social
        case .admin:        return Theme.admin
        case .travel:       return Theme.travel
        case .cycle:        return Theme.cycle
        case .medical:      return Theme.medical
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
        case .medical: return "Médicaments, RDV, carnets"
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
