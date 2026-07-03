import SwiftUI
import SwiftData

// MARK: - LifeBrain : le cerveau transversal de LifeOS
// Lit TOUTES les catégories (sommeil, nutrition, sport, humeur, habitudes, cycle, agenda)
// et produit une guidance CONNECTÉE et adaptative — chaque conseil relie ≥2 domaines.
// 100% on-device. Alimente la carte « Pour toi aujourd'hui » (accueil) ET le coach.

enum BrainTone { case good, warn, info, push }

struct BrainInsight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let tone: BrainTone
    let category: AppCategory?
    let priority: Int   // plus grand = plus prioritaire
}

@MainActor
enum LifeBrain {

    // MARK: Snapshot transversal

    struct Snapshot {
        var hour: Int = 0
        var sleepHours: Double = 0
        var sleepQuality: Int = 0          // 0…5
        var waterML = 0, waterGoal = 2500
        var kcal = 0, kcalGoal = 2200
        var proteinGoal = 0
        var isTrainingDay = false
        var trainingTitle = ""
        var habitsDone = 0, habitsTotal = 0
        var moodToday: Int? = nil          // 1…5
        var moodRecentAvg: Double? = nil   // 2-3 derniers jours
        var cyclePhase: String = ""        // "" si non suivi
        var loadCount = 0                  // charge du jour (tâches + événements)
    }

    static func snapshot(ctx: ModelContext) -> Snapshot {
        let cal = Calendar.current, d = UserDefaults.standard
        var s = Snapshot()
        s.hour = cal.component(.hour, from: .now)
        s.sleepHours = d.double(forKey: "lastSleepHours")
        s.sleepQuality = d.integer(forKey: "lastSleepQuality")
        s.waterGoal = max(1, d.integer(forKey: "waterGoal").nz(2500))
        s.kcalGoal = d.integer(forKey: "kcalGoal").nz(2200)
        s.proteinGoal = d.integer(forKey: "proteinGoal")
        if s.proteinGoal == 0 {
            let w = d.double(forKey: "userWeight")
            s.proteinGoal = w > 0 ? Int(w * 1.8) : 130
        }

        let waters = (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? []
        s.waterML = waters.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        let foods = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        s.kcal = foods.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }

        let weekday = cal.component(.weekday, from: .now)
        let gym = (try? ctx.fetch(FetchDescriptor<GymDay>())) ?? []
        if let today = gym.first(where: { $0.weekday == weekday && !$0.isRest && !$0.title.isEmpty }) {
            s.isTrainingDay = true; s.trainingTitle = today.title
        }

        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        s.habitsTotal = habits.count
        s.habitsDone = habits.filter { h in h.completions.contains { cal.isDateInToday($0.date) } }.count

        let moods = (try? ctx.fetch(FetchDescriptor<MoodEntry>())) ?? []
        s.moodToday = moods.first { cal.isDateInToday($0.date) }?.score
        let recent = moods.filter { $0.date > cal.date(byAdding: .day, value: -3, to: .now)! }
        if !recent.isEmpty { s.moodRecentAvg = Double(recent.reduce(0) { $0 + $1.score }) / Double(recent.count) }

        // Phase de cycle (si suivi)
        let startTS = d.double(forKey: "cycleStartDate")
        if startTS > 0 {
            let len = max(20, d.integer(forKey: "cycleLengthDays").nz(28))
            let start = Date(timeIntervalSince1970: startTS)
            let elapsed = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: .now)).day ?? 0
            let day = (elapsed % len + len) % len + 1
            switch day {
            case 1...5:   s.cyclePhase = "menstruelle"
            case 6...11:  s.cyclePhase = "folliculaire"
            case 12...16: s.cyclePhase = "ovulation"
            default:      s.cyclePhase = "lutéale"
            }
        }

        let todos = (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? []
        let events = (try? ctx.fetch(FetchDescriptor<SocialEvent>())) ?? []
        s.loadCount = todos.filter { !$0.done }.count
            + events.filter { cal.isDateInToday($0.date) }.count
            + (s.isTrainingDay ? 1 : 0)
        return s
    }

    // MARK: Génération des insights connectés

    static func insights(ctx: ModelContext) -> [BrainInsight] {
        insights(from: snapshot(ctx: ctx))
    }

    static func insights(from s: Snapshot) -> [BrainInsight] {
        var out: [BrainInsight] = []

        // Sommeil → sport + hydratation (connexion sommeil × fitness × nutrition)
        if s.sleepHours > 0 && s.sleepHours < 6.5 {
            let extra = s.isTrainingDay ? " Allège ta séance (\(s.trainingTitle)) et" : ""
            out.append(.init(icon: "moon.zzz.fill",
                             title: "Nuit courte (\(fmt(s.sleepHours)) h)",
                             detail: "Récup' en priorité.\(extra) bois +500 ml pour compenser la fatigue.",
                             tone: .warn, category: .sleep, priority: 90))
        } else if (s.sleepQuality >= 4 || s.sleepHours >= 7.5) && s.isTrainingDay {
            out.append(.init(icon: "bolt.fill",
                             title: "Bien récupéré 💪",
                             detail: "Nuit solide + jour de sport (\(s.trainingTitle)) : tu peux pousser l'intensité aujourd'hui.",
                             tone: .good, category: .fitness, priority: 70))
        }

        // Jour de sport → protéines + créatine (fitness × nutrition)
        if s.isTrainingDay {
            out.append(.init(icon: "figure.strengthtraining.traditional",
                             title: "Jour de sport : \(s.trainingTitle)",
                             detail: "Vise ~\(s.proteinGoal) g de protéines aujourd'hui, et prends ta créatine après la séance.",
                             tone: .info, category: .nutrition, priority: 60))
        }

        // Cycle → sport + nutrition + skincare (cycle × fitness × nutrition × looks)
        switch s.cyclePhase {
        case "folliculaire":
            out.append(.init(icon: "arrow.up.forward.circle.fill", title: "Phase folliculaire",
                             detail: "Énergie et récup au top : c'est le moment de charger lourd et viser des perfs.",
                             tone: .good, category: .fitness, priority: 55))
        case "lutéale":
            out.append(.init(icon: "leaf.fill", title: "Phase lutéale",
                             detail: "Baisse un peu l'intensité, ajoute du magnésium, priorise le sommeil. Peau plus réactive → routine douce.",
                             tone: .info, category: .cycle, priority: 55))
        case "menstruelle":
            out.append(.init(icon: "drop.halffull", title: "Règles",
                             detail: "Écoute ton corps : séances légères, fer + hydratation, et repos si besoin.",
                             tone: .info, category: .cycle, priority: 58))
        case "ovulation":
            out.append(.init(icon: "sparkle", title: "Ovulation — pic de forme",
                             detail: "Ta fenêtre la plus forte : cale ta séance clé ou ton record ici.",
                             tone: .good, category: .fitness, priority: 52))
        default: break
        }

        // Hydratation en retard (nutrition, contextuel selon l'heure)
        if s.hour >= 14 && s.waterML < Int(Double(s.waterGoal) * 0.4) {
            out.append(.init(icon: "drop.fill",
                             title: "Hydratation en retard",
                             detail: "Tu es à \(s.waterML)/\(s.waterGoal) ml. Bois ~\(max(250, (s.waterGoal - s.waterML) / 3)) ml maintenant.",
                             tone: .warn, category: .nutrition, priority: 50))
        }

        // Humeur en baisse → mental + sport (mood × mind × fitness)
        if let avg = s.moodRecentAvg, avg <= 2.3 {
            out.append(.init(icon: "cloud.rain.fill",
                             title: "Moral en baisse ces jours-ci",
                             detail: "Une marche de 20 min à la lumière + une séance légère font remonter l'humeur. Vas-y en douceur.",
                             tone: .warn, category: .mind, priority: 65))
        }

        // Journée chargée → protéger l'essentiel (agenda × sommeil)
        if s.loadCount >= 4 {
            out.append(.init(icon: "square.stack.3d.up.fill",
                             title: "Journée chargée (\(s.loadCount) éléments)",
                             detail: "Protège l'essentiel : ta priorité n°1 + une bonne nuit. Le reste peut glisser.",
                             tone: .info, category: nil, priority: 45))
        }

        // Habitudes restantes en fin de journée (productivité)
        if s.hour >= 18 && s.habitsTotal > 0 && s.habitsDone < s.habitsTotal {
            let left = s.habitsTotal - s.habitsDone
            out.append(.init(icon: "checklist",
                             title: "\(left) habitude\(left > 1 ? "s" : "") à cocher",
                             detail: "5 minutes suffisent pour ne pas casser ta série. Fais la plus rapide d'abord.",
                             tone: .push, category: nil, priority: 48))
        }

        // Tout est aligné (fallback positif)
        if out.isEmpty {
            out.append(.init(icon: "checkmark.seal.fill",
                             title: "Tout est aligné aujourd'hui 🎯",
                             detail: "Sommeil, hydratation, objectifs : tu es sur les rails. Continue comme ça.",
                             tone: .good, category: nil, priority: 10))
        }

        return out.sorted { $0.priority > $1.priority }
    }

    // MARK: Résumé pour le coach (chat) — connecte les domaines en une réponse

    static func coachSummary(ctx: ModelContext) -> String {
        let items = insights(ctx: ctx)
        let top = items.prefix(3)
        var lines = ["🧠 **Ta guidance du jour**", ""]
        for i in top { lines.append("• **\(i.title)** — \(i.detail)") }
        return lines.joined(separator: "\n")
    }

    private static func fmt(_ h: Double) -> String {
        h.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(h)) : String(format: "%.1f", h)
    }
}

private extension Int {
    func nz(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}

// MARK: - Score d'énergie ON-DEVICE (remplace l'ancien calcul backend)

enum LocalEnergy {
    /// Score 0–100 à partir du check-in du matin (sommeil, humeur, énergie, eau, habitudes).
    static func score(sleepQuality: Int, sleepHours: Double, mood: Int, energy: Int,
                      waterML: Int, habitsDone: Int, habitsTotal: Int) -> Int {
        var pts = 0.0
        pts += (sleepQuality > 0 ? Double(sleepQuality) / 5 : 0.6) * 30      // qualité sommeil
        if sleepHours > 0 { pts += max(0, 1 - abs(sleepHours - 8) / 4) * 15 } // durée (optimum 8 h)
        else { pts += 0.6 * 15 }
        pts += (mood > 0 ? Double(mood) / 5 : 0.6) * 25                       // humeur
        pts += (energy > 0 ? Double(energy) / 5 : 0.6) * 20                   // énergie ressentie
        pts += min(1, Double(waterML) / 2000) * 5                            // hydratation
        if habitsTotal > 0 { pts += Double(habitsDone) / Double(habitsTotal) * 5 } // habitudes
        return max(0, min(100, Int(pts.rounded())))
    }

    static func label(_ s: Int) -> String {
        switch s {
        case ..<35: return "Faible"
        case ..<55: return "Correct"
        case ..<75: return "Bien"
        case ..<90: return "Très bien"
        default:    return "Au top"
        }
    }
}

// MARK: - Carte « Pour toi aujourd'hui » (accueil)

struct LifeBrainCard: View {
    @Environment(\.modelContext) private var ctx

    private var insights: [BrainInsight] { LifeBrain.insights(ctx: ctx) }

    var body: some View {
        let top = Array(insights.prefix(3))
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.onVolt).frame(width: 30, height: 30)
                    .background(Theme.volt, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text("Pour toi aujourd'hui")
                    .font(.system(size: 20, weight: .black)).textCase(.uppercase).kerning(-0.3)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(Array(top.enumerated()), id: \.element.id) { idx, ins in
                    row(ins)
                    if idx < top.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 52) }
                }
            }
            .card(padding: 8, elevated: true)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder private func row(_ ins: BrainInsight) -> some View {
        if let cat = ins.category {
            NavigationLink { cat.destination } label: { content(ins) }.buttonStyle(.plain)
        } else {
            content(ins)
        }
    }

    private func content(_ ins: BrainInsight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ins.icon).font(.system(size: 16, weight: .bold))
                .foregroundStyle(glyphColor(ins.tone))
                .frame(width: 40, height: 40)
                .background(badgeBG(ins.tone), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ins.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(ins.detail).font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if ins.category != nil {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5)).padding(.top, 12)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func glyphColor(_ t: BrainTone) -> Color {
        switch t {
        case .good, .push: return Theme.onVolt
        case .warn:        return .white
        case .info:        return Color(uiColor: .systemBackground)
        }
    }
    private func badgeBG(_ t: BrainTone) -> Color {
        switch t {
        case .good, .push: return Theme.volt
        case .warn:        return Color(hex: 0xE8863C)
        case .info:        return Color.primary
        }
    }
}
