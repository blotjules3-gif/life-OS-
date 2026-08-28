import SwiftData
import SwiftUI

/// Écran "Mes objectifs" — liste tous les `UserGoal` actifs/paused/atteints
/// avec progression + actions (pause / marquer atteint / archiver).
///
/// Loop 25 audit — comblait le trou UX critique : user créait un plan puis
/// perdait la trace de son objectif.
struct MyGoalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query(sort: \UserGoal.updatedAt, order: .reverse) private var goals: [UserGoal]

    var body: some View {
        NavigationStack {
            List {
                if goals.isEmpty {
                    emptyState
                } else {
                    activeSection
                    if !archivedGoals.isEmpty { archivedSection }
                }
            }
            .navigationTitle("Mes objectifs")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private var activeGoals: [UserGoal] {
        goals.filter { $0.status == .active || $0.status == .paused }
    }

    private var archivedGoals: [UserGoal] {
        goals.filter { $0.status == .achieved || $0.status == .abandoned }
    }

    // MARK: - Sections

    @ViewBuilder
    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "target")
                    .font(.largeTitle)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 20)
                Text("Aucun objectif encore")
                    .font(.headline)
                Text("Ouvre le chat coach et dis-lui ce que tu veux accomplir. Il te proposera un plan complet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var activeSection: some View {
        Section("En cours") {
            ForEach(activeGoals) { goal in
                goalRow(goal)
            }
        }
    }

    private var archivedSection: some View {
        Section("Terminés") {
            ForEach(archivedGoals) { goal in
                goalRow(goal, isArchived: true)
            }
        }
    }

    // MARK: - Row

    private func goalRow(_ goal: UserGoal, isArchived: Bool = false) -> some View {
        let progress = GoalProgressCalculator.progress(for: goal, context: ctx)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: goal.kind.icon)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isArchived ? .secondary : .primary)
                    if !goal.appliedPlanSummary.isEmpty {
                        Text(goal.appliedPlanSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                statusBadge(goal.status)
            }

            if let progress {
                ProgressView(value: progress.ratio)
                    .tint(progress.ratio >= 1 ? .green : Color.accentColor)
                Text(progress.label)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if !isArchived {
                actionsRow(goal)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(_ status: GoalStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .active:    return ("Actif", .green)
            case .paused:    return ("En pause", .orange)
            case .achieved:  return ("Atteint", .blue)
            case .abandoned: return ("Abandonné", .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private func actionsRow(_ goal: UserGoal) -> some View {
        HStack(spacing: 8) {
            if goal.status == .active {
                Button("Pause") { goal.status = .paused; try? ctx.save() }
                    .buttonStyle(.bordered).controlSize(.mini)
            } else if goal.status == .paused {
                Button("Réactiver") { goal.status = .active; try? ctx.save() }
                    .buttonStyle(.bordered).controlSize(.mini)
            }
            Button("Atteint") { goal.status = .achieved; try? ctx.save() }
                .buttonStyle(.bordered).controlSize(.mini)
                .tint(.blue)
            Button(role: .destructive) {
                archive(goal)
            } label: {
                Text("Abandonner")
            }
            .buttonStyle(.bordered).controlSize(.mini)
        }
    }

    /// Marque l'objectif abandonné + archive les habits sourceGoalID matchant.
    /// Ne supprime pas les habits (l'user peut vouloir les garder manuellement).
    private func archive(_ goal: UserGoal) {
        goal.status = .abandoned
        let goalID = goal.id.uuidString
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>(
            predicate: #Predicate { $0.sourceGoalID == goalID }
        ))) ?? []
        for h in habits { h.isArchived = true }
        // Les CustomReminder liés sont cancel via SmartReminderScheduler
        let reminders = (try? ctx.fetch(FetchDescriptor<CustomReminder>(
            predicate: #Predicate { $0.sourceGoalID == goalID }
        ))) ?? []
        for r in reminders {
            r.enabled = false
            SmartReminderScheduler.cancel(r)
        }
        try? ctx.save()
    }
}
