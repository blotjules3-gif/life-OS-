import Foundation
import SwiftData

/// Génère un résumé texte des 30 derniers jours pour un bilan mensuel coach.
///
/// Contenu :
///   - Habitudes : nombre total de complétions + top 3 habitudes par streak
///   - Sommeil : moyenne 28j vs 7j (via `sleep_avg_hours_*` App Group)
///   - Poids : delta début vs fin de mois (via `VitalRecord` type="poids")
///   - Nutrition : moyenne kcal/jour si data disponible
///   - Cost cloud : cumul sur 30j (via `AIProviderUsageTracker.monthlySnapshot`)
///
/// Silencieux si donnée insuffisante — pas de bloc vide affiché.
@MainActor
enum MonthlyReviewGenerator {

    /// Génère un texte formaté (~200-400 mots) prêt à être injecté comme
    /// message user dans le chat coach ou affiché tel quel.
    static func generateSummary() -> String {
        var lines: [String] = []
        lines.append("Bilan des 30 derniers jours :")
        lines.append("")

        if let habits = habitsBlock() { lines.append(habits) }
        if let sleep = sleepBlock() { lines.append(sleep) }
        if let weight = weightBlock() { lines.append(weight) }
        if let nutrition = nutritionBlock() { lines.append(nutrition) }
        if let cost = costBlock() { lines.append(cost) }

        // Si rien à dire → message court
        if lines.count == 2 {
            lines.append("Pas encore assez de données pour un vrai bilan. Reviens dans quelques semaines.")
        } else {
            lines.append("")
            lines.append("Qu'est-ce que tu veux améliorer le mois prochain ?")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Blocks

    private static func habitsBlock() -> String? {
        guard let ctx = SharedModelContextProvider.shared.context else { return nil }
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isArchived == false }
        ))) ?? []
        guard !habits.isEmpty else { return nil }

        let cal = Calendar.current
        let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let totalCompletions = habits.reduce(0) { total, h in
            total + h.completions.filter { $0.date >= monthAgo }.count
        }
        guard totalCompletions > 0 else { return nil }

        // Top 3 par nombre de complétions sur 30j
        let sorted = habits
            .map { habit -> (name: String, count: Int) in
                let c = habit.completions.filter { $0.date >= monthAgo }.count
                return (habit.name, c)
            }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(3)

        var out = "Habitudes : \(totalCompletions) complétions ce mois."
        if !sorted.isEmpty {
            let top = sorted.map { "\($0.name) (\($0.count))" }.joined(separator: ", ")
            out += " Top : \(top)."
        }
        return out
    }

    private static func sleepBlock() -> String? {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return nil }
        let avg28 = grp.double(forKey: "sleep_avg_hours_28d")
        let avg7 = grp.double(forKey: "sleep_avg_hours_7d")
        guard avg28 > 0.5 else { return nil }

        var parts = [String(format: "Sommeil : %.1fh/nuit en moyenne sur 30 jours", avg28)]
        if avg7 > 0.5 {
            let diff = avg7 - avg28
            if abs(diff) >= 0.3 {
                let dir = diff > 0 ? "en hausse" : "en baisse"
                parts.append(String(format: "(%@ de %.1fh cette semaine)", dir, abs(diff)))
            }
        }
        return parts.joined(separator: " ") + "."
    }

    private static func weightBlock() -> String? {
        guard let ctx = SharedModelContextProvider.shared.context else { return nil }
        let cal = Calendar.current
        let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let descriptor = FetchDescriptor<VitalRecord>(
            predicate: #Predicate { $0.type == "poids" && $0.date >= monthAgo },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        let records = (try? ctx.fetch(descriptor)) ?? []
        guard records.count >= 2 else { return nil }

        // Loop 23 fix M5 — moyenne par jour pour lisser les fluctuations
        // intra-day (poids matin vs soir). On agrège par startOfDay puis on
        // compare la moyenne des 7 premiers vs des 7 derniers jours du mois.
        let byDay = Dictionary(grouping: records) { cal.startOfDay(for: $0.date) }
            .mapValues { records -> Double in
                records.reduce(0) { $0 + $1.value } / Double(records.count)
            }
        let sortedDays = byDay.keys.sorted()
        guard sortedDays.count >= 4 else { return nil }

        let firstWindow = sortedDays.prefix(min(7, sortedDays.count / 2))
        let lastWindow = sortedDays.suffix(min(7, sortedDays.count / 2))
        let firstAvg = firstWindow.compactMap { byDay[$0] }.reduce(0, +) / Double(firstWindow.count)
        let lastAvg = lastWindow.compactMap { byDay[$0] }.reduce(0, +) / Double(lastWindow.count)
        let delta = lastAvg - firstAvg
        guard abs(delta) >= 0.3 else { return nil }
        let sign = delta > 0 ? "+" : ""
        return String(format: "Poids : %@%.1f kg sur le mois (moyenne %.1f → %.1f, lissée par jour).",
                     sign, delta, firstAvg, lastAvg)
    }

    private static func nutritionBlock() -> String? {
        guard let ctx = SharedModelContextProvider.shared.context else { return nil }
        let cal = Calendar.current
        let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let entries = (try? ctx.fetch(FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.date >= monthAgo }
        ))) ?? []
        guard entries.count >= 5 else { return nil }
        let totalKcal = entries.reduce(0) { $0 + $1.calories }
        // Compte de jours distincts avec au moins 1 entry
        let distinctDays = Set(entries.map { cal.startOfDay(for: $0.date) }).count
        guard distinctDays > 0 else { return nil }
        let avgKcal = totalKcal / distinctDays
        return "Nutrition : \(avgKcal) kcal/jour en moyenne (sur \(distinctDays) jours trackés)."
    }

    private static func costBlock() -> String? {
        var totalEUR: Double = 0
        for slot in AIProviderCredentials.Slot.allCases {
            let snap = AIProviderUsageTracker.shared.monthlySnapshot(providerID: slot.providerID)
            totalEUR += AIProviderUsageTracker.usdToEUR(snap.estimatedCostUSD)
        }
        guard totalEUR > 0.01 else { return nil }
        return "Coach cloud : \(UsageFormatter.costEUR(usd: totalEUR / AIProviderUsageTracker.usdToEURRate)) sur le mois."
    }
}
