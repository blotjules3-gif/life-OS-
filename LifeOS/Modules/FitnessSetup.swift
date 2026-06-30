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

    @State private var sex = "Homme"
    @State private var goal = "Prise de muscle"
    @State private var level = "Intermédiaire"
    @State private var freq = "4 jours"
    @State private var place = "Salle"

    private let tint = AppCategory.fitness.tint

    var body: some View {
        SetupFlow(title: "Sport & fitness", accent: tint, pages: pages, onComplete: commit)
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 18) {
                    SetupHeader(icon: "figure.run", title: "On construit ton programme",
                                subtitle: "5 questions et ta semaine d'entraînement est prête.", accent: tint)
                    SetupChoice(options: ["Homme", "Femme"], selection: $sex, accent: tint,
                                icons: ["figure.stand", "figure.stand.dress"])
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "target", title: "Ton objectif ?", accent: tint)
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
                    SetupHeader(icon: "checkmark.seal.fill", title: "Ton programme",
                                subtitle: "Réparti sur la semaine. Tu pourras l'ajuster à tout moment.", accent: tint)
                    programPreview
                }
            }
        ]
    }

    // MARK: génération du split

    private var daysPerWeek: Int { Int(freq.prefix(1)) ?? 4 }

    /// Renvoie les titres de séances (jours d'entraînement) selon objectif/fréquence.
    private var sessions: [(String, String)] {
        switch daysPerWeek {
        case 2:
            return [("Full body A", "Squat · Développé couché · Tirage · Gainage"),
                    ("Full body B", "Soulevé de terre · Développé militaire · Fentes · Abdos")]
        case 3:
            if goal == "Force" {
                return [("Squat focus", "Squat lourd · Presse · Mollets"),
                        ("Bench focus", "Développé couché · Dips · Triceps"),
                        ("Deadlift focus", "Soulevé de terre · Rowing · Biceps")]
            }
            return [("Push", "Pecs · Épaules · Triceps"),
                    ("Pull", "Dos · Biceps · Avant-bras"),
                    ("Legs", "Quadris · Ischios · Mollets")]
        case 4:
            return [("Haut du corps A", "Pecs · Dos · Épaules"),
                    ("Bas du corps A", "Quadris · Ischios · Mollets"),
                    ("Haut du corps B", "Dos · Biceps · Triceps"),
                    ("Bas du corps B", "Fessiers · Ischios · Abdos")]
        default:
            return [("Pecs + Triceps", "Développé couché · Dips · Extensions"),
                    ("Dos + Biceps", "Tractions · Rowing · Curl"),
                    ("Jambes", "Squat · Presse · Mollets"),
                    ("Épaules + Abdos", "Développé militaire · Élévations · Gainage"),
                    ("Full / Faiblesses", "Rappel des points faibles · Cardio")]
        }
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
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.title).font(.subheadline.weight(.medium))
                            .foregroundStyle(p.rest ? Theme.textSecondary : tint)
                        if !p.rest { Text(p.focus).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(1) }
                    }
                    Spacer()
                }
                .padding(.vertical, 9).padding(.horizontal, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: enregistrement

    private func commit() {
        // Efface l'ancien programme et réécrit le nouveau.
        for d in gymDays { ctx.delete(d) }
        for p in weekPlan {
            ctx.insert(GymDay(weekday: p.weekday, title: p.title, focus: p.focus, isRest: p.rest))
        }
        // Défauts Tabata selon le niveau.
        tabataWork = level == "Débutant" ? 30 : (level == "Avancé" ? 45 : 40)
        tabataRest = level == "Avancé" ? 15 : 20
        gymOn = true
        try? ctx.save()
        CategorySetup.markDone(.fitness)
        Haptics.success()
    }
}
