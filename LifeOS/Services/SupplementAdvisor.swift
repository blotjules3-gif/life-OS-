import Foundation

// MARK: - Reco de prise de compléments (100% local, hors-ligne)

struct SuppReco {
    let moment: String        // "matin" | "midi" | "soir"
    let withFood: Bool        // avec un repas / à jeun
    let advice: String        // courte explication affichée + envoyée en notif

    /// Heure conseillée par défaut selon le moment (l'utilisateur peut l'ajuster).
    var hour: Int { moment == "soir" ? 21 : (moment == "midi" ? 12 : 8) }
    var minute: Int { moment == "midi" ? 30 : 0 }

    var foodLabel: String { withFood ? "avec un repas" : "à jeun" }
    var momentLabel: String {
        switch moment {
        case "soir": return "Le soir"
        case "midi": return "Le midi"
        default:     return "Le matin"
        }
    }
    var icon: String {
        switch moment {
        case "soir": return "moon.stars.fill"
        case "midi": return "sun.max.fill"
        default:     return "sunrise.fill"
        }
    }
}

/// Recommande QUAND prendre un complément à partir de son nom. Base de connaissances
/// locale des compléments les plus courants — aucune API requise.
enum SupplementAdvisor {

    static func reco(for raw: String) -> SuppReco {
        let n = raw.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        // Mots collés/séparés → on normalise les tirets en espaces et on encadre d'espaces
        // pour pouvoir matcher les clés COURTES en mot entier (évite « dha » ⊂ « ashwagandha »).
        let padded = " " + n.replacingOccurrences(of: "-", with: " ") + " "
        func has(_ keys: String...) -> Bool {
            keys.contains { key in key.count <= 4 ? padded.contains(" \(key) ") : n.contains(key) }
        }

        // Liposolubles / gras → matin avec repas
        if has("omega", "fish oil", "huile de poisson") {
            return SuppReco(moment: "matin", withFood: true, advice: "Mieux absorbé avec un repas qui contient du gras.")
        }
        if has("vitamine d", "vit d", "vitamin d", "cholecalcif") {
            return SuppReco(moment: "matin", withFood: true, advice: "Vitamine liposoluble : à prendre avec un repas gras.")
        }
        if has("vitamine k", "vit k", "k2", "mk-7", "mk7") {
            return SuppReco(moment: "matin", withFood: true, advice: "À prendre avec la vitamine D et un repas.")
        }
        if has("vitamine a", "retinol", "vitamine e", "vit e", "tocopherol") {
            return SuppReco(moment: "matin", withFood: true, advice: "Liposoluble : avec un repas contenant du gras.")
        }
        if has("curcuma", "curcumin", "turmeric") {
            return SuppReco(moment: "midi", withFood: true, advice: "Avec un repas + du poivre noir pour l'absorption.")
        }
        // Détente / sommeil → soir
        if has("magnesium", "magnésium", "bisglycinate") {
            return SuppReco(moment: "soir", withFood: true, advice: "Favorise la détente musculaire et le sommeil.")
        }
        if has("ashwagandha", "ksm") {
            return SuppReco(moment: "soir", withFood: true, advice: "Adaptogène anti-stress : aide à l'endormissement.")
        }
        if has("melatonine", "melatonin") {
            return SuppReco(moment: "soir", withFood: false, advice: "30 min avant le coucher, lumière tamisée.")
        }
        if has("glycine", "l-theanine", "theanine", "gaba", "valeriane", "camomille") {
            return SuppReco(moment: "soir", withFood: false, advice: "Le soir pour favoriser la détente.")
        }
        if has("calcium") {
            return SuppReco(moment: "soir", withFood: true, advice: "Le soir, avec un repas. Pas en même temps que le fer.")
        }
        // À jeun
        if has("fer", "iron", "bisglycinate de fer", "ferreux") {
            return SuppReco(moment: "matin", withFood: false, advice: "À jeun avec de la vitamine C, loin du café et du thé.")
        }
        if has("probio", "lactobacillus", "ferments") {
            return SuppReco(moment: "matin", withFood: false, advice: "À jeun, 15-20 min avant le petit-déjeuner.")
        }
        if has("collagene", "collagen") {
            return SuppReco(moment: "matin", withFood: false, advice: "À jeun le matin, idéal avec de la vitamine C.")
        }
        if has("zinc") {
            return SuppReco(moment: "soir", withFood: false, advice: "À distance des repas. Pas avec le calcium/fer.")
        }
        // Énergisants → matin
        if has("creatine", "créatine") {
            return SuppReco(moment: "matin", withFood: true, advice: "Dose quotidienne : le timing importe peu, sois régulier.")
        }
        if has("cafeine", "caffeine", "guarana") {
            return SuppReco(moment: "matin", withFood: false, advice: "Le matin uniquement, sinon ça gâche le sommeil.")
        }
        if has("rhodiola", "ginseng", "tyrosine", "b12", "b-12", "b complex", "complexe b", "spiruline", "ginkgo") {
            return SuppReco(moment: "matin", withFood: true, advice: "Le matin : effet plutôt énergisant.")
        }
        if has("vitamine c", "vit c", "ascorbic") {
            return SuppReco(moment: "matin", withFood: true, advice: "Le matin avec le petit-déjeuner.")
        }
        if has("multivitamine", "multivitamin", "multi ") || n == "multi" {
            return SuppReco(moment: "matin", withFood: true, advice: "Avec le petit-déjeuner pour bien tout absorber.")
        }
        if has("whey", "proteine", "protein", "bcaa", "eaa") {
            return SuppReco(moment: "matin", withFood: false, advice: "Autour de l'entraînement ou en collation.")
        }
        // Défaut prudent
        return SuppReco(moment: "matin", withFood: true, advice: "À prendre au petit-déjeuner, sauf avis contraire.")
    }
}

// MARK: - Suivi des confirmations (streaks) — alimenté par les notifs « Oui ✓ »

/// Stocke, par habitude (clé), la dernière confirmation et la série de jours consécutifs.
/// Utilisé par les notifs de confirmation (compléments, salle, etc.) via l'AppDelegate.
final class ConfirmationStore {
    static let shared = ConfirmationStore()
    private let d = UserDefaults.standard
    private init() {}

    private func lastKey(_ k: String) -> String { "confirm.\(k).last" }
    private func streakKey(_ k: String) -> String { "confirm.\(k).streak" }

    /// Marque l'habitude comme faite aujourd'hui et met à jour la série.
    func markDone(_ key: String) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let last = d.object(forKey: lastKey(key)) as? Date ?? .distantPast
        guard !cal.isDate(last, inSameDayAs: today) else { return }   // déjà compté
        let yesterday = cal.date(byAdding: .day, value: -1, to: today) ?? today
        let newStreak = cal.isDate(last, inSameDayAs: yesterday) ? streak(key) + 1 : 1
        d.set(today, forKey: lastKey(key))
        d.set(newStreak, forKey: streakKey(key))
    }

    func streak(_ key: String) -> Int { d.integer(forKey: streakKey(key)) }

    func doneToday(_ key: String) -> Bool {
        guard let last = d.object(forKey: lastKey(key)) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }
}
