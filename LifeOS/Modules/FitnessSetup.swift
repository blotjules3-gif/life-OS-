import SwiftUI
import SwiftData

// MARK: - Formulaire de configuration « Sport & fitness »
// Pré-remplit : programme hebdo (séances réparties), rappels muscu, défaut Tabata.

struct FitnessSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var gymDays: [GymDay]

    @AppStorage("gymReminderOn")    private var gymOn = true
    @AppStorage("gymReminderHour")  private var gymHour = 7
    @AppStorage("tabataWork")       private var tabataWork = 40
    @AppStorage("tabataRest")       private var tabataRest = 20
    @AppStorage("userGender")       private var userGender = ""     // déjà connu (onboarding)
    @AppStorage("userGoalFit")      private var userGoalFit = ""    // réutilisé par d'autres catégories

    @State private var goal = "Prise de muscle"
    @State private var level = "Intermédiaire"
    @State private var freq = "4 jours"
    @State private var place = "Salle"
    @State private var emphasis: Set<String> = []

    private let tint = AppCategory.fitness.tint
    private var isFemme: Bool { userGender == "femme" }

    var body: some View {
        SetupFlow(title: "Sport & fitness", accent: tint, pages: pages, onComplete: commit)
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 18) {
                    SetupHeader(icon: "figure.run", title: "On construit ton programme",
                                subtitle: "Quelques questions et ta semaine d'entraînement détaillée est prête.", accent: tint)
                    SetupChoice(options: ["Prise de muscle", "Perte de gras", "Force", "Forme générale"],
                                selection: $goal, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "chart.line.uptrend.xyaxis", title: "Ton niveau ?", accent: tint)
                    SetupChoice(options: ["Débutant", "Intermédiaire", "Avancé"], selection: $level, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "calendar", title: "Combien de séances par semaine ?", accent: tint)
                    SetupChoice(options: ["2 jours", "3 jours", "4 jours", "5 jours"], selection: $freq, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "house", title: "Où t'entraînes-tu ?", accent: tint)
                    SetupChoice(options: ["Salle", "Maison", "Les deux"], selection: $place, accent: tint,
                                icons: ["dumbbell.fill", "house.fill", "figure.run"])
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "scope", title: "Des muscles à prioriser ?",
                                subtitle: "Optionnel — on ajoutera du volume dessus.", accent: tint)
                    SetupMultiChoice(options: ["Pecs", "Dos", "Épaules", "Bras", "Jambes", "Fessiers", "Abdos"],
                                     selection: $emphasis, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "checkmark.seal.fill", title: "Ton programme détaillé",
                                subtitle: "Exercices + machines + séries×reps, répartis sur la semaine. Modifiable à tout moment.", accent: tint)
                    programPreview
                }
            }
        ]
    }

    // MARK: génération du split

    private var daysPerWeek: Int { Int(freq.prefix(1)) ?? 4 }

    /// Titres des séances (jours d'entraînement) selon objectif/fréquence.
    private var sessionTitles: [String] {
        switch daysPerWeek {
        case 2:
            return ["Full body A", "Full body B"]
        case 3:
            if goal == "Force" { return ["Squat focus", "Bench focus", "Deadlift focus"] }
            return ["Push", "Pull", "Legs"]
        case 4:
            return ["Haut du corps A", "Bas du corps A", "Haut du corps B", "Bas du corps B"]
        default:
            return ["Pecs + Triceps", "Dos + Biceps", "Jambes", "Épaules + Abdos", "Full / Faiblesses"]
        }
    }

    /// (titre, détail) avec exercices réels issus de GymExercises.
    private var sessions: [(String, String)] {
        sessionTitles.map { ($0, GymExercises.focus(for: $0, goal: goal)) }
    }

    /// Map les séances sur les jours de la semaine (lun→dim), le reste = repos.
    private var weekPlan: [(weekday: Int, title: String, focus: String, rest: Bool)] {
        // Jours d'entraînement choisis selon la fréquence (indices dans gymWeekOrder lun..dim)
        let trainIdx: [Int]
        switch daysPerWeek {
        case 2: trainIdx = [0, 3]            // lun, jeu
        case 3: trainIdx = [0, 2, 4]         // lun, mer, ven
        case 4: trainIdx = [0, 1, 3, 4]      // lun, mar, jeu, ven
        default: trainIdx = [0, 1, 2, 3, 4]  // lun→ven
        }
        var s = 0
        return gymWeekOrder.enumerated().map { i, wd in
            if let pos = trainIdx.firstIndex(of: i) {
                let sess = sessions[min(pos, sessions.count - 1)]
                s += 1
                return (wd, sess.0, sess.1, false)
            }
            return (wd, "Repos", "Récupération · marche · étirements", true)
        }
    }

    private var programPreview: some View {
        VStack(spacing: 8) {
            ForEach(weekPlan, id: \.weekday) { p in
                HStack(spacing: 12) {
                    Text(gymWeekdayName(p.weekday)).font(.subheadline.weight(.semibold))
                        .foregroundStyle(p.rest ? Theme.textSecondary : Theme.textPrimary).frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.title).font(.subheadline.weight(.semibold))
                            .foregroundStyle(p.rest ? Theme.textSecondary : tint)
                        if !p.rest {
                            Text(p.focus.replacingOccurrences(of: " · ", with: "\n"))
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10).padding(.horizontal, 12)
                .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: enregistrement

    private func commit() {
        userGoalFit = goal
        // Efface l'ancien programme et réécrit le nouveau.
        for d in gymDays { ctx.delete(d) }
        for p in weekPlan {
            var focus = p.focus
            // Volume supplémentaire sur les muscles priorisés.
            if !p.rest, !emphasis.isEmpty {
                focus = addEmphasis(to: focus, title: p.title)
            }
            ctx.insert(GymDay(weekday: p.weekday, title: p.title, focus: focus, isRest: p.rest))
        }
        // Défauts Tabata selon le niveau.
        tabataWork = level == "Débutant" ? 30 : (level == "Avancé" ? 45 : 40)
        tabataRest = level == "Avancé" ? 15 : 20
        gymOn = true
        try? ctx.save()
        CategorySetup.markDone(.fitness)
        Haptics.success()
    }

    /// Ajoute un exercice ciblé si la séance touche un muscle priorisé.
    private func addEmphasis(to focus: String, title: String) -> String {
        let map: [String: String] = ["Pecs": "Pecs", "Dos": "Dos", "Épaules": "Épaules",
                                     "Bras": "Biceps", "Jambes": "Quadriceps", "Fessiers": "Ischios", "Abdos": "Abdos"]
        var f = focus
        let reps = GymExercises.repScheme(goal: goal)
        for e in emphasis {
            guard let group = map[e], let pool = GymExercises.catalog[group] else { continue }
            // si la séance contient déjà ce groupe, ajoute un exercice de plus
            if GymExercises.templates[title]?.contains(group) == true {
                let present = f.components(separatedBy: " · ")
                if let extra = pool.first(where: { ex in !present.contains(where: { $0.hasPrefix(ex) }) }) {
                    f += " · \(extra) \(reps)"
                }
            }
        }
        return f
    }
}
