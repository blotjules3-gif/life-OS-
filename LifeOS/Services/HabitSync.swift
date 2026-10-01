import Foundation
import SwiftData
import WidgetKit

/// Lien entre la base des habitudes et ce qui vit hors de l'app (widgets,
/// actions de notification). Remplace `WidgetToggleReconciler`, qui trouvait
/// l'habitude par son NOM et INVERSAIT son etat (un double appui s'annulait, deux
/// habitudes homonymes etaient touchees, et la file etait videe avant d'etre
/// appliquee: un arret en cours perdait les gestes).
@MainActor
enum HabitSync {
    static let widgetKinds = ["InteractiveHabitsWidget", "HabitsWidget"]

    /// Donne un identifiant stable aux habitudes creees avant son existence.
    @discardableResult
    static func ensureIDs(_ ctx: ModelContext) -> Int {
        guard let habits = try? ctx.fetch(FetchDescriptor<Habit>()) else { return 0 }
        var seen = Set<String>(), fixed = 0
        for h in habits {
            // Vide, ou double (copie de fiche): nouvel identifiant.
            if h.uid.isEmpty || seen.contains(h.uid) { h.uid = UUID().uuidString; fixed += 1 }
            seen.insert(h.uid)
        }
        if fixed > 0 { try? ctx.save() }
        return fixed
    }

    /// Applique les ordres en attente. Chaque fichier n'est efface qu'apres une
    /// sauvegarde reussie: un arret en cours les laisse en file, et comme chaque
    /// ordre est explicite, le rejouer donne le meme resultat. Rend le nombre
    /// d'ordres traites.
    @discardableResult
    static func drain(_ ctx: ModelContext) -> Int {
        migrateLegacyQueue(ctx)
        let pending = HabitOps.pending()
        guard !pending.isEmpty else { return 0 }
        // Une lecture en erreur n'est PAS une base vide: sinon chaque ordre passerait
        // pour "habitude supprimee" et serait acquitte, donc perdu. On garde la file.
        let habits: [Habit]
        do { habits = try fetchHabits(ctx) } catch {
            AppLog.data.error("HabitSync: lecture des habitudes impossible, ordres gardés en file: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        let byID = Dictionary(habits.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for (_, op) in pending {
            // Habitude supprimee depuis: l'ordre n'a plus d'objet, il est simplement acquitte.
            guard let habit = byID[op.habitID] else { continue }
            apply(op, to: habit, ctx: ctx)
        }
        do {
            try ctx.save()
            pending.forEach { HabitOps.acknowledge($0.url) }
        } catch {
            AppLog.data.error("HabitSync: sauvegarde refusée, ordres gardés en file: \(error.localizedDescription, privacy: .public)")
            return 0
        }
        return pending.count
    }

    static func apply(_ op: HabitOp, to habit: Habit, ctx: ModelContext) {
        let tz = TimeZone(identifier: op.timeZone) ?? .current
        var cal = Calendar(identifier: .gregorian); cal.timeZone = tz
        let sameDay = habit.completions.filter { HabitOps.businessDay($0.date, timeZone: tz) == op.day }
        switch op.action {
        case .complete:
            guard sameDay.isEmpty, let dayStart = date(op.day, cal: cal) else { return }
            // Midi du jour metier: aucun changement d'heure ne le fait glisser d'un jour.
            habit.completions.append(HabitCompletion(date: dayStart.addingTimeInterval(12 * 3600)))
        case .uncomplete:
            // Retirer de la relation AVANT de supprimer: sinon la liste en memoire de
            // l'habitude garde l'element jusqu'au prochain rechargement.
            let ids = Set(sameDay.map(\.persistentModelID))
            habit.completions.removeAll { ids.contains($0.persistentModelID) }
            sameDay.forEach { ctx.delete($0) }
        }
    }

    private static func date(_ day: String, cal: Calendar) -> Date? {
        let p = day.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return cal.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// L'ancienne file (noms + horodatages, sens "inverser") est convertie une fois:
    /// un nom porte par UNE seule habitude devient un ordre "cocher"; ambigu ou
    /// inconnu, il est abandonne plutot que de toucher la mauvaise habitude.
    ///
    /// Une entree n'est retiree de l'ancienne file qu'une fois son ordre ecrit sur
    /// disque, ou quand elle est volontairement abandonnee (nom ambigu ou inconnu).
    /// Lecture de la base en erreur: rien n'est touche, on reessaiera.
    static func migrateLegacyQueue(_ ctx: ModelContext) {
        guard let d = LifeOSGroup.defaults, let old = d.array(forKey: "widget_pending_toggles") as? [[String: Any]], !old.isEmpty else { return }
        let habits: [Habit]
        do { habits = try fetchHabits(ctx) } catch {
            AppLog.data.error("HabitSync: migration reportée, lecture impossible: \(error.localizedDescription, privacy: .public)")
            return
        }
        var kept: [[String: Any]] = []
        for entry in old {
            guard let name = entry["habitName"] as? String else { continue }
            let matches = habits.filter { $0.name == name }
            guard matches.count == 1, !matches[0].uid.isEmpty else { continue }
            let at = Date(timeIntervalSince1970: entry["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970)
            do {
                try HabitOps.enqueue(HabitOp(habitID: matches[0].uid, action: .complete, at: at, source: "legacy"))
            } catch {
                AppLog.data.error("HabitSync: ordre migré non écrit, gardé dans l'ancienne file: \(error.localizedDescription, privacy: .public)")
                kept.append(entry)
            }
        }
        if kept.isEmpty { d.removeObject(forKey: "widget_pending_toggles") }
        else { d.set(kept, forKey: "widget_pending_toggles") }
    }

    /// Point unique de lecture, remplacable dans les tests pour simuler une panne.
    nonisolated(unsafe) static var fetchOverride: ((ModelContext) throws -> [Habit])?
    private static func fetchHabits(_ ctx: ModelContext) throws -> [Habit] {
        if let fetchOverride { return try fetchOverride(ctx) }
        return try ctx.fetch(FetchDescriptor<Habit>())
    }

    /// Publie l'instantane lu par les widgets (habitudes actives aujourd'hui, non
    /// archivees) et demande le rafraichissement des widgets concernes. Seul endroit
    /// qui ecrit cet instantane.
    static func publish(_ ctx: ModelContext, now: Date = Date(), timeZone: TimeZone = .current) {
        guard let d = LifeOSGroup.defaults else { return }
        let habits = ((try? ctx.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? [])
            // Meme liste du jour que l'app : sautees, en pause ou « x fois par semaine » deja
            // atteintes exclues ; une habitude faite aujourd'hui reste.
            .filter { !$0.isArchived && !$0.uid.isEmpty && HabitRules.isDueToday($0, now: now) }
        let today = HabitOps.businessDay(now, timeZone: timeZone)
        let entries = habits.map { h in
            HabitSnapshot.Entry(id: h.uid, name: h.name, icon: h.icon, colorHex: h.colorHex,
                                done: h.completions.contains { HabitOps.businessDay($0.date, timeZone: timeZone) == today })
        }
        // Ordres pas encore appliques (app a peine ouverte): l'instantane les montre deja.
        var snap = HabitSnapshot(day: today, timeZone: timeZone.identifier, generatedAt: now, habits: entries)
        for (_, op) in HabitOps.pending() where op.day == today { snap = snap.applying(op) }
        snap.write(to: d)
        // Resume lu par le coach et l'accueil.
        let done = snap.habits.filter(\.done)
        d.set(done.count, forKey: "habits_done_today")
        d.set(snap.habits.count, forKey: "habits_total_today")
        widgetKinds.forEach { WidgetCenter.shared.reloadTimelines(ofKind: $0) }
    }

    /// Ce qu'il faut faire au lancement et a chaque retour au premier plan.
    static func refresh(_ ctx: ModelContext) {
        ensureIDs(ctx)
        drain(ctx)
        publish(ctx)
    }
}
