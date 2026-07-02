import SwiftUI

struct GoalEditorSheet: View {

    @Binding var stepGoal: Int
    @Binding var waterGoal: Int
    @Binding var kcalGoal: Int
    @Binding var proteinGoal: Int
    @Binding var fastTarget: Int
    @Binding var budgetGoal: Int
    @Binding var glassesGoal: Int
    @Binding var focusMinGoal: Int
    @Binding var socialMaxMin: Int
    @Binding var hiddenGoalIDsRaw: String
    @Binding var goalEndDatesRaw: String

    @Environment(\.dismiss) private var dismiss
    @State private var endDates: [String: Date] = [:]
    @State private var expandedID: String? = nil

    struct GoalDef: Identifiable {
        let id: String
        let title: String
        let icon: String
        let colorHex: UInt
        let section: String
    }

    private let catalog: [GoalDef] = [
        GoalDef(id: "steps",   title: "Pas quotidiens",     icon: "figure.run",          colorHex: 0x4CC38A, section: "Activité"),
        GoalDef(id: "glasses", title: "Verres d'eau",        icon: "cup.and.saucer.fill", colorHex: 0x3CB2E0, section: "Nutrition"),
        GoalDef(id: "water",   title: "Volume eau",           icon: "drop.fill",           colorHex: 0x3CB2E0, section: "Nutrition"),
        GoalDef(id: "kcal",    title: "Calories",             icon: "flame.fill",          colorHex: 0xF1746C, section: "Nutrition"),
        GoalDef(id: "protein", title: "Protéines",            icon: "fork.knife",          colorHex: 0xE0A23C, section: "Nutrition"),
        GoalDef(id: "fast",    title: "Jeûne intermittent",   icon: "clock",               colorHex: 0x5DCFA8, section: "Nutrition"),
        GoalDef(id: "focus",   title: "Temps de focus",       icon: "brain.head.profile",  colorHex: 0x9B6CF1, section: "Focus"),
        GoalDef(id: "social",  title: "Réseaux sociaux max",  icon: "iphone.slash",        colorHex: 0xE05A7A, section: "Focus"),
        GoalDef(id: "budget",  title: "Budget mensuel",       icon: "creditcard.fill",     colorHex: 0x618EF1, section: "Finances"),
    ]

    private var hiddenIDs: Set<String> {
        Set(hiddenGoalIDsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }
    private var active: [GoalDef] { catalog.filter { !hiddenIDs.contains($0.id) } }
    private var inactive: [GoalDef] { catalog.filter { hiddenIDs.contains($0.id) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(active) { goal in goalRow(goal) }
                        .onDelete { idx in
                            var hidden = hiddenIDs
                            idx.map { active[$0].id }.forEach { hidden.insert($0) }
                            hiddenGoalIDsRaw = hidden.joined(separator: ",")
                        }
                } header: {
                    Text("Objectifs actifs")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(nil)
                } footer: {
                    Text("Glissez vers la gauche pour retirer un objectif.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }

                if !inactive.isEmpty {
                    Section {
                        ForEach(inactive) { goal in addRow(goal) }
                    } header: {
                        Text("Ajouter un objectif")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Mes objectifs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { persistEndDates(); dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { endDates = loadEndDates() }
        }
    }

    @ViewBuilder
    private func goalRow(_ goal: GoalDef) -> some View {
        let color = Color(hex: goal.colorHex)
        let isExpanded = expandedID == goal.id
        let endDate = endDates[goal.id]
        let expired = endDate.map { $0 < .now } ?? false

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    if let d = endDate {
                        Text(expired ? "Expiré" : "Jusqu'au \(d.formatted(.dateTime.day().month(.abbreviated)))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(expired ? Color(hex: 0xF1746C) : color.opacity(0.8))
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(valueText(for: goal.id))
                        .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(expired ? Color(hex: 0xF1746C) : color)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.25, bounce: 0.1), value: valueText(for: goal.id))
                    stepperView(for: goal.id)
                }

                Button {
                    withAnimation(.spring(duration: 0.28, bounce: 0.2)) {
                        expandedID = isExpanded ? nil : goal.id
                    }
                } label: {
                    Image(systemName: isExpanded ? "calendar.badge.minus" : "calendar.badge.plus")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isExpanded ? color : .secondary)
                        .frame(width: 44, height: 44)
                        .background(
                            isExpanded ? color.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                }
                .buttonStyle(LifeOSPressStyle())
            }
            .padding(.vertical, 6)

            if isExpanded {
                Divider().padding(.top, 8)
                datePicker(for: goal.id, color: color)
                    .padding(.bottom, 8)
            }
        }
        .animation(.spring(duration: 0.28, bounce: 0.15), value: isExpanded)
    }

    @ViewBuilder
    private func datePicker(for id: String, color: Color) -> some View {
        let presets: [(label: String, days: Int)] = [
            ("1 sem", 7), ("2 sem", 14), ("1 mois", 30), ("3 mois", 90)
        ]
        VStack(alignment: .leading, spacing: 12) {
            Text("Durée de l'objectif")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.days) { preset in
                        let target = Calendar.current.date(byAdding: .day, value: preset.days, to: .now) ?? Date(timeIntervalSinceNow: TimeInterval(preset.days * 86400))
                        let selected = matchesPreset(endDates[id], days: preset.days)
                        Button {
                            withAnimation(.spring(duration: 0.38, bounce: 0.1)) { endDates[id] = target }
                        } label: {
                            Text(preset.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? .white : color)
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(selected ? color : color.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(LifeOSPressStyle())
                    }

                    let noLimit = endDates[id] == nil
                    Button {
                        withAnimation(.spring(duration: 0.38, bounce: 0.1)) { _ = endDates.removeValue(forKey: id) }
                    } label: {
                        Text("Sans limite")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(noLimit ? .white : .secondary)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(noLimit ? Color.secondary : Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
                .padding(.horizontal, 2)
            }

            if endDates[id] != nil {
                DatePicker(
                    "Date précise",
                    selection: Binding(
                        get: { endDates[id] ?? Calendar.current.date(byAdding: .day, value: 7, to: .now)! },
                        set: { endDates[id] = $0 }
                    ),
                    in: Calendar.current.date(byAdding: .day, value: 1, to: .now)!...,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .tint(color)
            }
        }
    }

    @ViewBuilder
    private func addRow(_ goal: GoalDef) -> some View {
        let color = Color(hex: goal.colorHex)
        Button {
            var hidden = hiddenIDs
            hidden.remove(goal.id)
            hiddenGoalIDsRaw = hidden.joined(separator: ",")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(goal.title).font(.system(size: 14)).foregroundStyle(.primary)
                    Text(goal.section).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(color)
            }
        }
        .buttonStyle(LifeOSPressStyle())
    }

    @ViewBuilder
    private func stepperView(for id: String) -> some View {
        switch id {
        case "steps":   customStepper(value: $stepGoal,    min: 1000,  max: 30000, step: 500)
        case "water":   customStepper(value: $waterGoal,   min: 500,   max: 5000,  step: 250)
        case "kcal":    customStepper(value: $kcalGoal,    min: 1000,  max: 5000,  step: 50)
        case "protein": customStepper(value: $proteinGoal, min: 30,    max: 300,   step: 5)
        case "fast":    customStepper(value: $fastTarget,  min: 12,    max: 24,    step: 1)
        case "budget":  customStepper(value: $budgetGoal,  min: 100,   max: 20000, step: 50)
        case "glasses": customStepper(value: $glassesGoal, min: 1,     max: 20,    step: 1)
        case "focus":   customStepper(value: $focusMinGoal,min: 15,    max: 480,   step: 15)
        case "social":  customStepper(value: $socialMaxMin,min: 5,     max: 300,   step: 5)
        default:        EmptyView()
        }
    }

    private func customStepper(value: Binding<Int>, min: Int, max: Int, step: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                if value.wrappedValue - step >= min {
                    value.wrappedValue -= step
                    Haptics.tap()
                }
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue - step >= min ? .primary : .tertiary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())

            Button {
                if value.wrappedValue + step <= max {
                    value.wrappedValue += step
                    Haptics.tap()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(value.wrappedValue + step <= max ? .primary : .tertiary)
                    .frame(width: 44, height: 44)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(LifeOSPressStyle())
        }
    }

    private func valueText(for id: String) -> String {
        switch id {
        case "steps":   return "\(stepGoal) pas"
        case "water":   return "\(waterGoal) ml"
        case "kcal":    return "\(kcalGoal) kcal"
        case "protein": return "\(proteinGoal) g"
        case "fast":    return "\(fastTarget) h"
        case "budget":  return "\(budgetGoal) €"
        case "glasses": return "\(glassesGoal) verres/j"
        case "focus":   return "\(focusMinGoal) min/j"
        case "social":  return "\(socialMaxMin) min max"
        default:        return ""
        }
    }

    private func matchesPreset(_ date: Date?, days: Int) -> Bool {
        guard let d = date else { return false }
        let diff = d.timeIntervalSince(.now) / 86400
        return abs(diff - Double(days)) < 1.0
    }

    private func loadEndDates() -> [String: Date] {
        guard let data = goalEndDatesRaw.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Double].self, from: data) else { return [:] }
        return dict.compactMapValues { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }

    private func persistEndDates() {
        let dict = endDates.mapValues { $0.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(dict),
           let str = String(data: data, encoding: .utf8) {
            goalEndDatesRaw = str
        }
    }
}
