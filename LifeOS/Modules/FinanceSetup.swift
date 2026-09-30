import SwiftUI
import SwiftData

// MARK: - Formulaire de configuration « Finances perso »
// Pré-remplit : budget mensuel, compte courant, abonnements connus. Idempotent.

struct FinanceSetupView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var accounts: [Account]
    @Query private var subs: [Subscription]
    @AppStorage(AppStorageKeys.budgetGoal) private var budgetGoal = 1500

    @State private var budget = 1500
    @State private var balance = 1000
    @State private var chosenSubs: Set<String> = []

    private let tint = AppCategory.finance.tint

    // Abonnements courants avec coût mensuel indicatif (€).
    private let subOptions: [(String, Double)] = [
        ("Netflix", 13.49), ("Spotify", 11.99), ("Disney+", 8.99), ("Amazon Prime", 6.99),
        ("Salle de sport", 30), ("Forfait mobile", 15), ("Internet box", 30), ("iCloud", 2.99),
        ("YouTube Premium", 12.99), ("Assurance habitation", 20), ("Canal+", 25), ("Deezer", 11.99)
    ]

    var body: some View {
        SetupFlow(title: "Finances perso", accent: tint, pages: pages, onComplete: commit,
                  previewNotes: ["Tes opérations déjà saisies ne changent pas."],
                  preview: previewChanges, draft: draftIO)
            .onAppear {
                budget = budgetGoal
                if let main = accounts.first(where: { $0.kind == "Courant" }) { balance = Int(main.balance) }
                chosenSubs = Set(subs.map { $0.name }.filter { name in subOptions.contains { $0.0 == name } })
            }
    }

    private var pages: [SetupPage] {
        [
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "creditcard.fill", title: "Ton budget mensuel",
                                subtitle: "Ce que tu veux pouvoir dépenser par mois (hors loyer/charges fixes).",
                                accent: tint)
                    SetupNumber(value: $budget, unit: "€", range: 200...10000, step: 50, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "eurosign.bank.building", title: "Solde de ton compte courant",
                                subtitle: "Approximatif — tu l'ajusteras quand tu veux.", accent: tint)
                    SetupNumber(value: $balance, unit: "€", range: -2000...100000, step: 50, accent: tint)
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "repeat.circle.fill", title: "Tes abonnements",
                                subtitle: "On les suit pour calculer ce qui part chaque mois.", accent: tint)
                    SetupMultiChoice(options: subOptions.map { $0.0 }, selection: $chosenSubs, accent: tint)
                    monthlyTotal
                }
            },
            SetupPage {
                VStack(spacing: 16) {
                    SetupHeader(icon: "checkmark.seal.fill", title: "C'est prêt !",
                                subtitle: "Budget, compte et abonnements sont configurés.", accent: tint)
                    finalSummary
                }
            }
        ]
    }

    private var subTotal: Double {
        subOptions.filter { chosenSubs.contains($0.0) }.reduce(0) { $0 + $1.1 }
    }
    private var monthlyTotal: some View {
        Text("≈ \(String(format: "%.2f", subTotal)) € / mois d'abonnements")
            .font(.subheadline.weight(.semibold)).foregroundStyle(tint).padding(.top, 4)
    }
    private var finalSummary: some View {
        VStack(spacing: 10) {
            row("creditcard", "Budget mensuel : \(budget) €")
            row("eurosign.circle", "Compte courant : \(balance) €")
            row("repeat", "\(chosenSubs.count) abonnements (\(String(format: "%.0f", subTotal)) €/mois)")
        }
    }
    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 24)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(14).raisedSurface(RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 14)
    }

    private func previewChanges() -> [SetupSession.Change] {
        let main = accounts.first(where: { $0.kind == "Courant" })
        let euros: (Double) -> String = { $0.formatted(.currency(code: "EUR").precision(.fractionLength(0))) }
        let existing = Set(subs.map(\.name))
        let added = subOptions.map(\.0).filter { chosenSubs.contains($0) && !existing.contains($0) }
        let removed = subs.map(\.name).filter { n in subOptions.contains { $0.0 == n } && !chosenSubs.contains(n) }
        return [
            .make("Budget mensuel", euros(Double(budgetGoal)), euros(Double(budget))),
            .make(main == nil ? "Compte courant (créé)" : "Solde du compte courant",
                  main.map { euros($0.balance) } ?? "—", euros(Double(balance))),
            added.isEmpty ? nil : .make("Abonnements ajoutés", "—", added.joined(separator: ", ")),
            removed.isEmpty ? nil : .make("Abonnements retirés", removed.joined(separator: ", "), "—"),
        ].compactMap { $0 }
    }

    private func commit() {
        budgetGoal = budget
        // Compte courant — mise à jour si déjà présent (idempotent).
        if let main = accounts.first(where: { $0.kind == "Courant" }) {
            LedgerService.setCurrentBalance(ctx, account: main, to: Double(balance))
        } else {
            ctx.insert(Account(name: "Compte courant", kind: "Courant", balance: Double(balance)))
        }
        // Abonnements — n'ajoute que les nouveaux ; retire ceux décochés qui venaient de la liste.
        let existingNames = Set(subs.map { $0.name })
        for (name, amount) in subOptions where chosenSubs.contains(name) && !existingNames.contains(name) {
            ctx.insert(Subscription(name: name, amount: amount, cycle: "Mensuel"))
        }
        for s in subs where subOptions.contains(where: { $0.0 == s.name }) && !chosenSubs.contains(s.name) {
            ctx.delete(s)
        }
        do { try ctx.save() } catch { AppLog.data.error("FinanceSetup save failed: \(error.localizedDescription, privacy: .public)") }
        CategorySetup.markDone(.finance)
        Haptics.success()
    }

    /// Reponses gardees entre deux lancements (voir SetupDraft).
    private var draftIO: SetupDraftIO {
        SetupDraftIO(save: {
            var d = SetupDraft()
            d.put("budget", budget)
            d.put("balance", balance)
            d.put("chosenSubs", chosenSubs)
            return d
        }, restore: { d in
            if let v = d.int("budget") { budget = v }
            if let v = d.int("balance") { balance = v }
            if let v = d.set("chosenSubs") { chosenSubs = v }
        })
    }
}
