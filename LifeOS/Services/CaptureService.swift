import Foundation
import SwiftData

/// Enregistre une capture validee par les chemins officiels de chaque domaine,
/// puis permet de l'annuler pour de vrai (suppression de ce qui a ete cree).
///
/// - tache : `TaskInbox` (meme lecture que Todoo, uid stable), rappel par `TaskReminders` ;
/// - depense : `LedgerService` (solde recalcule, montant negatif) ;
/// - note : le modele `Note` de Notio.
@MainActor
enum CaptureService {
    enum CaptureError: LocalizedError, Equatable {
        case emptyTitle, missingAmount, noAccount, accountNotFound, unresolved
        var errorDescription: String? {
            switch self {
            case .emptyTitle: return "Écris au moins un mot."
            case .missingAmount: return "Indique un montant valide."
            case .noAccount: return "Crée d'abord un compte dans Bankino : une dépense doit appartenir à un compte."
            case .accountNotFound: return "Compte introuvable. Choisis un compte existant."
            case .unresolved: return "Confirme les champs surlignés avant d'enregistrer."
            }
        }
    }

    /// Ce qui a ete cree, pour l'annulation.
    enum Receipt {
        case task(TodoItem)
        case expense(Txn)
        case note(Note)

        var label: String {
            switch self {
            case .task: return "Tâche ajoutée"
            case .expense: return "Dépense enregistrée"
            case .note: return "Note enregistrée"
            }
        }
    }

    /// Valeurs finales de l'ecran d'apercu (apres corrections).
    struct Draft {
        var kind: CaptureKind
        var title: String
        var date: Date?
        var hasTime: Bool
        var amount: Double?
        var category: String
        var accountID: UUID?
        var noteBody: String
        var parsedTask: ParsedTask?
        /// -1 aucun rappel, 0 a l'heure (TodoItem.reminderMinutes).
        var reminderMinutes: Int = -1
    }

    /// Le compte propose par defaut : le compte courant, sinon le premier.
    static func defaultAccount(_ accounts: [Account]) -> Account? {
        accounts.first(where: { $0.kind == "Courant" }) ?? accounts.first
    }

    static func save(_ d: Draft, in ctx: ModelContext) throws -> Receipt {
        let title = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let receipt: Receipt
        switch d.kind {
        case .task:
            guard !title.isEmpty else { throw CaptureError.emptyTitle }
            let t = TaskInbox.makeTodo(parsed: d.parsedTask ?? ParsedTask(), title: title, due: d.date)
            t.reminderMinutes = (d.date != nil && d.hasTime) ? d.reminderMinutes : -1
            ctx.insert(t)
            receipt = .task(t)
        case .expense:
            guard let a = d.amount, a.isFinite, a > 0 else { throw CaptureError.missingAmount }
            let accounts = (try? ctx.fetch(FetchDescriptor<Account>())) ?? []
            guard !accounts.isEmpty else { throw CaptureError.noAccount }
            guard let id = d.accountID, let acc = accounts.first(where: { $0.id == id }) else {
                throw CaptureError.accountNotFound
            }
            let txn = LedgerService.addTransaction(ctx, amount: -abs(a), category: d.category,
                                                   account: acc, note: title, date: d.date ?? .now)
            receipt = .expense(txn)
        case .note:
            let body = d.noteBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !body.isEmpty else { throw CaptureError.emptyTitle }
            let n = Note(title: title.isEmpty ? String(body.prefix(60)) : title, body: body)
            n.modified = .now
            ctx.insert(n)
            receipt = .note(n)
        }
        do {
            try ctx.save()
        } catch {
            ctx.rollback()
            throw error
        }
        if case .task(let t) = receipt, t.reminderMinutes >= 0 { TaskReminders.schedule(t) }
        return receipt
    }

    /// Annule une capture : supprime ce qui a ete cree et remet le solde.
    static func undo(_ r: Receipt, in ctx: ModelContext) throws {
        switch r {
        case .task(let t):
            TaskReminders.cancel(t)
            ctx.delete(t)
        case .expense(let txn):
            LedgerService.deleteTransaction(ctx, txn)
        case .note(let n):
            ctx.delete(n)
        }
        try ctx.save()
    }
}
