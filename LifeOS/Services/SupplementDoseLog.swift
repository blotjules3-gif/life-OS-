import Foundation
import SwiftData

/// Prise notee depuis la notification « Tu as bien pris ton … ? » (bouton Oui).
/// Avant (lot 6), ce bouton ne cochait que la serie : l'historique des prises et le
/// stock ne bougeaient que depuis l'ecran SuppSafe.
@MainActor
enum SupplementDoseLog {
    /// Heure prevue a laquelle rattacher la prise : la derniere de la journee deja
    /// passee, sinon la premiere (prise en avance).
    static func slot(for now: Date, times: [SupplementSchedule.Time], calendar: Calendar = .current) -> SupplementSchedule.Time? {
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let sorted = times.sorted { $0.hour * 60 + $0.minute < $1.hour * 60 + $1.minute }
        return sorted.last { $0.hour * 60 + $0.minute <= minutes } ?? sorted.first
    }

    /// `confirmKey` = "supp.<stableID>". Rend true si une prise a ete enregistree.
    @discardableResult
    static func logTaken(confirmKey: String, in ctx: ModelContext, now: Date = .now) -> Bool {
        let prefix = SupplementSchedule.baseID("")
        guard confirmKey.hasPrefix(prefix) else { return false }
        let sid = String(confirmKey.dropFirst(prefix.count))
        guard !sid.isEmpty,
              let s = (try? ctx.fetch(FetchDescriptor<Supplement>()))?.first(where: { $0.stableID == sid }),
              let t = slot(for: now, times: SupplementSchedule.times(raw: s.timesRaw, hour: s.hour, minute: s.minute))
        else { return false }
        let cal = Calendar.current
        let already = ((try? ctx.fetch(FetchDescriptor<SupplementDose>())) ?? []).contains {
            $0.supplementKey == sid && cal.isDate($0.day, inSameDayAs: now) && $0.hour == t.hour && $0.minute == t.minute
        }
        guard !already else { return false }   // pas de double comptage du stock
        ctx.insert(SupplementDose(supplementKey: sid, name: s.name, day: now, hour: t.hour, minute: t.minute, state: "taken", loggedAt: now))
        if s.trackStock { s.stock = SupplementSchedule.stock(after: s.stock, unitsPerDose: s.unitsPerDose, taken: true, undo: false) }
        do { try ctx.save() } catch { ctx.rollback(); return false }
        SupplementScheduler.apply(s)
        return true
    }
}
