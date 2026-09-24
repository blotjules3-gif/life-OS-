import SwiftUI
import Combine

// MARK: - Gestionnaire d'Ordre Manuel des Catégories

final class CategoryOrderManager: ObservableObject {
    static let shared = CategoryOrderManager()

    @Published var order: [AppCategory] = []

    private let userDefaultsKey = "user_custom_category_order_v2"

    init() {
        loadOrder()
    }

    /// Ordre par défaut avec nos modules les plus avancés en tête (Sport, Nutrition, Tâches/To-Do en priorité absolue)
    static var defaultMobileOrder: [AppCategory] {
        [
            .fitness,       // 1. Sport & fitness (séances, HIIT, muscu)
            .nutrition,     // 2. Nutrition (calories, macros, jeûne)
            .productivity,  // 3. Productivité & To-Do (tâches quotidiennes, habitudes)
            .mind,          // 4. Mental & focus
            .finance,       // 5. Finances perso
            .invest,        // 6. Investissement & bourse
            .sleep,         // 7. Sommeil & réveil
            .admin,         // 8. Admin & coffre-fort documents
            .learning,      // 9. Apprentissage & flashcards
            .career,        // 10. Carrière & CV
            .looks,         // 11. Looksmaxx & soins
            .home,          // 12. Maison & quotidien
            .mobility,      // 13. Mobilité
            .travel,        // 14. Voyage
            .social,        // 15. Social & relations (mis en bas selon consigne utilisateur)
            .medical,       // 16. Santé médicale
            .cycle          // 17. Cycle menstruel
        ]
    }

    /// Ordre adapté spécialement pour l'usage sur ordinateur (Desktop Mac) :
    /// Productivité / To-Do quotidienne, Sport, Nutrition, Finances, Coffre Documents en tête !
    static var defaultDesktopOrder: [AppCategory] {
        [
            .productivity,  // 1. To-do list quotidienne & gestionnaire de tâches sur grand écran
            .fitness,       // 2. Programmes de sport, planification séances & HIIT
            .nutrition,     // 3. Planification repas, objectifs calories & macro
            .finance,       // 4. Finances, budget & abonnements (tableaux et calculs sur Mac)
            .invest,        // 5. Portefeuille d'investissement & simulateur
            .admin,         // 6. Coffre-fort & scan de documents Finder
            .learning,      // 7. Apprentissage, prise de notes & compétences
            .career,        // 8. Carrière, candidatures & CV
            .mind,          // 9. Mental, focus pomodoro & journal
            .sleep,         // 10. Sommeil & réveil
            .looks,         // 11. Looksmaxx & garde-robe
            .home,          // 12. Maison & quotidien
            .mobility,      // 13. Mobilité
            .travel,        // 14. Voyage
            .social,        // 15. Social
            .medical,       // 16. Santé médicale
            .cycle          // 17. Cycle
        ]
    }

    var defaultOrder: [AppCategory] {
        #if targetEnvironment(macCatalyst)
        return Self.defaultDesktopOrder
        #else
        return Self.defaultMobileOrder
        #endif
    }

    func loadOrder() {
        if let raw = UserDefaults.standard.string(forKey: userDefaultsKey), !raw.isEmpty {
            let slugs = raw.split(separator: ",").map(String.init)
            var loaded: [AppCategory] = []
            var seen = Set<AppCategory>()
            for slug in slugs {
                if let cat = AppCategory(rawValue: slug), !seen.contains(cat) {
                    loaded.append(cat)
                    seen.insert(cat)
                }
            }
            // Ajouter les catégories manquantes éventuelles
            for cat in defaultOrder {
                if !seen.contains(cat) {
                    loaded.append(cat)
                    seen.insert(cat)
                }
            }
            self.order = loaded
        } else {
            self.order = defaultOrder
        }
    }

    func saveOrder() {
        let raw = order.map(\.rawValue).joined(separator: ",")
        UserDefaults.standard.set(raw, forKey: userDefaultsKey)
    }

    func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        saveOrder()
    }

    /// Place la catégorie tout en haut
    func moveToTop(_ category: AppCategory) {
        guard let idx = order.firstIndex(of: category), idx > 0 else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            let item = order.remove(at: idx)
            order.insert(item, at: 0)
            saveOrder()
        }
    }

    /// Place la catégorie tout en bas (comme demandé par l'utilisateur)
    func moveToBottom(_ category: AppCategory) {
        guard let idx = order.firstIndex(of: category), idx < order.count - 1 else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            let item = order.remove(at: idx)
            order.append(item)
            saveOrder()
        }
    }

    /// Inverse complètement l'ordre avec animation cool
    func reverseOrder() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
            order.reverse()
            saveOrder()
        }
    }

    /// Applique l'ordre optimisé pour Mac
    func setDesktopOptimized() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            order = Self.defaultDesktopOrder
            saveOrder()
        }
    }

    /// Applique l'ordre avec Sport & Nutrition en premier
    func setFitnessFirst() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            order = Self.defaultMobileOrder
            saveOrder()
        }
    }

    /// Réinitialise selon la plateforme active
    func reset() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            order = defaultOrder
            saveOrder()
        }
    }

    /// Trie une liste de BubbleCategory selon l'ordre manuel
    func sortBubbleCategories(_ bubbles: [BubbleCategory]) -> [BubbleCategory] {
        bubbles.sorted { a, b in
            let catA = AppCategory(bubbleTitle: a.title)
            let catB = AppCategory(bubbleTitle: b.title)
            guard let catA, let catB else {
                return (catA != nil) && (catB == nil)
            }
            let indexA = order.firstIndex(of: catA) ?? 999
            let indexB = order.firstIndex(of: catB) ?? 999
            return indexA < indexB
        }
    }
}
