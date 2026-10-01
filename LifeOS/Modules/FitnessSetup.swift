import SwiftUI
import SwiftData

// MARK: - Formulaire de configuration « Sport & fitness »
// Pré-remplit : programme hebdo (séances réparties), rappels muscu, défaut Tabata.

struct FitnessSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var gymDays: [GymDay]

    @AppStorage(AppStorageKeys.gymReminderOn)    private var gymOn = true
    @AppStorage(AppStorageKeys.gymReminderHour)  private var gymHour = 7
    @AppStorage(AppStorageKeys.tabataWork)       private var tabataWork = 40
    @AppStorage(AppStorageKeys.tabataRest)       private var tabataRest = 20
    @AppStorage(AppStorageKeys.userGender)       private var userGender = ""     // déjà connu (onboarding)
    @AppStorage(AppStorageKeys.userGoalFit)      private var userGoalFit = ""    // réutilisé par d'autres catégories

    // Plusieurs objectifs a la fois: viser le muscle ET le cardio est une
    // demande normale, et l'ancien choix unique obligeait a mentir.
    @State private var goals: Set<String> = ["Prise de muscle"]
    @State private var level = "Intermédiaire"
    @State private var freq = "4 jours"
    @State private var place = "Salle"
    /// Matériel (libellés `FitbotEquipment`) et duree de seance : le meme generateur
    /// que « Générer un programme » dans Fitbot, pour un seul moteur.
    @State private var kit: Set<String> = [FitbotEquipment.gym.label]
    @State private var minutes = "60 min"
    @State private var emphasis: Set<String> = []

    /// Le generateur de programme raisonne sur un seul objectif. On lui donne
    /// le plus structurant de ceux coches, du plus precis au plus vague.
    private var primaryGoal: String {
        for g in ["Force", "Prise de muscle", "Perte de gras", "Cardio / Endurance"]
        where goals.contains(g) { return g }
        return "Forme générale"
    }

    private let tint = AppCategory.fitness.tint
    private var isFemme: Bool { userGender == "femme" }

    var body: some View {
        SetupFlow(title: "Sport & fitness", accent: tint, pages: pages, onComplete: commit,
                  previewNotes: ["Tes séances et charges déjà enregistrées ne changent pas."],
                  preview: previewChanges, draft: draftIO)
            .onAppear(perform: loadAnswers)
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 18) {
                    SetupHeader(icon: "figure.run", title: "On construit ton programme",
                                subtitle: "Quelques questions et ta semaine d'entraînement détaillée est prête.", accent: tint)
                    SetupMultiChoice(options: ["Prise de muscle", "Perte de gras", "Force",
                                               "Cardio / Endurance", "Forme générale"],
                                     selection: $goals, accent: tint)
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
                    SetupChoice(options: ["2 jours", "3 jours", "4 jours", "5 jours", "6 jours"], selection: $freq, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "dumbbell", title: "Quel matériel as-tu ?",
                                subtitle: "Seuls des exercices faisables avec lui seront proposés.", accent: tint)
                    SetupMultiChoice(options: FitbotEquipment.allCases.map(\.label), selection: $kit, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "clock", title: "Combien de temps par séance ?", accent: tint)
                    SetupChoice(options: FitbotGenerator.sessionLengths.map { "\($0) min" }, selection: $minutes, accent: tint)
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

    private var equipment: Set<FitbotEquipment> {
        let set = Set(FitbotEquipment.allCases.filter { kit.contains($0.label) })
        return set.isEmpty ? [.gym] : set
    }
    private var sessionMinutes: Int { Int(minutes.prefix { $0.isNumber }) ?? 60 }

    /// Semaine generee (split selon la frequence, exercices selon le matériel), puis
    /// volume ajoute sur les muscles priorises.
    private var generated: FitbotGenerator.Week {
        var week = FitbotGenerator.generate(goal: FitbotGoal.fromSetup(primaryGoal), daysPerWeek: daysPerWeek,
                                            sessionMinutes: sessionMinutes, equipment: equipment,
                                            excluded: FitbotSettings.parseExcluded(UserDefaults.standard.string(forKey: FitbotSettings.excludedKey) ?? ""))
        if !emphasis.isEmpty {
            for i in week.days.indices where !week.days[i].isRest {
                week.days[i].focus = addEmphasis(to: week.days[i].focus, goal: week.goal)
            }
        }
        return week
    }

    private var weekPlan: [(weekday: Int, title: String, focus: String, rest: Bool)] {
        generated.days.map { ($0.weekday, $0.isRest ? "Repos" : $0.title,
                              $0.isRest ? "Récupération · marche · étirements" : $0.focus, $0.isRest) }
    }

    private var programPreview: some View {
        VStack(spacing: 8) {
            if !generated.uncoveredGroups.isEmpty {
                Text("Aucun exercice du catalogue pour \(generated.uncoveredGroups.joined(separator: ", ")) avec ce matériel.")
                    .font(.caption).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !generated.isUsable {
                Text("Une séance resterait vide avec ce matériel : ta semaine actuelle sera gardée. Ajoute du matériel.")
                    .font(.caption).foregroundStyle(Theme.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
                .raisedSurface(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 14)
    }

    // MARK: enregistrement

    /// L'apercu montre le NOUVEAU programme jour par jour, a cote de l'ancien:
    /// c'est ce que "Appliquer" va remplacer.
    private func previewChanges() -> [SetupSession.Change] {
        let names = ["", "Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
        let old = Dictionary(gymDays.map { ($0.weekday, $0.isRest ? "Repos" : $0.title) }, uniquingKeysWith: { a, _ in a })
        var out: [SetupSession.Change] = [
            .make("Objectif principal", userGoalFit.isEmpty ? "—" : userGoalFit, primaryGoal),
            .make("Minuteur HIIT", "\(tabataWork)s / \(tabataRest)s",
                  "\(level == "Débutant" ? 30 : (level == "Avancé" ? 45 : 40))s / \(level == "Avancé" ? 15 : 20)s"),
        ].compactMap { $0 }
        for p in weekPlan {
            let new = p.rest ? "Repos" : p.title
            if let c = SetupSession.Change.make("Programme · \(names[p.weekday])", old[p.weekday] ?? "—", new) {
                out.append(c)
            }
        }
        return out
    }

    // Reponses gardees pour "Modifier mes reponses". Avant, seul l'objectif etait
    // enregistre: rouvrir le questionnaire montrait les valeurs par defaut
    // (Intermediaire, 4 jours, Salle) au lieu de ce que l'utilisateur avait choisi.
    private enum Saved {
        static let level = "fitnessSetup.level", freq = "fitnessSetup.freq"
        static let place = "fitnessSetup.place", emphasis = "fitnessSetup.emphasis"
        static let minutes = "fitnessSetup.minutes"
    }

    private func loadAnswers() {
        let d = UserDefaults.standard
        if let g = d.string(forKey: "userGoalsFit"), !g.isEmpty {
            goals = Set(g.split(separator: ",").map(String.init))
        }
        if let v = d.string(forKey: Saved.level), !v.isEmpty { level = v }
        if let v = d.string(forKey: Saved.freq), !v.isEmpty { freq = v }
        if let v = d.string(forKey: Saved.place), !v.isEmpty { place = v }
        // Matériel : celui de Fitbot s'il a ete regle, sinon deduit de l'ancien
        // « Où t'entraînes-tu ? » (maison = poids du corps, on ne suppose pas d'haltères).
        if let raw = d.string(forKey: FitbotSettings.equipmentKey), !raw.isEmpty {
            kit = Set(FitbotEquipment.parse(raw).map(\.label))
        } else if place == "Maison" {
            kit = [FitbotEquipment.bodyweight.label]
        }
        if let v = d.string(forKey: Saved.minutes), !v.isEmpty { minutes = v }
        if let v = d.string(forKey: Saved.emphasis) {
            emphasis = Set(v.split(separator: ",").map(String.init))
        }
    }

    private func commit() {
        let d = UserDefaults.standard
        d.set(level, forKey: Saved.level); d.set(freq, forKey: Saved.freq)
        d.set(place, forKey: Saved.place)
        d.set(minutes, forKey: Saved.minutes)
        d.set(FitbotEquipment.serialize(equipment), forKey: FitbotSettings.equipmentKey)
        d.set(emphasis.sorted().joined(separator: ","), forKey: Saved.emphasis)
        userGoalFit = primaryGoal
        // La liste complete a part, pour ne pas casser ceux qui comparent
        // userGoalFit a une seule valeur exacte.
        UserDefaults.standard.set(goals.sorted().joined(separator: ","), forKey: "userGoalsFit")
        // Reecrit la semaine DANS les jours existants (memes identifiants, une seance en
        // cours reste rattachee) et garde l'ancienne pour « Revenir à la semaine d'avant ».
        let week = generated
        d.set(week.goal.rawValue, forKey: "fitbot.lastGoal")
        d.set(week.daysPerWeek, forKey: "fitbot.lastDays")
        d.set(week.sessionMinutes, forKey: "fitbot.lastMinutes")
        // Défauts Tabata selon le niveau.
        tabataWork = level == "Débutant" ? 30 : (level == "Avancé" ? 45 : 40)
        tabataRest = level == "Avancé" ? 15 : 20
        gymOn = true
        if week.isUsable {
            do { try FitbotProgramService.apply(week, days: gymDays, in: ctx) }
            catch { AppLog.data.error("FitnessSetup programme failed: \(error.localizedDescription, privacy: .public)") }
        }
        do { try ctx.save() } catch { AppLog.data.error("FitnessSetup save failed: \(error.localizedDescription, privacy: .public)") }
        CategorySetup.markDone(.fitness)
        Haptics.success()
    }

    /// Ajoute un exercice ciblé si la séance touche déjà un muscle priorisé, avec le
    /// matériel disponible.
    private func addEmphasis(to focus: String, goal: FitbotGoal) -> String {
        let map: [String: String] = ["Pecs": "Pecs", "Dos": "Dos", "Épaules": "Épaules",
                                     "Bras": "Biceps", "Jambes": "Quadriceps", "Fessiers": "Ischios", "Abdos": "Abdos"]
        var f = focus
        for e in emphasis.sorted() {
            guard let group = map[e] else { continue }
            let present = f.components(separatedBy: " · ")
            guard present.contains(where: { GymExercises.group(of: $0) == group }) else { continue }
            let bases = Set(present.map { GymExercises.baseName($0) })
            if let extra = GymExercises.choices(group: group, equipment: equipment).first(where: { !bases.contains($0) }) {
                f += " · \(extra) \(goal.target)"
            }
        }
        return f
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("goals", goals)
            d.put("level", level)
            d.put("freq", freq)
            d.put("place", place)
            d.put("kit", kit)
            d.put("minutes", minutes)
            d.put("emphasis", emphasis)
            return d
        }, restore: { d in
            if let v = d.set("goals") { goals = v }
            if let v = d.string("level") { level = v }
            if let v = d.string("freq") { freq = v }
            if let v = d.string("place") { place = v }
            if let v = d.set("kit") { kit = v }
            if let v = d.string("minutes") { minutes = v }
            if let v = d.set("emphasis") { emphasis = v }
        })
    }
}
