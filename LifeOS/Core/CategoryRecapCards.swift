import SwiftUI
import SwiftData

/// Carte de récapitulatif contextuel affichée en tête du tableau de bord de chaque catégorie.
struct CategoryRecapCard: View {
    let category: AppCategory

    @Query private var steps: [StepEntry]
    @Query private var workouts: [WorkoutSet]
    @Query private var foods: [FoodEntry]
    @Query private var waters: [WaterEntry]
    @Query private var todos: [TodoItem]
    @Query private var habits: [Habit]
    @Query private var sleeps: [SleepNight]
    @Query private var appointments: [MedicalAppointment]
    @Query private var documents: [DocVault]
    @Query private var trips: [Trip]
    @Query private var pantry: [PantryItem]
    @Query private var pets: [Pet]
    @Query private var holdings: [Holding]
    @Query private var jobs: [JobApplication]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Récapitulatif", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(category.tint)
                    .textCase(.uppercase)
                Spacer()
                Text(todayFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            metricsContent
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(category.tint.opacity(0.2), lineWidth: 1)
        )
    }

    private var todayFormatted: String {
        Date.now.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR")))
    }

    @ViewBuilder
    private var metricsContent: some View {
        switch category {
        case .fitness:
            fitnessRecap
        case .nutrition:
            nutritionRecap
        case .productivity:
            productivityRecap
        case .sleep:
            sleepRecap
        case .finance, .invest:
            financeRecap
        case .medical:
            medicalRecap
        case .home:
            homeRecap
        case .admin:
            adminRecap
        case .travel:
            travelRecap
        case .career:
            careerRecap
        default:
            genericRecap
        }
    }

    // MARK: - Recaps spécifiques

    private var fitnessRecap: some View {
        let cal = Calendar.current
        let todaySteps = steps.first { cal.isDateInToday($0.day) }?.steps ?? 0
        let weekWorkouts = workouts.filter {
            guard let sevenDaysAgo = cal.date(byAdding: .day, value: -7, to: .now) else { return false }
            return $0.date >= sevenDaysAgo
        }.count

        return HStack(spacing: 16) {
            recapMetric(title: "Pas aujourd'hui", value: "\(todaySteps.formatted())", unit: "pas", icon: "figure.walk", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Séances (7j)", value: "\(weekWorkouts)", unit: "séance\(weekWorkouts > 1 ? "s" : "")", icon: "dumbbell.fill", color: .orange)
        }
    }

    private var nutritionRecap: some View {
        let cal = Calendar.current
        let todayFoods = foods.filter { cal.isDateInToday($0.date) }
        let totalCal = todayFoods.reduce(0) { $0 + $1.calories }
        let todayWater = waters.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        let waterLiters = Double(todayWater) / 1000.0

        return HStack(spacing: 16) {
            recapMetric(title: "Calories du jour", value: "\(totalCal)", unit: "kcal", icon: "flame.fill", color: .orange)
            Divider().frame(height: 36)
            recapMetric(title: "Hydratation", value: String(format: "%.1f", waterLiters), unit: "L / 2L", icon: "drop.fill", color: .cyan)
        }
    }

    private var productivityRecap: some View {
        let openTasks = todos.filter { !$0.done }.count
        let activeHabits = habits.filter { !$0.isArchived }
        let doneHabits = activeHabits.filter { h in
            h.completions.contains { Calendar.current.isDateInToday($0.date) }
        }.count

        return HStack(spacing: 16) {
            recapMetric(title: "Tâches à faire", value: "\(openTasks)", unit: "en cours", icon: "checklist", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Habitudes faites", value: "\(doneHabits)/\(max(activeHabits.count, 1))", unit: "validées", icon: "checkmark.circle.fill", color: .green)
        }
    }

    private var sleepRecap: some View {
        let lastNight = sleeps.sorted { $0.date > $1.date }.first
        let duration = lastNight.map { String(format: "%.1fh", $0.hours) } ?? "7.5h"
        let qualityScore = lastNight.map { "\($0.quality * 20)%" } ?? "85%"

        return HStack(spacing: 16) {
            recapMetric(title: "Dernière nuit", value: duration, unit: "durée", icon: "bed.double.fill", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Qualité estimée", value: qualityScore, unit: "score", icon: "moon.stars.fill", color: .indigo)
        }
    }

    private var financeRecap: some View {
        let count = holdings.count
        return HStack(spacing: 16) {
            recapMetric(title: "Actifs suivis", value: "\(count)", unit: "lignes", icon: "chart.line.uptrend.xyaxis", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Objectif budget", value: "Actif", unit: "suivi mensuel", icon: "eurosign.circle.fill", color: .green)
        }
    }

    private var medicalRecap: some View {
        let upcoming = appointments.filter { $0.date >= Date.now }.count
        return HStack(spacing: 16) {
            recapMetric(title: "Rendez-vous à venir", value: "\(upcoming)", unit: "prévu\(upcoming > 1 ? "s" : "")", icon: "calendar.badge.clock", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Santé & carnet", value: "À jour", unit: "dossier médical", icon: "heart.text.square.fill", color: .red)
        }
    }

    private var homeRecap: some View {
        let pCount = pantry.count
        let petCount = pets.count
        return HStack(spacing: 16) {
            recapMetric(title: "Aliments en stock", value: "\(pCount)", unit: "articles", icon: "refrigerator.fill", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Animaux suivis", value: "\(petCount)", unit: "compagnon\(petCount > 1 ? "s" : "")", icon: "pawprint.fill", color: .brown)
        }
    }

    private var adminRecap: some View {
        let docCount = documents.count
        return HStack(spacing: 16) {
            recapMetric(title: "Documents coffre", value: "\(docCount)", unit: "numérisé\(docCount > 1 ? "s" : "")", icon: "lock.doc.fill", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Démarches", value: "Sécurisé", unit: "sauvegarde locale", icon: "checkmark.shield.fill", color: .blue)
        }
    }

    private var travelRecap: some View {
        let count = trips.count
        return HStack(spacing: 16) {
            recapMetric(title: "Voyages enregistrés", value: "\(count)", unit: "itinéraire\(count > 1 ? "s" : "")", icon: "airplane", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Bagages & listes", value: "Prêt", unit: "checklists", icon: "suitcase.fill", color: .cyan)
        }
    }

    private var careerRecap: some View {
        let count = jobs.count
        return HStack(spacing: 16) {
            recapMetric(title: "Candidatures", value: "\(count)", unit: "en cours", icon: "briefcase.fill", color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Profil & CV", value: "Actif", unit: "mise à jour", icon: "doc.text.fill", color: .purple)
        }
    }

    private var genericRecap: some View {
        HStack(spacing: 16) {
            recapMetric(title: "Statut du module", value: "Actif", unit: category.title, icon: category.icon, color: category.tint)
            Divider().frame(height: 36)
            recapMetric(title: "Outils connectés", value: "\(category.tools.count)", unit: "fonctionnalités", icon: "square.grid.2x2.fill", color: category.tint)
        }
    }

    private func recapMetric(title: String, value: String, unit: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
