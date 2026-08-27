import SwiftData
import SwiftUI
import UIKit

/// Preview d'un `GoalPlan` avant application — l'user voit exactement ce
/// qui va être créé et valide (ou modifie) explicitement.
///
/// Contrat produit (§ 13 spec) : "L'application propose, l'user décide".
///
/// Loop 24.
struct GoalPlanPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    let goal: UserGoal
    let plan: GoalPlan

    @State private var applied = false
    @State private var applyResult: GoalPlanExecutor.ApplyResult?

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if !plan.modulesToActivate.isEmpty { modulesSection }
                if !plan.habits.isEmpty { habitsSection }
                if !plan.reminders.isEmpty { remindersSection }
                if !plan.profileFields.isEmpty { profileFieldsSection }
                if !plan.recommendations.isEmpty { recommendationsSection }

                if let result = applyResult {
                    Section("Résultat") {
                        Text(summaryOf(result))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(plan.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(applied ? "Fermer" : "Annuler") { dismiss() }
                }
                if !applied {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Créer ce plan") { apply() }
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: plan.goalKind.icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(plan.title).font(.headline)
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
        } footer: {
            Text("\(plan.totalActionCount) actions à créer. Tu peux valider tout ou fermer.")
                .font(.caption2)
        }
    }

    private var modulesSection: some View {
        Section("Modules à activer") {
            ForEach(plan.modulesToActivate, id: \.self) { raw in
                let cat = AppCategory(rawValue: raw)
                Label(cat?.title ?? raw, systemImage: cat?.icon ?? "square.grid.2x2")
            }
        }
    }

    private var habitsSection: some View {
        Section("Habitudes à créer") {
            ForEach(plan.habits, id: \.name) { h in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: h.icon).foregroundStyle(Color.accentColor).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).font(.subheadline.weight(.medium))
                        Text(h.rationale).font(.caption).foregroundStyle(.secondary)
                        Text(String(format: "Prévu %02d:%02d", h.scheduledHour, h.scheduledMinute))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var remindersSection: some View {
        Section("Rappels à créer") {
            ForEach(plan.reminders, id: \.title) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.title).font(.subheadline.weight(.medium))
                    Text(r.message).font(.caption).foregroundStyle(.secondary)
                    Text(scheduleLabel(r))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var profileFieldsSection: some View {
        Section("Cibles profil") {
            ForEach(plan.profileFields, id: \.fieldID) { pf in
                let spec = ProfileFieldCatalog.all[pf.fieldID]
                HStack {
                    Text(spec?.displayName ?? pf.fieldID)
                    Spacer()
                    Text(pf.value.isEmpty ? "(à définir avec ton contexte)" : pf.value)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
    }

    private var recommendationsSection: some View {
        Section("Conseils") {
            ForEach(plan.recommendations) { rec in
                VStack(alignment: .leading, spacing: 3) {
                    Text(rec.title).font(.subheadline.weight(.medium))
                    Text(rec.rationale).font(.caption).foregroundStyle(.secondary)
                    if rec.partnerID == nil {
                        Text("Recommandation neutre")
                            .font(.caption2).foregroundStyle(.tertiary)
                    } else {
                        Text("Offre partenaire — \(rec.partnerID ?? "")")
                            .font(.caption2).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func apply() {
        let result = GoalPlanExecutor.apply(plan, goal: goal, context: ctx)
        applyResult = result
        applied = true
    }

    private func summaryOf(_ r: GoalPlanExecutor.ApplyResult) -> String {
        var parts: [String] = []
        if !r.modulesActivated.isEmpty {
            parts.append("\(r.modulesActivated.count) module(s) activé(s)")
        }
        if r.habitsCreated > 0 {
            parts.append("\(r.habitsCreated) habitude(s) créée(s)")
        }
        if r.habitsSkippedExisting > 0 {
            parts.append("\(r.habitsSkippedExisting) déjà présente(s)")
        }
        if r.remindersCreated > 0 {
            parts.append("\(r.remindersCreated) rappel(s) créé(s)")
        }
        if r.profileFieldsWritten > 0 {
            parts.append("\(r.profileFieldsWritten) champ(s) profil mis à jour")
        }
        return parts.isEmpty ? "Aucune action nouvelle — tout était déjà en place." : parts.joined(separator: ", ") + "."
    }

    private func scheduleLabel(_ r: ReminderTemplate) -> String {
        let freq = CustomReminder.Frequency(rawValue: r.frequencyRaw) ?? .daily
        switch freq {
        case .daily:
            return String(format: "Chaque jour à %02d:%02d", r.hour, r.minute)
        case .everyXHours:
            return "Toutes les \(r.intervalHours)h · \(r.windowStartHour)h-\(r.windowEndHour)h"
        case .multipleTimes:
            let hs = r.specificHours.map { "\($0)h" }.joined(separator: " · ")
            return hs.isEmpty ? "Horaires précis (à définir)" : hs
        }
    }
}
