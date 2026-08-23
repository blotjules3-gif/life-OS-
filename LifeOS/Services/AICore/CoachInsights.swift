import Foundation
import SwiftData

/// Calcule 3 patterns hebdomadaires simples pour injection dans le prompt.
/// Transforme le coach en analyste : au lieu de répondre message par message,
/// il voit les tendances sur la semaine.
///
/// Patterns actuels (Loop 10) :
///   1. **Régularité habitudes** : nombre de jours cette semaine avec ≥1
///      habitude complétée
///   2. **Tendance sommeil** : différence heures moyennes semaine vs 4
///      semaines précédentes
///   3. **Activité sport** : nombre de sessions cette semaine (habits taggées
///      moduleTag = "fitness" OU sport)
///
/// Silencieux si données insuffisantes — pas de bruit.
@MainActor
enum CoachInsights {

    struct Insight {
        let category: String   // "habitudes", "sommeil", "sport"
        let text: String       // phrase courte à injecter
    }

    /// Retourne 0-3 insights formatés — s'auto-limite si donnée manquante.
    static func weeklyInsights() -> [Insight] {
        var out: [Insight] = []
        if let habits = habitConsistency() { out.append(habits) }
        if let sleep = sleepTrend() { out.append(sleep) }
        if let sport = sportSessions() { out.append(sport) }
        return out
    }

    /// Rend un bloc prompt prêt à concaténer. Vide si aucun insight.
    static func promptBlock() -> String {
        let insights = weeklyInsights()
        guard !insights.isEmpty else { return "" }
        var lines = ["Tendances cette semaine :"]
        for i in insights {
            lines.append("- \(i.text)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Patterns

    /// Jours cette semaine (lundi → aujourd'hui) avec au moins 1 habitude complétée.
    private static func habitConsistency() -> Insight? {
        guard let ctx = SharedModelContextProvider.shared.context else { return nil }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isArchived == false }
        )
        let habits = (try? ctx.fetch(descriptor)) ?? []
        guard !habits.isEmpty else { return nil }

        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let daysWithCompletion = Set(habits
            .flatMap(\.completions)
            .filter { $0.date >= weekStart }
            .map { cal.startOfDay(for: $0.date) })
        let daysElapsed = max(1, cal.dateComponents([.day], from: weekStart, to: .now).day ?? 0)
        return Insight(
            category: "habitudes",
            text: "\(daysWithCompletion.count)/\(daysElapsed + 1) jours avec au moins 1 habitude complétée"
        )
    }

    /// Compare sommeil moyen semaine vs 4 semaines précédentes via App Group.
    /// Le blob `sleep_avg_hours_7d` est publié par `SleepWidgetSyncer`.
    private static func sleepTrend() -> Insight? {
        guard let grp = UserDefaults(suiteName: "group.lifeos.app") else { return nil }
        let avg7d = grp.double(forKey: "sleep_avg_hours_7d")
        let avg28d = grp.double(forKey: "sleep_avg_hours_28d")
        guard avg7d > 0.5, avg28d > 0.5 else { return nil }
        let diff = avg7d - avg28d
        if abs(diff) < 0.2 { return nil }  // trop peu significatif
        let direction = diff > 0 ? "améliore" : "dégrade"
        let delta = String(format: "%.1fh", abs(diff))
        return Insight(
            category: "sommeil",
            text: "Ton sommeil s'\(direction) (\(delta) vs 4 semaines précédentes)"
        )
    }

    /// Tags reconnus comme "sport" — étendus Loop 12 fix M5.
    private static let sportTags: Set<String> = [
        "fitness", "sport", "gym", "workout", "muscu", "cardio",
        "running", "run", "musculation", "training"
    ]

    /// Nombre de séances sport cette semaine (habits avec moduleTag reconnu).
    private static func sportSessions() -> Insight? {
        guard let ctx = SharedModelContextProvider.shared.context else { return nil }
        let descriptor = FetchDescriptor<Habit>(
            predicate: #Predicate { $0.isArchived == false }
        )
        let allHabits = (try? ctx.fetch(descriptor)) ?? []
        let habits = allHabits.filter { sportTags.contains($0.moduleTag.lowercased()) }
        guard !habits.isEmpty else { return nil }
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let sessions = habits.flatMap(\.completions).filter { $0.date >= weekStart }.count
        guard sessions > 0 else { return nil }
        return Insight(
            category: "sport",
            text: "\(sessions) séances de sport cette semaine"
        )
    }
}
