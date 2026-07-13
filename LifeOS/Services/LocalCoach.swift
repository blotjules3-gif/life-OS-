import Foundation
import SwiftData

/// Coach LifeOS 100 % ON-DEVICE — aucun serveur.
/// Comprend le message, LIT les vraies données SwiftData de l'utilisateur, et
/// PEUT agir concrètement (créer une habitude, une tâche, une note, logger un verre d'eau…).
/// Remplace l'ancien backend distant `AgentAPI` (non déployé → « Could not connect »).
@MainActor
enum LocalCoach {

    // MARK: - Entrée principale

    static func respond(to raw: String, ctx: ModelContext) -> String {
        let t = normalize(raw)
        let d = UserDefaults.standard
        let name = (d.string(forKey: "userName") ?? "").trimmingCharacters(in: .whitespaces)

        // Salutations
        if matches(t, ["bonjour", "salut", "coucou", "hello", "hey", "yo ", "cava", "ca va", "comment vas"]) && t.count < 30 {
            return "\(greet(name)) Je suis ton coach LifeOS, et je marche entièrement sur ton iPhone. "
                + statusLine(ctx) + "\n\nJe peux te créer une habitude, une tâche, une note, logger un verre d'eau, ou te faire un bilan. Dis-moi."
        }

        // Remerciement
        if matches(t, ["merci", "thanks", "nickel", "parfait", "super"]) && t.count < 20 {
            return "Avec plaisir, on continue quand tu veux."
        }

        // Aide / capacités
        if matches(t, ["aide", "help", "tu fais quoi", "tu peux faire", "que peux", "capacites", "comment ca marche"]) {
            return capabilities()
        }

        // --- COACHING GÉNÉRATIF (vraies réponses) ---
        if let plan = workoutPlan(raw) { return plan }
        if let meal = mealPlan(raw) { return meal }
        if let mot = motivation(t) { return mot }

        // Guidance TRANSVERSALE (relie sommeil × sport × nutrition × cycle × humeur…)
        if matches(t, ["quoi faire", "que faire", "conseil", "conseille", "guidance", "guide moi",
                      "par quoi commencer", "optimise ma journee", "priorite", "je fais quoi", "aide moi a m'organiser"]) {
            return LifeBrain.coachSummary(ctx: ctx)
        }

        // --- ACTIONS (écriture) ---

        // Créer une habitude
        if matches(t, ["habitude", "habit"]) && hasCreateVerb(t) {
            let subject = subject(from: raw, after: ["habitude quotidienne", "habitude", "habit"])
            if let clean = meaningful(subject) {
                let h = Habit(name: clean, icon: iconFor(clean), colorHex: 0x4CF810)
                ctx.insert(h); try? ctx.save()
                return "Nouvelle habitude créée : **\(clean)**. Elle est dans ton suivi d'habitudes — coche-la chaque jour pour bâtir ta série."
            }
            return "Bonne idée. Quelle habitude veux-tu créer ? Donne-moi juste son nom (ex. « Méditer 10 min », « Boire 2 L d'eau », « Lire 20 pages »)."
        }

        // Créer une tâche / rappel
        if hasCreateVerb(t) && matches(t, ["tache", "tâche", "todo", "to-do", "rappelle", "rappel", "faut que", "il faut", "penser a", "pense a", "note moi de"]) {
            let subject = subject(from: raw, after: ["rappelle moi de", "rappelle-moi de", "rappelle moi", "note moi de", "une tache", "une tâche", "un todo", "tache", "tâche", "todo", "il faut que je", "faut que je", "penser a", "pense a", "de "])
            if let clean = meaningful(subject) {
                let todo = TodoItem(title: clean, priority: matches(t, ["urgent", "vite", "important"]) ? 2 : 0)
                ctx.insert(todo); try? ctx.save()
                return "C'est noté : **\(clean)** est ajouté à ta liste de tâches (module To-do)."
            }
            return "Dis-moi quoi ajouter à ta liste et je le note tout de suite (ex. « rappelle-moi d'appeler le dentiste »)."
        }

        // Logger de l'eau
        if matches(t, ["verre d'eau", "verre deau", "un verre", "j'ai bu", "jai bu", "bu de l'eau", "ajoute de l'eau", "hydrate"]) && !matches(t, ["combien", "reste", "objectif"]) {
            let glass = 250
            ctx.insert(WaterEntry(amountML: glass)); try? ctx.save()
            let (ml, goal, _) = water(ctx)
            return "+1 verre (\(glass) ml) enregistré. Tu es à \(ml) / \(goal) ml aujourd'hui. \(ml >= goal ? "Objectif atteint, bravo." : "Continue comme ça !")"
        }

        // Créer une note
        if hasCreateVerb(t) && matches(t, ["note", "noter"]) {
            let subject = subject(from: raw, after: ["une note", "note que", "noter que", "note", "noter"])
            if let clean = meaningful(subject) {
                ctx.insert(Note(title: String(clean.prefix(40)), body: clean)); try? ctx.save()
                return "Note enregistrée : « \(clean) »."
            }
        }

        // --- LECTURE (résumés / questions sur les données) ---

        // Bilan / résumé
        if matches(t, ["bilan", "resume", "récap", "recap", "point", "ou j'en suis", "ou jen suis", "semaine", "comment je vais"]) {
            return weeklyReport(ctx, name: name)
        }

        // Sommeil
        if matches(t, ["sommeil", "dormi", "dormir", "nuit", "fatigue", "reveil", "réveil", "sleep"]) {
            return sleepReport()
        }

        // Journée / demain / planning
        if matches(t, ["demain", "planning", "programme", "ma journee", "ma journée", "aujourd'hui", "aujourdhui", "objectifs du jour", "a faire", "à faire", "todo list", "mes taches", "mes tâches"]) {
            return dayPlan(ctx)
        }

        // Habitudes (liste, sans verbe de création)
        if matches(t, ["habitude", "mes habit", "streak", "serie", "série"]) {
            return habitsReport(ctx)
        }

        // Eau (question)
        if matches(t, ["eau", "hydrat", "verres", "boire"]) {
            let (ml, goal, glasses) = water(ctx)
            return "Aujourd'hui : \(ml) / \(goal) ml (\(glasses) verre\(glasses > 1 ? "s" : "")). "
                + (ml >= goal ? "Objectif atteint." : "Il te reste \(max(0, goal - ml)) ml. Dis « j'ai bu un verre » et je l'ajoute.")
        }

        // Calories / repas
        if matches(t, ["calorie", "kcal", "manger", "mange", "repas", "nutrition"]) {
            let (kcal, goal) = calories(ctx)
            return "Aujourd'hui : \(kcal) / \(goal) kcal. "
                + (kcal == 0 ? "Rien de logué pour l'instant — scanne un produit ou envoie-moi une photo de ton assiette." : "Il te reste ~\(max(0, goal - kcal)) kcal pour la journée.")
        }

        // Tâches (question)
        if matches(t, ["tache", "tâche", "todo", "to-do", "a faire"]) {
            return dayPlan(ctx)
        }

        // Fallback utile
        return "Je suis là pour t'aider. " + statusLine(ctx)
            + "\n\nQuelques exemples de ce que tu peux me dire :\n• « Crée une habitude Méditer 10 min »\n• « Rappelle-moi d'appeler le dentiste »\n• « J'ai bu un verre d'eau »\n• « Fais-moi un bilan »\n• « Comment j'ai dormi ? »"
    }

    /// Message d'accueil au premier lancement — local, sans serveur.
    static func welcome(name: String) -> String {
        "\(greet(name)) Je suis ton coach LifeOS — je fonctionne directement sur ton iPhone, sans connexion.\n\n"
        + "Je connais tes données (habitudes, eau, calories, tâches, sommeil) et je peux agir pour toi : créer une habitude, ajouter une tâche, logger un verre d'eau, ou te faire un bilan.\n\n"
        + "Par quoi veux-tu commencer ?"
    }

    // MARK: - Rapports (lecture des données)

    private static func statusLine(_ ctx: ModelContext) -> String {
        let (ml, goalW, _) = water(ctx)
        let (done, total) = habitsToday(ctx)
        let pending = pendingTodos(ctx).count
        var bits: [String] = []
        bits.append("\(ml)/\(goalW) ml")
        if total > 0 { bits.append("\(done)/\(total) habitudes") }
        if pending > 0 { bits.append("\(pending) tâche\(pending > 1 ? "s" : "") en attente") }
        return "Aujourd'hui : " + bits.joined(separator: " · ") + "."
    }

    private static func weeklyReport(_ ctx: ModelContext, name: String) -> String {
        let (ml, goalW, glasses) = water(ctx)
        let (kcal, goalK) = calories(ctx)
        let (done, total) = habitsToday(ctx)
        let pending = pendingTodos(ctx)
        let mood = todayMood(ctx)

        var lines = ["📊 **Ton bilan\(name.isEmpty ? "" : ", \(name)")**", ""]
        lines.append("• Habitudes : \(done)/\(total) faites aujourd'hui\(total == 0 ? " (aucune encore — on en crée une ?)" : "")")
        lines.append("• Hydratation : \(glasses) verre\(glasses > 1 ? "s" : "") (\(ml)/\(goalW) ml)")
        lines.append("• Calories : \(kcal)/\(goalK) kcal")
        if let m = mood { lines.append("• Humeur du jour : \(moodEmoji(m))/5") }
        lines.append("• Tâches en attente : \(pending.count)")
        lines.append("")
        // Conseil ciblé
        if total > 0 && done < total { lines.append("👉 Priorité : boucler tes \(total - done) habitude(s) restante(s).") }
        else if ml < goalW { lines.append("👉 Priorité : bois encore \(max(0, goalW - ml)) ml d'eau.") }
        else if !pending.isEmpty { lines.append("👉 Priorité : « \(pending[0].title) ».") }
        else { lines.append("👉 Tout est carré aujourd'hui, continue comme ça 🎯") }
        // Guidance transversale (relie les domaines entre eux)
        if let brain = LifeBrain.insights(ctx: ctx).first {
            lines.append(""); lines.append("🧠 \(brain.title) — \(brain.detail)")
        }
        return lines.joined(separator: "\n")
    }

    private static func sleepReport() -> String {
        let d = UserDefaults.standard
        let q = d.integer(forKey: "lastSleepQuality")   // 0…5
        let h = d.double(forKey: "lastSleepHours")
        let wh = d.integer(forKey: "wakeupHour"); let wm = d.integer(forKey: "wakeupMinute")
        let wake = String(format: "%02d:%02d", wh, wm)
        if q == 0 && h == 0 {
            return "😴 Je n'ai pas encore de données de sommeil pour cette nuit. Fais le check du réveil et je pourrai suivre ta qualité de sommeil. Ton réveil est réglé à \(wake)."
        }
        var s = "😴 **Ton sommeil**\n"
        if h > 0 { s += "• Durée : \(String(format: "%.1f", h)) h\n" }
        if q > 0 { s += "• Qualité : \(q)/5\n" }
        s += "• Réveil réglé : \(wake)\n\n"
        if h > 0 && h < 7 { s += "💡 Moins de 7 h — vise un coucher plus tôt ce soir pour récupérer." }
        else if q >= 4 { s += "💪 Belle nuit ! Garde ce rythme régulier." }
        else { s += "💡 Régularité + écran coupé 1 h avant = meilleure récup." }
        return s
    }

    private static func dayPlan(_ ctx: ModelContext) -> String {
        let (done, total) = habitsToday(ctx)
        let pending = pendingTodos(ctx)
        let d = UserDefaults.standard
        let wake = String(format: "%02d:%02d", d.integer(forKey: "wakeupHour"), d.integer(forKey: "wakeupMinute"))
        var lines = ["🗓️ **Ton plan**", "", "• Réveil : \(wake)"]
        if total > 0 { lines.append("• Habitudes : \(done)/\(total) faites — \(max(0, total - done)) à cocher") }
        if pending.isEmpty {
            lines.append("• Tâches : aucune en attente ✅")
        } else {
            lines.append("• Tâches (\(pending.count)) :")
            for todo in pending.prefix(5) { lines.append("   ◦ \(todo.title)\(todo.priority == 2 ? " ⚡️" : "")") }
            if pending.count > 5 { lines.append("   … +\(pending.count - 5) autres") }
        }
        return lines.joined(separator: "\n")
    }

    private static func habitsReport(_ ctx: ModelContext) -> String {
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        if habits.isEmpty {
            return "Tu n'as pas encore d'habitude 🌱 Dis-moi laquelle créer (ex. « crée une habitude Méditer 10 min ») et je m'en occupe."
        }
        var lines = ["🔥 **Tes habitudes**", ""]
        for h in habits {
            let streak = currentStreak(h)
            let doneToday = h.completions.contains { Calendar.current.isDateInToday($0.date) }
            lines.append("• \(doneToday ? "✅" : "⬜️") \(h.name)\(streak > 0 ? " — série \(streak) j 🔥" : "")")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Accès données

    private static func water(_ ctx: ModelContext) -> (ml: Int, goal: Int, glasses: Int) {
        let all = (try? ctx.fetch(FetchDescriptor<WaterEntry>())) ?? []
        let ml = all.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amountML }
        let goal = max(1, UserDefaults.standard.integer(forKey: "waterGoal").nonZero(or: 2000))
        return (ml, goal, ml / 250)
    }

    private static func calories(_ ctx: ModelContext) -> (kcal: Int, goal: Int) {
        let all = (try? ctx.fetch(FetchDescriptor<FoodEntry>())) ?? []
        let kcal = all.filter { Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        let goal = UserDefaults.standard.integer(forKey: "kcalGoal").nonZero(or: 2200)
        return (kcal, goal)
    }

    private static func habitsToday(_ ctx: ModelContext) -> (done: Int, total: Int) {
        let habits = (try? ctx.fetch(FetchDescriptor<Habit>())) ?? []
        let done = habits.filter { h in h.completions.contains { Calendar.current.isDateInToday($0.date) } }.count
        return (done, habits.count)
    }

    private static func pendingTodos(_ ctx: ModelContext) -> [TodoItem] {
        let all = (try? ctx.fetch(FetchDescriptor<TodoItem>())) ?? []
        return all.filter { !$0.done }.sorted { $0.priority > $1.priority }
    }

    private static func todayMood(_ ctx: ModelContext) -> Int? {
        let all = (try? ctx.fetch(FetchDescriptor<MoodEntry>())) ?? []
        return all.first { Calendar.current.isDateInToday($0.date) }?.score
    }

    private static func currentStreak(_ h: Habit) -> Int {
        let days = Set(h.completions.map { Calendar.current.startOfDay(for: $0.date) })
        var streak = 0
        var day = Calendar.current.startOfDay(for: .now)
        // Autorise la série à compter même si aujourd'hui pas encore fait (on part d'hier).
        if !days.contains(day) { day = Calendar.current.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            streak += 1
            day = Calendar.current.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    // MARK: - NLU utilitaire

    private static func normalize(_ s: String) -> String {
        s.folding(options: .diacriticInsensitive, locale: .current).lowercased()
    }

    private static func matches(_ normalized: String, _ needles: [String]) -> Bool {
        needles.contains { normalized.contains(normalize($0)) }
    }

    private static func hasCreateVerb(_ t: String) -> Bool {
        matches(t, ["cree", "créer", "creer", "ajoute", "ajouter", "nouvelle", "nouveau", "commence", "commencer",
                    "mets", "mettre", "demarre", "démarre", "lance", "note moi", "rappelle", "il faut", "faut que", "je veux", "j'aimerais"])
    }

    /// Extrait le sujet après le premier mot-déclencheur trouvé, nettoie les mots outils.
    private static func subject(from raw: String, after triggers: [String]) -> String {
        for trig in triggers {
            if let r = raw.range(of: trig, options: [.caseInsensitive, .diacriticInsensitive]) {
                var tail = String(raw[r.upperBound...])
                // enlève une ponctuation/filler de tête
                tail = tail.trimmingCharacters(in: CharacterSet(charactersIn: " :,'’-"))
                for filler in ["de ", "d'", "d’", "une ", "un ", "le ", "la ", "les ", "que je ", "que ", "je ", "dois ", "moi ", "pour ", "a ", "à ", "mon ", "ma "] {
                    if normalize(tail).hasPrefix(normalize(filler)) {
                        tail = String(tail.dropFirst(filler.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                return tail.trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }

    /// Renvoie le sujet nettoyé s'il est exploitable, sinon nil (trop court / mot générique).
    private static func meaningful(_ s: String) -> String? {
        let cleaned = s.trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        let generic = ["quotidienne", "quotidien", "journaliere", "journalière", "tous les jours", "chaque jour", "quelque chose", "truc"]
        guard cleaned.count >= 3, !generic.contains(normalize(cleaned)) else { return nil }
        return cleaned.prefix(1).uppercased() + cleaned.dropFirst()
    }

    private static func iconFor(_ name: String) -> String {
        let n = normalize(name)
        if n.contains("medit") || n.contains("respir") || n.contains("calme") { return "figure.mind.and.body" }
        if n.contains("eau") || n.contains("boire") || n.contains("hydrat") { return "drop.fill" }
        if n.contains("sport") || n.contains("gym") || n.contains("course") || n.contains("muscu") || n.contains("marche") { return "figure.run" }
        if n.contains("lire") || n.contains("lecture") || n.contains("livre") || n.contains("page") { return "book.fill" }
        if n.contains("dorm") || n.contains("couch") || n.contains("sommeil") { return "moon.fill" }
        if n.contains("ecrire") || n.contains("journal") || n.contains("note") { return "pencil" }
        if n.contains("etir") || n.contains("stretch") || n.contains("yoga") { return "figure.flexibility" }
        return "checkmark.seal.fill"
    }

    private static func greet(_ name: String) -> String {
        let h = Calendar.current.component(.hour, from: .now)
        let base = (h < 6 || h >= 18) ? "Bonsoir" : "Bonjour"
        return name.isEmpty ? base : "\(base) \(name)"
    }

    private static func moodEmoji(_ s: Int) -> String { String(s) }

    // MARK: - Générateurs de contenu réel

    private struct MuscleGroup { let keys: [String]; let title: String; let ex: [String] }
    private static let muscleGroups: [MuscleGroup] = [
        .init(keys: ["pec", "poitrine", "chest"], title: "PECS",
              ex: ["Développé couché haltères — 4 × 8-10", "Développé incliné — 3 × 10",
                   "Écarté à la poulie — 3 × 12", "Dips lestés — 3 × échec"]),
        .init(keys: ["epaul", "delto", "shoulder"], title: "ÉPAULES",
              ex: ["Développé militaire — 4 × 8-10", "Élévations latérales — 4 × 15",
                   "Oiseau (arrière d'épaule) — 3 × 15", "Face pull — 3 × 15"]),
        .init(keys: ["dos", "back", "tirage", "traction"], title: "DOS",
              ex: ["Tractions — 4 × max", "Rowing haltère — 4 × 10",
                   "Tirage horizontal — 3 × 12", "Tirage vertical — 3 × 12"]),
        .init(keys: ["jambe", "leg", "quadri", "fessier", "cuisse", "squat"], title: "JAMBES",
              ex: ["Squat — 4 × 8", "Presse — 4 × 12", "Fentes — 3 × 12 / jambe",
                   "Leg curl — 3 × 15", "Mollets — 4 × 20"]),
        .init(keys: ["biceps", "triceps", "bras", "curl"], title: "BRAS",
              ex: ["Curl barre — 4 × 10", "Curl incliné — 3 × 12",
                   "Barre au front — 4 × 10", "Extension poulie — 3 × 15"]),
        .init(keys: ["abdo", "core", "gainage", "ventre"], title: "ABDOS",
              ex: ["Gainage — 3 × 60 s", "Relevés de jambes — 3 × 15",
                   "Crunch à la poulie — 3 × 20", "Russian twist — 3 × 20"]),
    ]

    /// Génère une VRAIE séance structurée selon le(s) muscle(s) ciblé(s).
    private static func workoutPlan(_ raw: String) -> String? {
        let t = normalize(raw)
        guard matches(t, ["plan de salle", "programme", "seance", "entrainement", "entraine",
                          "muscu", "salle de sport", "exercice", "workout", "plan sport", "planning sport",
                          "fais moi un plan", "plan de sport"]) else { return nil }

        var picked = muscleGroups.filter { g in g.keys.contains { t.contains(normalize($0)) } }
        if picked.isEmpty {
            if matches(t, ["haut du corps", "push", "pousser", "haut"]) {
                picked = muscleGroups.filter { ["PECS", "ÉPAULES", "BRAS"].contains($0.title) }
            } else if matches(t, ["bas du corps", "jambe", "leg", "bas"]) {
                picked = muscleGroups.filter { $0.title == "JAMBES" }
            } else if matches(t, ["full body", "complet", "tout le corps", "full"]) {
                picked = [muscleGroups[0], muscleGroups[2], muscleGroups[3], muscleGroups[5]]
            } else {
                picked = [muscleGroups[0], muscleGroups[1]]   // par défaut : push (pecs + épaules)
            }
        }
        // Nombre d'exos par groupe selon le nombre de groupes ciblés.
        let perGroup = picked.count == 1 ? 5 : (picked.count == 2 ? 3 : 2)

        var lines = ["💪 **Séance \(picked.map(\.title).joined(separator: " + "))** — ~45-55 min", ""]
        lines.append("Échauffement : 5-10 min de cardio léger + mobilité articulaire.")
        lines.append("")
        for g in picked {
            lines.append("**\(g.title)**")
            for e in g.ex.prefix(perGroup) { lines.append("• \(e)") }
            lines.append("")
        }
        lines.append("Repos 60-90 s entre les séries · progresse en charge chaque semaine.")
        lines.append("Étire-toi 5 min à la fin. Tu veux que je la programme ? Dis-moi le jour (ex. « ajoute-la lundi »).")
        return lines.joined(separator: "\n")
    }

    /// Journée alimentaire type, calibrée sur l'objectif kcal.
    private static func mealPlan(_ raw: String) -> String? {
        let t = normalize(raw)
        guard matches(t, ["plan alimentaire", "plan repas", "que manger", "menu", "regime", "quoi manger",
                          "journee type", "plan nutrition", "idee repas", "manger quoi"]) else { return nil }
        let goal = UserDefaults.standard.integer(forKey: "kcalGoal").nonZero(or: 2200)
        let bkf = Int(Double(goal) * 0.25), lunch = Int(Double(goal) * 0.35)
        let snack = Int(Double(goal) * 0.10), dinner = goal - bkf - lunch - snack
        return """
        🍽️ **Journée type (~\(goal) kcal)**

        **Petit-déj (~\(bkf) kcal)**
        • Flocons d'avoine + fruits + 2 œufs, ou skyr + granola.
        **Déjeuner (~\(lunch) kcal)**
        • Protéine (poulet/poisson/tofu) + riz/quinoa + légumes + huile d'olive.
        **Collation (~\(snack) kcal)**
        • Fruit + poignée d'amandes, ou fromage blanc.
        **Dîner (~\(dinner) kcal)**
        • Protéine maigre + légumes verts + patate douce.

        Vise ~1,6-2 g de protéines / kg. Envoie-moi une photo de ton assiette et je logue les calories.
        """
    }

    /// Coup de boost quand la motivation manque.
    private static func motivation(_ t: String) -> String? {
        guard matches(t, ["motive", "motivation", "pas envie", "flemme", "demotive", "demotivation",
                          "j'abandonne", "jabandonne", "dur", "decourage"]) else { return nil }
        let lines = [
            "Tu n'as pas à être motivé, juste à commencer 5 min — le reste suit. 💪",
            "Le futur toi te remerciera pour ce que tu fais MAINTENANT. On y va, une action.",
            "La discipline bat la motivation. Fais juste la première étape, même minuscule. 🔥",
            "Chaque jour où tu tiens, tu deviens quelqu'un sur qui tu peux compter. Go.",
        ]
        // Choix « pseudo-aléatoire » stable dans la journée (pas de Date.now interdit ici → heure).
        let idx = Calendar.current.component(.hour, from: .now) % lines.count
        return lines[idx]
    }

    private static func capabilities() -> String {
        "Voici ce que je sais faire, directement sur ton iPhone :\n\n"
        + "💪 **Programme sport** — « fais-moi un plan de salle, objectif épaules / pecs »\n"
        + "🍽️ **Plan alimentaire** — « donne-moi une journée type de repas »\n"
        + "🆕 **Créer** — « crée une habitude Méditer 10 min », « rappelle-moi d'appeler le dentiste »\n"
        + "💧 **Logger** — « j'ai bu un verre d'eau »\n"
        + "📊 **Bilan / sommeil / planning** — « fais-moi un bilan », « comment j'ai dormi ? », « mes tâches »\n\n"
        + "Envoie-moi aussi une photo (assiette → calories, document → à classer)."
    }
}

private extension Int {
    func nonZero(or fallback: Int) -> Int { self == 0 ? fallback : self }
}
