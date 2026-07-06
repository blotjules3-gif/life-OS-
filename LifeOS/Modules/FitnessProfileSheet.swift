import SwiftUI
import UserNotifications

/// Sheet compact — l'utilisateur renseigne poids, taille, niveau et 1RM.
/// Ces données sont lues par le coach IA via UserContextBuilder pour calculer
/// ratios force/kg, calibrer les propositions de séance et donner du feedback pertinent.
struct FitnessProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("userWeightKg")   private var weightKg: Double = 0
    @AppStorage("userHeightCm")   private var heightCm: Double = 0
    @AppStorage("userStrengthLevel") private var levelRaw: String = "intermediaire"
    @AppStorage("userBench1RM")   private var bench1RM: Double = 0
    @AppStorage("userSquat1RM")   private var squat1RM: Double = 0
    @AppStorage("userDeadlift1RM") private var deadlift1RM: Double = 0
    @AppStorage("userTrainingYears") private var trainingYears: Int = 0
    @AppStorage("userWeeklyFrequency") private var weeklyFrequency: Int = 3
    @AppStorage("fitnessCoachIntroShown") private var coachIntroShown = false
    @State private var showResetConfirm = false
    @State private var resetDone = false

    private let levels: [(key: String, label: String, hint: String)] = [
        ("debutant",       "Débutant",       "Moins d'1 an de pratique régulière"),
        ("intermediaire",  "Intermédiaire",  "1 à 3 ans, technique maîtrisée sur les compounds"),
        ("avance",         "Avancé",         "Plus de 3 ans, périodisation, PRs solides"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    metricRow("Poids",  value: $weightKg, unit: "kg", range: 30...200, step: 0.5)
                    metricRow("Taille", value: $heightCm, unit: "cm", range: 120...220, step: 1)
                } header: {
                    Text("Anthropométrie")
                } footer: {
                    Text("Nécessaire pour calculer les ratios force/kg et adapter le volume.")
                        .font(.system(size: 11))
                }

                Section {
                    Picker("Niveau", selection: $levelRaw) {
                        ForEach(levels, id: \.key) { l in
                            Text(l.label).tag(l.key)
                        }
                    }
                    .pickerStyle(.segmented)

                    if let hint = levels.first(where: { $0.key == levelRaw })?.hint {
                        Text(hint)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Stepper(value: $trainingYears, in: 0...30) {
                        Text("Années d'entraînement : \(trainingYears)")
                            .font(.system(size: 14))
                    }
                    Stepper(value: $weeklyFrequency, in: 0...7) {
                        Text("Fréquence hebdo : \(weeklyFrequency) séance\(weeklyFrequency > 1 ? "s" : "")")
                            .font(.system(size: 14))
                    }
                } header: {
                    Text("Expérience")
                }

                Section {
                    metricRow("Bench 1RM",    value: $bench1RM,    unit: "kg", range: 0...300, step: 2.5)
                    metricRow("Squat 1RM",    value: $squat1RM,    unit: "kg", range: 0...400, step: 2.5)
                    metricRow("Deadlift 1RM", value: $deadlift1RM, unit: "kg", range: 0...500, step: 2.5)
                } header: {
                    Text("Records (1RM estimés)")
                } footer: {
                    Text("Le coach compare tes records au ratio poids de corps pour calibrer ses conseils. Laisse à 0 si tu n'as pas testé.")
                        .font(.system(size: 11))
                }

                if weightKg > 0, (bench1RM > 0 || squat1RM > 0 || deadlift1RM > 0) {
                    Section {
                        if bench1RM > 0    { ratioRow("Bench",    ratio: bench1RM    / weightKg) }
                        if squat1RM > 0    { ratioRow("Squat",    ratio: squat1RM    / weightKg) }
                        if deadlift1RM > 0 { ratioRow("Deadlift", ratio: deadlift1RM / weightKg) }
                    } header: {
                        Text("Ratios force / poids de corps")
                    }
                }

                Section {
                    Button {
                        showResetConfirm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Recommencer l'intro coach")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            if resetDone {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color(hex: 0x4CC38A))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .foregroundStyle(Color(hex: 0x9B6CF1))
                } footer: {
                    Text("Le coach relancera ses questions à ta prochaine ouverture du hub Muscu. Utile pour recalibrer un nouveau programme.")
                        .font(.system(size: 11))
                }
            }
            .confirmationDialog(
                "Relancer l'intro coach à la prochaine ouverture de Muscu ?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Relancer", role: .destructive) {
                    coachIntroShown = false
                    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["fitnessCoachIntroFollowup"])
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        resetDone = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation(.easeOut(duration: 0.3)) { resetDone = false }
                    }
                }
                Button("Annuler", role: .cancel) { }
            }
            .navigationTitle("Profil sportif")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func metricRow(_ label: String, value: Binding<Double>, unit: String, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
        }
    }

    private func ratioRow(_ label: String, ratio: Double) -> some View {
        let tier = ratioTier(label: label, ratio: ratio)
        return HStack {
            Text(label)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            Text(String(format: "×%.2f", ratio))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.primary)
            Text(tier)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color(for: tier), in: Capsule())
        }
    }

    private func ratioTier(label: String, ratio: Double) -> String {
        // Barèmes indicatifs (adulte homme non compétiteur — ordre de grandeur)
        let (novice, inter, advanced): (Double, Double, Double) = {
            switch label {
            case "Bench":    return (0.75, 1.25, 1.75)
            case "Squat":    return (1.00, 1.75, 2.25)
            case "Deadlift": return (1.25, 2.00, 2.75)
            default:         return (1.0, 1.5, 2.0)
            }
        }()
        if ratio >= advanced { return "Avancé" }
        if ratio >= inter    { return "Intermédiaire" }
        if ratio >= novice   { return "Novice" }
        return "Débutant"
    }

    private func color(for tier: String) -> Color {
        switch tier {
        case "Avancé":        return Color(hex: 0x9B6CF1)
        case "Intermédiaire": return Color(hex: 0x4CC38A)
        case "Novice":        return Color(hex: 0xE0A23C)
        default:              return Color.secondary
        }
    }
}
