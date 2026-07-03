import SwiftUI
import SwiftData
import Combine

// MARK: - Modèle de séance planifiée (parsée depuis GymDay.focus)

struct PlannedExercise: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let sets: Int
    let reps: Int
}

struct WorkoutPlan: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let exercises: [PlannedExercise]
}

enum WorkoutParser {
    /// "Squat barre 4×10 · Presse à cuisses 4×10" → [PlannedExercise]
    static func exercises(from focus: String) -> [PlannedExercise] {
        focus.split(separator: "·").compactMap { part in
            let raw = part.trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }
            return parse(raw)
        }
    }

    static func parse(_ raw: String) -> PlannedExercise {
        let pattern = "([0-9]{1,2})\\s*[×xX*]\\s*([0-9]{1,3})"
        if let re = try? NSRegularExpression(pattern: pattern),
           let m = re.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
           let setsR = Range(m.range(at: 1), in: raw), let repsR = Range(m.range(at: 2), in: raw),
           let full = Range(m.range, in: raw) {
            let sets = Int(raw[setsR]) ?? 3
            let reps = Int(raw[repsR]) ?? 10
            var name = raw
            name.removeSubrange(full)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ·-–—()"))
            return PlannedExercise(name: name.isEmpty ? raw : name, sets: max(1, sets), reps: max(1, reps))
        }
        return PlannedExercise(name: raw, sets: 3, reps: 10)
    }
}

// MARK: - Séance guidée

struct GuidedWorkoutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @Query private var gymDays: [GymDay]
    @Query(sort: \WorkoutSet.date, order: .reverse) private var history: [WorkoutSet]

    @AppStorage("gwRestSecs") private var restDuration = 90

    @State private var plan: WorkoutPlan?
    @State private var exIndex = 0
    @State private var setNumber = 1
    @State private var weight = ""
    @State private var reps = ""
    @State private var logged: [WorkoutSet] = []
    @State private var resting = false
    @State private var restRemaining = 0
    @State private var finished = false
    @State private var lastWasPR = false

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var availablePlans: [WorkoutPlan] {
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.compactMap { w -> WorkoutPlan? in
            guard let d = gymDays.first(where: { $0.weekday == w && !$0.isRest && !$0.title.isEmpty }) else { return nil }
            let exos = WorkoutParser.exercises(from: d.focus)
            guard !exos.isEmpty else { return nil }
            return WorkoutPlan(title: d.title, subtitle: weekdayName(w), exercises: exos)
        }
    }

    private var todayPlan: WorkoutPlan? {
        let w = Calendar.current.component(.weekday, from: .now)
        guard let d = gymDays.first(where: { $0.weekday == w && !$0.isRest && !$0.title.isEmpty }) else { return nil }
        let exos = WorkoutParser.exercises(from: d.focus)
        guard !exos.isEmpty else { return nil }
        return WorkoutPlan(title: d.title, subtitle: "Aujourd'hui", exercises: exos)
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if finished {
                summary
            } else if let plan {
                session(plan)
            } else {
                chooser
            }
            if resting { restOverlay.transition(.opacity) }
        }
        .navigationTitle("Séance guidée").navigationBarTitleDisplayMode(.inline)
        .onAppear { if plan == nil { plan = todayPlan; if plan != nil { loadExercise() } } }
        .onReceive(tick) { _ in
            guard resting else { return }
            if restRemaining > 1 { restRemaining -= 1 }
            else { endRest() }
        }
        .animation(.easeInOut(duration: 0.2), value: resting)
        .animation(.easeInOut(duration: 0.25), value: finished)
    }

    // MARK: Choix de séance

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Choisis ta séance").nikeTitle(24).padding(.top, 8)
                if availablePlans.isEmpty {
                    EmptyState(icon: "dumbbell", title: "Aucun programme",
                               message: "Configure tes jours de sport dans Sport → programme, puis reviens ici.")
                } else {
                    ForEach(availablePlans) { p in
                        Button { plan = p; loadExercise() } label: { planCard(p) }
                            .buttonStyle(PressableButtonStyle())
                    }
                }
            }
            .padding(Theme.pad)
        }
    }

    private func planCard(_ p: WorkoutPlan) -> some View {
        HStack(spacing: 14) {
            IconBadge(icon: "dumbbell.fill", size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.title).font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(p.subtitle).font(.caption2.weight(.bold)).foregroundStyle(Theme.onVolt)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.volt, in: Capsule())
                }
                Text("\(p.exercises.count) exercices · \(p.exercises.map(\.name).joined(separator: ", "))")
                    .font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(Theme.textSecondary.opacity(0.5))
        }
        .card(padding: 14)
    }

    // MARK: Flux guidé

    private var currentExercise: PlannedExercise? {
        guard let plan, exIndex < plan.exercises.count else { return nil }
        return plan.exercises[exIndex]
    }

    private func session(_ plan: WorkoutPlan) -> some View {
        let ex = plan.exercises[min(exIndex, plan.exercises.count - 1)]
        let last = lastSet(ex.name)
        let pr = prWeight(ex.name)
        return ScrollView {
            VStack(spacing: 18) {
                // progression séance
                VStack(spacing: 8) {
                    HStack {
                        Text("EXERCICE \(exIndex + 1)/\(plan.exercises.count)")
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(plan.title.uppercased()).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.volt)
                    }
                    ProgressView(value: sessionProgress).tint(Theme.volt)
                }

                // carte exercice
                VStack(spacing: 10) {
                    Text(ex.name).font(.system(size: 26, weight: .black)).multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary).minimumScaleFactor(0.6).lineLimit(2)
                    Text("SÉRIE \(setNumber) / \(ex.sets) · OBJECTIF \(ex.reps) REPS")
                        .font(.system(size: 13, weight: .heavy)).kerning(0.5).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 10) {
                        if let last {
                            refPill("DERNIÈRE FOIS", "\(fmt(last.weightKg))kg × \(last.reps)")
                        }
                        if pr > 0 { refPill("RECORD", "\(fmt(pr))kg", accent: true) }
                    }
                    // pastilles séries faites
                    HStack(spacing: 6) {
                        ForEach(0..<ex.sets, id: \.self) { i in
                            Circle().fill(i < setNumber - 1 ? Theme.volt : Theme.textSecondary.opacity(0.2))
                                .frame(width: 9, height: 9)
                        }
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 20)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                // saisie charge + reps
                HStack(spacing: 12) {
                    valueBox("CHARGE", unit: "kg", text: $weight, step: 2.5, decimal: true)
                    valueBox("REPS", unit: "", text: $reps, step: 1, decimal: false)
                }

                Button { validateSet(ex) } label: {
                    Text(setNumber < ex.sets ? "Valider la série" :
                            (exIndex < plan.exercises.count - 1 ? "Exercice suivant" : "Terminer la séance"))
                        .font(.system(size: 17, weight: .black)).foregroundStyle(Theme.onVolt)
                        .frame(maxWidth: .infinity).padding(.vertical, 17)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled((Double(reps) ?? 0) <= 0)

                if !logged.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Séries loggées (\(logged.count))").font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(logged.reversed()) { s in
                            HStack {
                                Text(s.exercise).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Spacer()
                                Text("\(fmt(s.weightKg))kg × \(s.reps)").font(.subheadline.bold()).foregroundStyle(.fitTint)
                            }
                            .padding(.vertical, 4)
                        }
                    }.card(padding: 14)
                }

                Button(role: .destructive) { finished = true } label: {
                    Text("Terminer maintenant").font(.subheadline.weight(.semibold))
                }.padding(.top, 4)
            }
            .padding(Theme.pad)
        }
    }

    private func refPill(_ label: String, _ value: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.system(size: 15, weight: .black)).foregroundStyle(accent ? Theme.volt : Theme.textPrimary)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func valueBox(_ label: String, unit: String, text: Binding<String>, step: Double, decimal: Bool) -> some View {
        VStack(spacing: 10) {
            Text(label).font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.textSecondary)
            HStack {
                TextField("0", text: text)
                    .keyboardType(decimal ? .decimalPad : .numberPad)
                    .font(.system(size: 34, weight: .black, design: .rounded)).monospacedDigit()
                    .multilineTextAlignment(.center).foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty { Text(unit).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textSecondary) }
            }
            HStack(spacing: 10) {
                stepBtn("minus") { adjust(text, -step, decimal) }
                stepBtn("plus") { adjust(text, step, decimal) }
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stepBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Image(systemName: icon).font(.system(size: 15, weight: .black)).foregroundStyle(Theme.textPrimary)
                .frame(width: 42, height: 34).background(Theme.textPrimary.opacity(0.08), in: Capsule())
        }
    }

    // MARK: Repos

    private var restOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 24) {
                Text("REPOS").font(.system(size: 16, weight: .heavy)).kerning(3).foregroundStyle(.white.opacity(0.7))
                Text(formatHMS(restRemaining))
                    .font(.system(size: 88, weight: .black, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                if lastWasPR {
                    Label("Nouveau record 💪", systemImage: "trophy.fill")
                        .font(.headline.bold()).foregroundStyle(Theme.volt)
                }
                Text("Prochaine : \(nextSetLabel)").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 14) {
                    restBtn("−15s") { restRemaining = max(1, restRemaining - 15) }
                    restBtn("+15s") { restRemaining += 15 }
                }
                Button { endRest() } label: {
                    Text("Passer le repos").font(.system(size: 16, weight: .black)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 40).padding(.top, 6)
            }
            .padding(30)
        }
    }

    private func restBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            Text(label).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(.white.opacity(0.14), in: Capsule())
        }
    }

    private var nextSetLabel: String {
        guard let ex = currentExercise else { return "" }
        if setNumber <= ex.sets { return "\(ex.name) · série \(setNumber)/\(ex.sets)" }
        return "exercice suivant"
    }

    // MARK: Résumé

    private var summary: some View {
        let volume = logged.reduce(0.0) { $0 + $1.volume }
        let mins = max(1, Int(Date().timeIntervalSince(logged.first?.date ?? .now) / 60) + 1)
        return ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(Theme.volt).padding(.top, 20)
                Text("Séance terminée").nikeTitle(26)
                HStack(spacing: 12) {
                    summaryStat("\(logged.count)", "SÉRIES")
                    summaryStat("\(Int(volume))", "KG VOLUME")
                    summaryStat("\(mins)", "MINUTES")
                }
                if logged.isEmpty {
                    Text("Aucune série loggée.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Button { dismiss() } label: {
                    Text("Terminer").font(.system(size: 17, weight: .black)).foregroundStyle(Theme.onVolt)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(Theme.volt, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }.padding(.top, 8)
            }
            .padding(Theme.pad)
        }
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(label).font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: Logique

    private var sessionProgress: Double {
        guard let plan, !plan.exercises.isEmpty else { return 0 }
        let totalSets = plan.exercises.reduce(0) { $0 + $1.sets }
        let done = plan.exercises.prefix(exIndex).reduce(0) { $0 + $1.sets } + (setNumber - 1)
        return Double(done) / Double(max(1, totalSets))
    }

    private func validateSet(_ ex: PlannedExercise) {
        let w = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        let r = Int(reps) ?? 0
        guard r > 0 else { return }
        lastWasPR = w > 0 && w > prWeight(ex.name)
        let set = WorkoutSet(exercise: ex.name, weightKg: w, reps: r, rpe: 8)
        ctx.insert(set); logged.append(set)
        Haptics.success()

        guard let plan else { return }
        if setNumber < ex.sets {
            setNumber += 1
            startRest()
        } else if exIndex < plan.exercises.count - 1 {
            exIndex += 1; setNumber = 1; loadExercise(); startRest()
        } else {
            finished = true
        }
    }

    private func startRest() {
        guard restDuration > 0 else { return }
        restRemaining = restDuration; resting = true
    }
    private func endRest() { resting = false; lastWasPR = false }

    private func loadExercise() {
        guard let ex = currentExercise else { return }
        if let last = lastSet(ex.name) {
            weight = fmt(last.weightKg); reps = "\(last.reps)"
        } else {
            weight = ""; reps = "\(ex.reps)"
        }
    }

    private func lastSet(_ name: String) -> WorkoutSet? {
        history.first { $0.exercise.caseInsensitiveCompare(name) == .orderedSame }
    }
    private func prWeight(_ name: String) -> Double {
        history.filter { $0.exercise.caseInsensitiveCompare(name) == .orderedSame }.map(\.weightKg).max() ?? 0
    }

    private func adjust(_ text: Binding<String>, _ delta: Double, _ decimal: Bool) {
        let cur = Double(text.wrappedValue.replacingOccurrences(of: ",", with: ".")) ?? 0
        let next = max(0, cur + delta)
        text.wrappedValue = decimal ? fmt(next) : "\(Int(next))"
    }

    private func fmt(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))" : String(format: "%.1f", v)
    }

    private func weekdayName(_ w: Int) -> String {
        ["", "Dimanche", "Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi"][w]
    }
}
