import SwiftUI
import UIKit

/// Les 17 pôles de LifeOS (16 pour tous + `cycle` conditionnel). Pilotent la
/// grille du tableau de bord et la navigation.
enum AppCategory: String, CaseIterable, Identifiable {
    case fitness, nutrition, productivity, mind, finance,
         invest, sleep, admin, learning, career,
         looks, home, mobility, travel, social, medical, cycle

    /// Liste des catégories ordonnée selon les préférences de l'utilisateur (ou défaut optimisé plateforme)
    static var ordered: [AppCategory] {
        CategoryOrderManager.shared.order
    }

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

    /// Couleur du domaine, depuis la table unique `DomainPalette` (clair / sombre).
    var palettePair: DomainPalette.Pair {
        switch self {
        case .sleep:        return DomainPalette.sleep
        case .nutrition:    return DomainPalette.nutrition
        case .fitness:      return DomainPalette.fitness
        case .looks:        return DomainPalette.looks
        case .mind:         return DomainPalette.mind
        case .productivity: return DomainPalette.productivity
        case .finance:      return DomainPalette.finance
        case .invest:       return DomainPalette.invest
        case .career:       return DomainPalette.career
        case .learning:     return DomainPalette.learning
        case .home:         return DomainPalette.home
        case .mobility:     return DomainPalette.mobility
        case .social:       return DomainPalette.social
        case .admin:        return DomainPalette.admin
        case .travel:       return DomainPalette.travel
        case .cycle:        return DomainPalette.cycle
        case .medical:      return DomainPalette.medical
        }
    }

    /// La couleur dynamique (clair / sombre / palette neutre) que `tint` affiche.
    var tintUIColor: UIColor { Theme.toneUIColor(palettePair) }

    /// Petits accents et icones sur verre. Jamais le seul porteur du sens : l'icone et
    /// le titre de la catégorie restent lisibles en palette neutre.
    var tint: Color { Color(uiColor: tintUIColor) }

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
            .onAppear {
                ModuleUsageTracker.shared.track(self)
                Task { @MainActor in AnalyticsEvents.moduleOpened(self.rawValue) }
            }
    }
}
