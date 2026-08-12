import SwiftUI
import SwiftData

/// Syncers agrégats — publient des signaux résumés dans l'App Group pour :
///   • Alimenter le contexte coach (UserContextBuilder.build) sans requête SwiftData
///   • Nourrir les futures tuiles de la Home unifiée (LifeStatusTile)
///   • Rester lisibles depuis les widgets (App Group partagé)
///
/// Pattern : chaque syncer est une vue invisible qui @Query un modèle,
/// écoute les changements + le passage à foreground, et publie un résumé
/// (ex. array de scores, moyenne, dernier) dans `UserDefaults(suiteName: "group.lifeos.app")`.
///
/// Convention de clé : `<domain>_<metric>_<horizon>` (ex. `mood_recent_7d`,
/// `energy_score_today`, `kcal_today`). Ne jamais renommer une clé existante
/// sans code de migration (les widgets et le coach lisent).

private let appGroup = "group.lifeos.app"

// MARK: - Humeur

/// Publie les 7 derniers scores d'humeur (les plus récents en tête) sous
/// `mood_recent_7d` (JSON array of Int, 1…5). Lu par UserContextBuilder pour
/// afficher "Humeur récente: 4, 3, 5 (moy 4.0/5)".
struct MoodWidgetSyncer: View {
    @Query(sort: \MoodEntry.date, order: .reverse) private var moods: [MoodEntry]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { sync() }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                sync()
            }
            .onChange(of: moods.count) { _, _ in sync() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private func sync() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) else { return }
        let scores = moods
            .filter { $0.date >= weekAgo }
            .prefix(7)
            .map { $0.score }
        if scores.isEmpty {
            defaults.removeObject(forKey: "mood_recent_7d")
            defaults.removeObject(forKey: "mood_avg_7d")
        } else {
            if let data = try? JSONSerialization.data(withJSONObject: Array(scores)) {
                defaults.set(data, forKey: "mood_recent_7d")
            }
            let avg = Double(scores.reduce(0, +)) / Double(scores.count)
            defaults.set(avg, forKey: "mood_avg_7d")
        }
    }
}

// MARK: - Sommeil

/// Publie les 7 dernières nuits (heures + qualité) sous `sleep_recent_7d`
/// et la moyenne d'heures sous `sleep_avg_hours_7d`.
struct SleepWidgetSyncer: View {
    @Query(sort: \SleepNight.date, order: .reverse) private var nights: [SleepNight]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { sync() }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                sync()
            }
            .onChange(of: nights.count) { _, _ in sync() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private func sync() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let cal = Calendar.current
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: .now) else { return }
        let recent = nights.filter { $0.date >= weekAgo }.prefix(7)
        if recent.isEmpty {
            defaults.removeObject(forKey: "sleep_recent_7d")
            defaults.removeObject(forKey: "sleep_avg_hours_7d")
            return
        }
        let payload: [[String: Any]] = recent.map { n in
            ["hours": (n.hours * 10).rounded() / 10, "quality": n.quality]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            defaults.set(data, forKey: "sleep_recent_7d")
        }
        let avg = recent.reduce(0.0) { $0 + $1.hours } / Double(recent.count)
        defaults.set((avg * 10).rounded() / 10, forKey: "sleep_avg_hours_7d")
    }
}

// MARK: - Nutrition (kcal + eau du jour)

/// Publie les totaux nutritionnels du jour sous `today_kcal`, `today_protein_g`,
/// `today_water_ml` — clés déjà lues par UserContextBuilder.
struct NutritionTodaySyncer: View {
    @Query(sort: \FoodEntry.date, order: .reverse) private var foods: [FoodEntry]
    @Query(sort: \WaterEntry.date, order: .reverse) private var waters: [WaterEntry]

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .onAppear { sync() }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                sync()
            }
            .onChange(of: foods.count) { _, _ in sync() }
            .onChange(of: waters.count) { _, _ in sync() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in sync() }
    }

    private func sync() {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let foodsToday = foods.filter { cal.isDate($0.date, inSameDayAs: today) }
        let watersToday = waters.filter { cal.isDate($0.date, inSameDayAs: today) }

        let kcal = foodsToday.reduce(0) { $0 + $1.calories }
        let protein = Int(foodsToday.reduce(0.0) { $0 + $1.protein }.rounded())
        let waterML = watersToday.reduce(0) { $0 + $1.amountML }

        defaults.set(kcal, forKey: "today_kcal")
        defaults.set(protein, forKey: "today_protein_g")
        defaults.set(waterML, forKey: "today_water_ml")
    }
}
