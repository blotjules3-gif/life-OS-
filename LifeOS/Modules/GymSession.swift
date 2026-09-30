import SwiftUI
import SwiftData

// MARK: - Seance du jour : le programme, la charge conseillee, et le journal

/// Ouvre la seance prevue par le programme, donne pour chaque exercice la charge de la
/// prochaine seance (StrengthProgression), et loggue chaque serie dans le MEME journal
/// que Hevvy. C'est ce journal qui fera avancer les charges la semaine suivante.
struct GymSessionView: View {
    @Bindable var day: GymDay
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSet.date, order: .reverse) private var sets: [WorkoutSet]
    @AppStorage(AppStorageKeys.userBench1RM) private var bench1RM: Double = 0
    @AppStorage(AppStorageKeys.userSquat1RM) private var squat1RM: Double = 0
    @AppStorage(AppStorageKeys.userDeadlift1RM) private var deadlift1RM: Double = 0

    private var exercises: [String] {
        day.focus.split(separator: "·").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var logged: [StrengthProgression.LoggedSet] { sets.map(\.logged) }

    var body: some View {
        List {
            if exercises.isEmpty {
                Text("Aucun exercice dans cette séance. Ajoute-les dans le programme.").foregroundStyle(.secondary)
            }
            recoverySection
            ForEach(exercises, id: \.self) { label in
                ExerciseBlock(label: label,
                              prescription: prescription(for: label),
                              today: todaySets(for: label),
                              onLog: { w, r, rpe in log(label, w, r, rpe) },
                              onDelete: { ctx.delete($0) })
            }
        }
        .navigationTitle(day.title.isEmpty ? "Séance" : day.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Groupes de la seance travailles il y a moins de 48 h : on le dit, sans bloquer.
    @ViewBuilder private var recoverySection: some View {
        let groups = Array(Set(exercises.compactMap { GymExercises.group(of: $0) })).sorted()
        let tired = groups.compactMap { g -> (String, Int)? in
            guard let h = StrengthProgression.hoursSince(group: g, in: logged.filter { !Calendar.current.isDateInToday($0.date) }),
                  h < 48 else { return nil }
            return (g, Int(h))
        }
        if !tired.isEmpty {
            Section {
                ForEach(tired, id: \.0) { g, h in
                    Label("\(g) travaillés il y a \(h) h : récupération incomplète, reste léger.", systemImage: "bed.double.fill")
                        .font(.footnote)
                }
            }
        }
    }

    private func prescription(for label: String) -> StrengthProgression.Prescription? {
        guard GymExercises.group(of: label) != "Cardio",
              let target = StrengthProgression.target(from: label) else { return nil }
        return StrengthProgression.next(exercise: label, target: target, history: logged, profile1RM: profile1RM(label))
    }

    private func profile1RM(_ label: String) -> Double? {
        let n = StrengthProgression.normalized(label)
        if n.hasPrefix("developpe couche") { return bench1RM > 0 ? bench1RM : nil }
        if n.hasPrefix("squat") { return squat1RM > 0 ? squat1RM : nil }
        if n.hasPrefix("souleve de terre") && !n.contains("roumain") { return deadlift1RM > 0 ? deadlift1RM : nil }
        return nil
    }

    private func todaySets(for label: String) -> [WorkoutSet] {
        let key = StrengthProgression.normalized(label)
        return sets.filter { Calendar.current.isDateInToday($0.date) && StrengthProgression.normalized($0.exercise) == key }
            .sorted { $0.date < $1.date }
    }

    private func log(_ label: String, _ weight: Double, _ reps: Int, _ rpe: Double) {
        ctx.insert(WorkoutSet(exercise: GymExercises.baseName(label), weightKg: weight, reps: reps, rpe: rpe))
        try? ctx.save()
        Haptics.success()
    }
}

private struct ExerciseBlock: View {
    let label: String
    let prescription: StrengthProgression.Prescription?
    let today: [WorkoutSet]
    let onLog: (Double, Int, Double) -> Void
    let onDelete: (WorkoutSet) -> Void

    @State private var weight = ""
    @State private var reps = 0
    @State private var rpe = 8.0

    var body: some View {
        Section {
            if let p = prescription {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.weight.map { "\(p.sets) × \(p.reps) à \(StrengthProgression.fmt($0)) kg" } ?? "\(p.sets) × \(p.reps)")
                        .font(.headline)
                    Text(p.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(today.enumerated()), id: \.element.id) { i, s in
                HStack {
                    Text("Série \(i + 1)")
                    Spacer()
                    Text("\(StrengthProgression.fmt(s.weightKg)) kg × \(s.reps) · effort \(Int(s.rpe))").foregroundStyle(.secondary)
                }
                .swipeActions { Button(role: .destructive) { onDelete(s) } label: { Label("Supprimer", systemImage: "trash") } }
            }
            if prescription != nil {
                HStack(spacing: 8) {
                    TextField("kg", text: $weight).keyboardType(.decimalPad).frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                    Stepper("\(reps) reps", value: $reps, in: 0...50).fixedSize()
                }
                Picker("Effort ressenti", selection: $rpe) {
                    ForEach([6.0, 7, 8, 9, 10], id: \.self) { Text("\(Int($0))/10").tag($0) }
                }
                .pickerStyle(.segmented)
                Button {
                    guard let w = Double(weight.replacingOccurrences(of: ",", with: ".")), w >= 0, reps > 0 else { return }
                    onLog(w, reps, rpe)
                } label: { Label("Valider la série", systemImage: "checkmark.circle.fill") }
                .disabled(Double(weight.replacingOccurrences(of: ",", with: ".")) == nil || reps == 0)
            }
        } header: {
            Text(GymExercises.baseName(label))
        }
        .onAppear {
            if weight.isEmpty, let w = today.last?.weightKg ?? prescription?.weight { weight = StrengthProgression.fmt(w) }
            if reps == 0 { reps = today.last?.reps ?? prescription?.reps ?? 0 }
        }
    }
}

// MARK: - Volume de la semaine

/// Series difficiles par groupe sur 7 jours, avec le repere 10 a 20.
struct GymWeeklyVolumeView: View {
    let sets: [WorkoutSet]
    var body: some View {
        let vol = StrengthProgression.weeklyHardSets(sets.map(\.logged))
        let groups = GymExercises.catalog.keys.filter { $0 != "Cardio" }.sorted()
        ForEach(groups, id: \.self) { g in
            let n = vol[g, default: 0]
            HStack {
                Text(g)
                Spacer()
                Text("\(n) série\(n > 1 ? "s" : "")")
                    .foregroundStyle(n == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                Image(systemName: n >= 10 && n <= 20 ? "checkmark.circle.fill" : (n > 20 ? "exclamationmark.circle" : "circle"))
                    .foregroundStyle(n >= 10 && n <= 20 ? Theme.success : (n > 20 ? Theme.warning : Color.secondary))
                    .accessibilityLabel(n >= 10 && n <= 20 ? "dans la cible" : (n > 20 ? "au-dessus de la cible" : "sous la cible"))
            }
        }
    }
}
