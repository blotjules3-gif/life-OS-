import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var finTint: Color { AppCategory.finance.tint } }

/// Champ de montant avec son erreur sous le champ (voir `AmountInput`).
/// L'erreur n'apparait qu'une fois quelque chose tape: un formulaire neuf ne
/// s'ouvre pas en rouge.
private struct AmountRow: View {
    let title: String
    @Binding var text: String
    var rules: AmountInput.Rules = .positive

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title); Spacer()
                TextField("0", text: $text)
                    .keyboardType(rules.allowNegative ? .numbersAndPunctuation : .decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if !text.isEmpty, let m = AmountInput.parse(text, rules: rules).message {
                Text(m).font(.caption).foregroundStyle(Theme.warning)
            }
        }
    }
}

/// Enregistre et ne ferme le formulaire que si la base a bien ecrit.
@MainActor
private func commitForm(_ ctx: ModelContext, error message: Binding<String?>, dismiss: DismissAction) {
    do { try ctx.save(); dismiss() }
    catch { ctx.rollback(); message.wrappedValue = "Enregistrement impossible, réessaie. (\(error.localizedDescription))" }
}

private struct FormError: View {
    let message: String?
    var body: some View {
        if let message {
            Section { Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning) }
        }
    }
}

// MARK: - Hub Finances


// MARK: - Comptes & dépenses

struct AccountsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var accounts: [Account]
    @Query(sort: \Txn.date, order: .reverse) private var txns: [Txn]
    @State private var showAddAccount = false
    @State private var showAddTxn = false

    private var total: Double { accounts.reduce(0) { $0 + $1.balance } }
    private var monthSpend: Double { txns.filter { $0.amount < 0 && Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }.reduce(0) { $0 + abs($1.amount) } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Patrimoine liquide").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(total, format: .currency(code: "EUR")).font(.system(size: 36, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Text("Dépensé ce mois : \(monthSpend, format: .currency(code: "EUR"))").font(.caption).foregroundStyle(Theme.warning)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    // Alerte dépense anormale / risque découvert
                    if let alert = anomalyAlert() {
                        HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger); Text(alert).font(.footnote).foregroundStyle(Theme.textPrimary) }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Theme.danger.opacity(0.20), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }

                    HStack {
                        SectionHeader(title: "Comptes")
                        Button { showAddAccount = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }.accessibilityLabel("Ajouter un compte")
                    }
                    ForEach(accounts) { a in
                        HStack {
                            Image(systemName: a.kind == "Épargne" ? "banknote" : a.kind == "Cash" ? "eurosign.circle" : "creditcard").foregroundStyle(.finTint)
                            VStack(alignment: .leading) { Text(a.name).foregroundStyle(Theme.textPrimary); Text(a.kind).font(.caption).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Text(a.balance, format: .currency(code: "EUR")).bold().foregroundStyle(a.balance < 0 ? Theme.danger : Theme.textPrimary)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { LedgerService.deleteAccount(ctx, a) } label: { Label("Supprimer", systemImage: "trash") } }
                    }

                    HStack {
                        SectionHeader(title: "Dernières opérations")
                        Button { showAddTxn = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }.accessibilityLabel("Ajouter une transaction")
                    }
                    if txns.isEmpty { Text("Aucune opération.").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    ForEach(txns.prefix(15)) { t in
                        HStack {
                            VStack(alignment: .leading) { Text(t.note.isEmpty ? t.category : t.note).foregroundStyle(Theme.textPrimary); Text(t.date, style: .date).font(.caption).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Text(t.amount, format: .currency(code: "EUR")).bold().foregroundStyle(t.amount < 0 ? Theme.danger : Theme.success)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { LedgerService.deleteTransaction(ctx, t) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Comptes & dépenses").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAccount) { AccountEditor() }
        .sheet(isPresented: $showAddTxn) { TxnEditor(accounts: accounts) }
    }
    private func anomalyAlert() -> String? {
        if accounts.contains(where: { $0.balance < 0 }) { return "Un de tes comptes est à découvert." }
        let spends = txns.filter { $0.amount < 0 }.map { abs($0.amount) }
        guard spends.count >= 3 else { return nil }
        let avg = spends.reduce(0,+)/Double(spends.count)
        if let big = spends.first, big > avg * 3 { return "Dépense inhabituelle détectée : \(Int(big))€ (3× ta moyenne)." }
        return nil
    }
}

struct AccountEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var kind = "Courant"; @State private var balance = ""
    @State private var error: String?
    private var parsed: AmountInput.Parsed { AmountInput.parse(balance, rules: .init(required: false, allowNegative: true, allowZero: true)) }
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && parsed.message == nil }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du compte", text: $name)
                Picker("Type", selection: $kind) { ForEach(["Courant","Épargne","Cash"], id: \.self) { Text($0) } }
                AmountRow(title: "Solde", text: $balance, rules: .init(required: false, allowNegative: true, allowZero: true))
                FormError(message: error)
            }
            .navigationTitle("Nouveau compte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Account(name: name, kind: kind, balance: parsed.value ?? 0)); commitForm(ctx, error: $error, dismiss: dismiss) }.disabled(!canSave) }
            }
        }
    }
}

struct TxnEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    /// Les comptes eux-memes, pas leurs noms: avec deux comptes du meme nom,
    /// l'operation partait sur le premier trouve.
    let accounts: [Account]
    @State private var amount = ""; @State private var isExpense = true
    @State private var category = "Courses"; @State private var note = ""; @State private var accountID: UUID?
    @State private var error: String?
    private let cats = ["Courses","Restau","Transport","Logement","Loisirs","Santé","Shopping","Salaire","Divers"]
    private var parsed: AmountInput.Parsed { AmountInput.parse(amount) }
    var body: some View {
        NavigationStack {
            Form {
                // Sans compte, l'operation n'avait nulle part ou aller: le formulaire
                // se fermait et rien n'etait enregistre, sans un mot.
                if accounts.isEmpty {
                    Section { Label("Crée d'abord un compte : une opération doit appartenir à un compte.", systemImage: "info.circle") }
                }
                Picker("Type", selection: $isExpense) { Text("Dépense").tag(true); Text("Revenu").tag(false) }.pickerStyle(.segmented)
                AmountRow(title: "Montant", text: $amount)
                Picker("Catégorie", selection: $category) { ForEach(cats, id: \.self) { Text($0) } }
                if !accounts.isEmpty {
                    Picker("Compte", selection: $accountID) {
                        ForEach(accounts, id: \.id) { a in
                            Text("\(a.name.isEmpty ? a.kind : a.name) · \(a.kind)").tag(Optional(a.id))
                        }
                    }
                }
                TextField("Note", text: $note)
                FormError(message: error)
            }
            .navigationTitle("Nouvelle opération").navigationBarTitleDisplayMode(.inline)
            .onAppear { if accountID == nil { accountID = accounts.first?.id } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    guard let base = parsed.value else { return }
                    let v = base * (isExpense ? -1 : 1)
                    // Passe par LedgerService : le solde est RECALCULE depuis les
                    // operations. L'ancien code faisait `acc.balance += v` ici, et rien
                    // ne le defaisait a la suppression ou a la modification.
                    guard let id = accountID, let acc = LedgerService.account(ctx, id: id) else {
                        error = "Compte introuvable. Choisis un compte existant."
                        return
                    }
                    _ = LedgerService.addTransaction(ctx, amount: v, category: category, account: acc, note: note)
                    commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(parsed.value == nil || accounts.isEmpty) }
            }
        }
    }
}

// MARK: - Budget enveloppes

struct BudgetView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Envelope.name) private var envelopes: [Envelope]
    @Query(sort: \EnvelopeEntry.date, order: .reverse) private var entries: [EnvelopeEntry]
    @Query private var txns: [Txn]
    @State private var month = EnvelopeMath.monthKey(.now)
    @State private var showAdd = false
    @State private var editing: Envelope?
    @State private var addingTo: Envelope?
    @State private var editingEntry: EnvelopeEntry?
    @State private var error: String?

    private var monthTitle: String {
        EnvelopeMath.startOfMonth(month).formatted(.dateTime.month(.wide).year())
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    monthBar
                    if let error { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(Theme.warning) }
                    if envelopes.isEmpty {
                        EmptyState(icon: "tray.2", title: "Aucune enveloppe", message: "Crée des enveloppes (Courses, Loisirs…) avec un plafond mensuel. Les dépenses Bankino de la même catégorie y sont comptées.")
                    } else {
                        ForEach(envelopes) { e in envelopeCard(e) }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Budget enveloppes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nouvelle enveloppe") } }
        .sheet(isPresented: $showAdd) { EnvelopeEditor(envelope: nil) }
        .sheet(item: $editing) { EnvelopeEditor(envelope: $0) }
        .sheet(item: $addingTo) { e in EnvelopeEntryEditor(envelope: e, entry: nil, month: month) }
        .sheet(item: $editingEntry) { entry in
            if let e = envelopes.first(where: { $0.uid == entry.envelopeUID }) { EnvelopeEntryEditor(envelope: e, entry: entry, month: month) }
        }
        .onAppear {
            if EnvelopeMigration.run(ctx) { save("migration des enveloppes") }
        }
    }

    private var monthBar: some View {
        HStack {
            Button { month -= 1 } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Mois précédent")
            Spacer()
            Text(monthTitle.capitalized).font(.headline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { month += 1 } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Mois suivant")
                .disabled(month >= EnvelopeMath.monthKey(.now))
        }
        .card()
    }

    @ViewBuilder private func envelopeCard(_ e: Envelope) -> some View {
        let spent = Double(EnvelopeBudget.spentCents(e, month: month, entries: entries, txns: txns)) / 100
        let available = Double(EnvelopeBudget.availableCents(e, month: month, entries: entries, txns: txns)) / 100
        let budgetForMonth = e.monthlyBudget + (e.carryOver ? available + spent - e.monthlyBudget : 0)
        let progress = budgetForMonth > 0 ? min(1, max(0, spent / budgetForMonth)) : (spent > 0 ? 1 : 0)
        let mine = entries.filter { $0.envelopeUID == e.uid && EnvelopeMath.monthKey($0.date) == month }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Color(hex: UInt(e.colorHex))).frame(width: 12, height: 12)
                Text(e.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(spent, format: .currency(code: "EUR")) / \(budgetForMonth, format: .currency(code: "EUR"))")
                    .font(.subheadline.bold()).foregroundStyle(available < 0 ? Theme.danger : Theme.textPrimary)
            }
            ProgressView(value: progress).tint(available < 0 ? Theme.danger : Color(hex: UInt(e.colorHex)))
            HStack {
                Text(available >= 0 ? "Reste \(available.formatted(.currency(code: "EUR")))" : "Dépassé de \((-available).formatted(.currency(code: "EUR")))")
                    .font(.caption).foregroundStyle(available < 0 ? Theme.danger : Theme.textSecondary)
                Spacer()
                Button { addingTo = e } label: {
                    Label("Dépense", systemImage: "plus").font(.caption.bold())
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .glassControl(Capsule()).foregroundStyle(Theme.textPrimary)
                }.buttonStyle(.plain)
            }
            Text("Compte les opérations Bankino « \(e.countedCategory) »" + (e.carryOver ? " · report du reste activé" : ""))
                .font(.caption2).foregroundStyle(Theme.textSecondary)
            ForEach(mine) { entry in
                Button { editingEntry = entry } label: {
                    HStack {
                        Text(entry.date, format: .dateTime.day().month(.abbreviated)).font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(entry.note.isEmpty ? "Dépense" : entry.note).font(.caption).foregroundStyle(Theme.textPrimary).lineLimit(1)
                        Spacer()
                        Text(entry.amount, format: .currency(code: "EUR")).font(.caption.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    }
                }.buttonStyle(.plain)
                .contextMenu { Button(role: .destructive) { delete(entry) } label: { Label("Supprimer", systemImage: "trash") } }
            }
        }
        .card()
        .contextMenu {
            Button { editing = e } label: { Label("Modifier", systemImage: "pencil") }
            Button(role: .destructive) { delete(e) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func delete(_ entry: EnvelopeEntry) {
        ctx.delete(entry)
        save("suppression d'une dépense")
    }

    /// Supprimer l'enveloppe supprime ses ecritures ; les operations Bankino restent.
    private func delete(_ e: Envelope) {
        for entry in entries where entry.envelopeUID == e.uid { ctx.delete(entry) }
        ctx.delete(e)
        save("suppression d'une enveloppe")
    }

    private func save(_ what: String) {
        do { try ctx.save(); error = nil }
        catch { ctx.rollback(); self.error = "Enregistrement impossible (\(what)), réessaie." }
    }
}

struct EnvelopeEditor: View {
    let envelope: Envelope?
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var budget = ""; @State private var color = 0x2185FF
    @State private var category = ""; @State private var carry = false
    @State private var error: String?
    @State private var loaded = false
    private let colors = [0x2185FF, 0x47CC5C, 0xFF2E33, 0xFFB83D, 0xA852F5, 0x24C7CC]
    private let cats = ["Courses","Restau","Transport","Logement","Loisirs","Santé","Shopping","Divers"]
    private var parsed: AmountInput.Parsed { AmountInput.parse(budget) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Courses)", text: $name)
                AmountRow(title: "Plafond mensuel", text: $budget)
                Picker("Opérations Bankino comptées", selection: $category) {
                    Text("Catégorie du même nom").tag("")
                    ForEach(cats, id: \.self) { Text($0).tag($0) }
                }
                Toggle("Reporter le reste au mois suivant", isOn: $carry)
                HStack { ForEach(colors, id: \.self) { c in Circle().fill(Color(hex: UInt(c))).frame(width: 28, height: 28).overlay(color == c ? Circle().stroke(.white, lineWidth: 2) : nil).onTapGesture { color = c } } }
                FormError(message: error)
            }
            .navigationTitle(envelope == nil ? "Nouvelle enveloppe" : "Modifier l'enveloppe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(envelope == nil ? "Créer" : "Enregistrer") {
                    guard let b = parsed.value else { return }
                    let n = name.trimmingCharacters(in: .whitespaces)
                    if let e = envelope {
                        e.name = n; e.monthlyBudget = b; e.colorHex = color; e.linkedCategory = category; e.carryOver = carry
                    } else {
                        let e = Envelope(name: n, monthlyBudget: b, colorHex: color)
                        e.linkedCategory = category; e.carryOver = carry
                        ctx.insert(e)
                    }
                    commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsed.value == nil) }
            }
            .onAppear {
                guard !loaded, let e = envelope else { return }
                loaded = true
                name = e.name; budget = AmountInput.format(e.monthlyBudget); color = e.colorHex
                category = e.linkedCategory; carry = e.carryOver
            }
        }
    }
}

/// Ajouter ou corriger une depense d'enveloppe (montant, date, note).
struct EnvelopeEntryEditor: View {
    let envelope: Envelope
    let entry: EnvelopeEntry?
    let month: Int
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""; @State private var note = ""; @State private var date = Date.now
    @State private var error: String?
    @State private var loaded = false
    // Negatif autorise : un remboursement diminue la depense du mois.
    private var parsed: AmountInput.Parsed { AmountInput.parse(amount, rules: .init(allowNegative: true)) }
    var body: some View {
        NavigationStack {
            Form {
                AmountRow(title: "Montant", text: $amount, rules: .init(allowNegative: true))
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                TextField("Note (facultatif)", text: $note)
                Text("Un montant négatif est un remboursement.").font(.caption).foregroundStyle(Theme.textSecondary)
                FormError(message: error)
            }
            .navigationTitle(entry == nil ? "Dépense · \(envelope.name)" : "Modifier la dépense").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") {
                    guard let v = parsed.value, let uid = envelope.uid else { return }
                    let n = note.trimmingCharacters(in: .whitespaces)
                    if let entry {
                        entry.amountCents = EnvelopeBudget.cents(v); entry.date = date; entry.note = n
                    } else {
                        ctx.insert(EnvelopeEntry(envelopeUID: uid, date: date, amountCents: EnvelopeBudget.cents(v), note: n))
                    }
                    commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(parsed.value == nil || envelope.uid == nil) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let entry {
                    amount = AmountInput.format(entry.amount); note = entry.note; date = entry.date
                } else if month != EnvelopeMath.monthKey(.now) {
                    // Saisie retroactive : on se place dans le mois affiche.
                    date = min(.now, EnvelopeMath.startOfMonth(month))
                }
            }
        }
    }
}

// MARK: - Abonnements

struct SubscriptionsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var subs: [Subscription]
    @State private var showAdd = false
    private var monthlyTotal: Double { subs.filter { $0.active }.reduce(0) { $0 + $1.monthlyCost } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Coût mensuel des abonnements").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(monthlyTotal, format: .currency(code: "EUR")).font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        Text("Soit \(monthlyTotal*12, format: .currency(code: "EUR")) / an").font(.caption).foregroundStyle(Theme.warning)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    ForEach(subs) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(s.name).font(.headline).foregroundStyle(s.active ? Theme.textPrimary : Theme.textSecondary)
                                Spacer()
                                Text("\(s.amount, format: .currency(code: "EUR"))/\(s.cycle == "Annuel" ? "an" : "mois")").bold().foregroundStyle(.finTint)
                            }
                            HStack {
                                Text("Prochain : \(s.nextDate, style: .date)").font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Toggle("Actif", isOn: Binding(get: { s.active }, set: { s.active = $0; advanceDueDates() })).labelsHidden().tint(.finTint)
                                Link(destination: cancelURL(s.name)) { Text("Résilier").font(.caption.bold()).foregroundStyle(Theme.danger) }
                            }
                        }.card()
                            .contextMenu { Button(role: .destructive) { ctx.delete(s) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    IntegrationNotice(text: "La détection automatique des abonnements oubliés (analyse de tes relevés) et la résiliation « en un tap » nécessitent l'agrégation bancaire (voir module dédié) + des mandats de résiliation. Ici tu les listes et le bouton Résilier ouvre une recherche d'aide à la résiliation.")
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Abonnements").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { SubscriptionEditor() }
        .onAppear { advanceDueDates() }
        .onChange(of: subs.count) { _, _ in advanceDueDates() }
    }

    /// `nextDate` n'avancait jamais: « Prochain » montrait une date passee, et le
    /// badge « Oublié ? » (date + 2 mois) s'allumait sur tout abonnement actif, y
    /// compris ceux du questionnaire crees avec la date du jour. Ce badge n'avait
    /// aucune donnee d'usage derriere lui: il est retire. La date avance au cycle.
    private func advanceDueDates() {
        var changed = false
        for s in subs where s.active {
            let next = Self.nextChargeDate(from: s.nextDate, cycle: s.cycle)
            if next != s.nextDate { s.nextDate = next; changed = true }
        }
        if changed { LifeOSTry(try ctx.save(), context: "prochain prelevement", category: AppLog.data) }
    }

    /// Premiere echeance a partir d'aujourd'hui, en comptant depuis la date de
    /// depart (31 janv. donne 28 fev. puis 31 mars, sans glisser au 28).
    static func nextChargeDate(from start: Date, cycle: String, now: Date = .now,
                               calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard start < today else { return start }
        let unit: Calendar.Component = cycle == "Annuel" ? .year : .month
        for k in 1...1200 {
            if let d = calendar.date(byAdding: unit, value: k, to: start), d >= today { return d }
        }
        return start
    }
    /// Recherche "resilier <abonnement>", sans jamais planter.
    ///
    /// L'ancienne version interpolait le nom saisi par l'utilisateur dans une
    /// chaine puis forcait le deballage. Deux facons de planter: le repli
    /// utilisait le nom BRUT quand l'encodage echouait, et un nom contenant
    /// une espace ou un diese donne alors une URL invalide, donc nil, donc
    /// crash. Un abonnement nomme "Disney +" suffisait.
    /// URLComponents encode les parametres correctement, y compris l'accent
    /// de "resilier" qui n'a rien a faire dans une chaine d'URL brute.
    private func cancelURL(_ name: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "www.google.com"
        c.path = "/search"
        c.queryItems = [URLQueryItem(name: "q", value: "résilier \(name)")]
        // Repli sur la page d'accueil: on n'ouvre rien d'inattendu, et
        // surtout on ne plante pas si l'URL ne se construit pas.
        return c.url ?? URL(string: "https://www.google.com")!
    }
}

struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var amount = ""; @State private var cycle = "Mensuel"; @State private var next = Date()
    @State private var error: String?
    private var parsed: AmountInput.Parsed { AmountInput.parse(amount) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (Netflix, Spotify…)", text: $name)
                AmountRow(title: "Montant", text: $amount)
                Picker("Cycle", selection: $cycle) { Text("Mensuel").tag("Mensuel"); Text("Annuel").tag("Annuel") }
                DatePicker("Prochain prélèvement", selection: $next, displayedComponents: .date)
                FormError(message: error)
            }
            .navigationTitle("Nouvel abonnement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    guard let a = parsed.value else { return }
                    ctx.insert(Subscription(name: name, amount: a, cycle: cycle, nextDate: next)); commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || parsed.value == nil) }
            }
        }
    }
}

// MARK: - Split (Tricount)

struct SplitView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SplitExpense.date, order: .reverse) private var expenses: [SplitExpense]
    @State private var showAdd = false
    // Plus de membres inventes (« Alex », « Sam ») dans les soldes: on part de
    // l'utilisateur seul et il ajoute son groupe.
    @AppStorage(AppStorageKeys.splitMembers) private var membersRaw = "Moi"
    @State private var newMember = ""

    /// Membres enregistres + toute personne deja presente dans une depense (sinon ses
    /// dettes disparaitraient des soldes).
    private var members: [String] {
        Self.members(raw: membersRaw, expenseNames: expenses.flatMap { [$0.payer] + $0.participants.split(separator: ",").map(String.init) })
    }

    static func members(raw: String, expenseNames: [String]) -> [String] {
        var out: [String] = []
        for n in raw.split(separator: ",").map(String.init) + expenseNames {
            let t = n.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, !out.contains(t) { out.append(t) }
        }
        return out
    }

    private func usedInExpenses(_ m: String) -> Bool {
        expenses.contains { $0.payer == m || $0.participants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(m) }
    }

    private func addMember() {
        // Une virgule casserait la liste stockee en CSV.
        let n = newMember.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !members.contains(n) else { newMember = ""; return }
        membersRaw = (Self.members(raw: membersRaw, expenseNames: []) + [n]).joined(separator: ",")
        newMember = ""
    }

    private func removeMember(_ m: String) {
        guard !usedInExpenses(m) else { return }
        membersRaw = Self.members(raw: membersRaw, expenseNames: []).filter { $0 != m }.joined(separator: ",")
    }

    /// Solde de chacun : payé - sa part due.
    private var balances: [String: Double] {
        var bal: [String: Double] = [:]
        for m in members { bal[m] = 0 }
        for e in expenses {
            let parts = e.participants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let split = parts.isEmpty ? members : parts
            guard !split.isEmpty else { continue }
            // Parts en centimes entiers : `e.amount / count` perdait des centimes
            // (10 € a trois donnait 3,333... et le total ne retombait pas sur 10).
            let totalCents = Int((e.amount * 100).rounded())
            let shares = SettlementCalculator.split(totalCents: totalCents, between: split.count)
            bal[e.payer, default: 0] += Double(totalCents) / 100.0
            for (idx, p) in split.enumerated() {
                bal[p, default: 0] -= Double(shares[idx]) / 100.0
            }
        }
        return bal
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Qui doit quoi")
                        ForEach(members, id: \.self) { m in
                            let b = balances[m] ?? 0
                            HStack {
                                Text(m).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(b >= 0 ? "+\(b, format: .currency(code: "EUR"))" : "\(b, format: .currency(code: "EUR"))")
                                    .bold().foregroundStyle(b >= 0 ? Theme.success : Theme.danger)
                            }
                        }
                        Text(settlementHint).font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 4)
                    }.card()

                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Membres")
                        if members.count < 2 {
                            Text("Ajoute les personnes du groupe pour partager une dépense.").font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(members, id: \.self) { m in
                            HStack {
                                Text(m).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if !usedInExpenses(m) && members.count > 1 {
                                    Button { removeMember(m) } label: { Image(systemName: "minus.circle").foregroundStyle(Theme.danger) }
                                        .buttonStyle(.plain).accessibilityLabel("Retirer \(m)")
                                }
                            }
                        }
                        HStack {
                            TextField("Nom", text: $newMember).onSubmit(addMember)
                            Button { addMember() } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }
                                .buttonStyle(.plain).accessibilityLabel("Ajouter un membre")
                                .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }.card()

                    HStack { SectionHeader(title: "Dépenses"); Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }.accessibilityLabel("Ajouter").disabled(members.isEmpty) }
                    if expenses.isEmpty { Text("Aucune dépense partagée.").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    ForEach(expenses) { e in
                        HStack {
                            VStack(alignment: .leading) { Text(e.desc.isEmpty ? "Dépense" : e.desc).foregroundStyle(Theme.textPrimary); Text("Payé par \(e.payer)").font(.caption).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Text(e.amount, format: .currency(code: "EUR")).bold().foregroundStyle(.finTint)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { ctx.delete(e) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Split").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) { SplitEditor(members: members) }
    }
    /// Delegue a `SettlementCalculator` : l'ancienne version envoyait TOUTE la plus
    /// grosse dette au plus gros crediteur (faux des qu'il y a plus de deux personnes)
    /// et tronquait le montant avec `Int()` (99,99 € s'affichait 99 €).
    private var settlementHint: String {
        let cents = balances.mapValues { Int(($0 * 100).rounded()) }
        return SettlementCalculator.hint(balancesCents: cents)
    }
}

struct SplitEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let members: [String]
    @State private var desc = ""; @State private var amount = ""; @State private var payer = ""
    @State private var selected: Set<String> = []
    @State private var error: String?
    private var parsed: AmountInput.Parsed { AmountInput.parse(amount) }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $desc)
                AmountRow(title: "Montant", text: $amount)
                Picker("Payé par", selection: $payer) { ForEach(members, id: \.self) { Text($0) } }
                Section("Partagé entre") {
                    ForEach(members, id: \.self) { m in
                        Button { if selected.contains(m) { selected.remove(m) } else { selected.insert(m) } } label: {
                            HStack { Text(m).foregroundStyle(Theme.textPrimary); Spacer(); if selected.contains(m) { Image(systemName: "checkmark").foregroundStyle(.finTint) } }
                        }
                    }
                    if selected.isEmpty { Text("Choisis au moins une personne.").font(.caption).foregroundStyle(Theme.warning) }
                }
                FormError(message: error)
            }
            .navigationTitle("Nouvelle dépense").navigationBarTitleDisplayMode(.inline)
            .onAppear { payer = members.first ?? "Moi"; selected = Set(members) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    guard let a = parsed.value, !selected.isEmpty else { return }
                    ctx.insert(SplitExpense(payer: payer, amount: a, desc: desc, participants: selected.sorted().joined(separator: ",")))
                    commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(parsed.value == nil || selected.isEmpty) }
            }
        }
    }
}

// MARK: - Objectifs d'épargne

struct SavingsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var goals: [SavingsGoal]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if goals.isEmpty {
                        EmptyState(icon: "target", title: "Aucun objectif", message: "Définis un objectif (voyage, apport immo…) et ton effort mensuel.")
                    } else {
                        ForEach(goals) { g in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(g.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(g.current, format: .currency(code: "EUR")) / \(g.target, format: .currency(code: "EUR"))").bold().foregroundStyle(Theme.textPrimary) }
                                ProgressView(value: g.progress).tint(Color.accentColor)
                                HStack {
                                    Text(Self.status(target: g.target, current: g.current, monthly: g.monthly)).font(.caption).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    // Sans effort mensuel, « +0€ » ne faisait rien: bouton masque.
                                    if g.monthly > 0 {
                                        Button { g.current += g.monthly } label: {
                                            Text("+\(g.monthly, format: .currency(code: "EUR"))").font(.caption.bold())
                                                .padding(.horizontal, 12).padding(.vertical, 6)
                                                .glassControl(Capsule())
                                                .foregroundStyle(Theme.textPrimary)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }.card()
                                .contextMenu { Button(role: .destructive) { ctx.delete(g) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Épargne").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { SavingsEditor() }
    }

    /// « Objectif atteint » seulement quand l'epargne atteint la cible. Avant, un
    /// effort mensuel a 0 donnait monthsLeft = 0, donc « Objectif atteint » a tort.
    static func status(target: Double, current: Double, monthly: Double) -> String {
        if current >= target { return "Objectif atteint" }
        guard monthly > 0 else { return "Fixe un effort mensuel pour estimer la date." }
        let months = Int(ceil((target - current) / monthly))
        return "≈ \(months) mois restants (\(monthly.formatted(.currency(code: "EUR")))/mois)"
    }
}

struct SavingsEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var target = ""; @State private var current = ""; @State private var monthly = ""
    @State private var error: String?
    private var t: AmountInput.Parsed { AmountInput.parse(target) }
    private var c: AmountInput.Parsed { AmountInput.parse(current, rules: .optional) }
    private var m: AmountInput.Parsed { AmountInput.parse(monthly, rules: .optional) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && t.value != nil && c.message == nil && m.message == nil
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Objectif (ex: Apport immo)", text: $name)
                AmountRow(title: "Montant cible", text: $target)
                AmountRow(title: "Déjà épargné", text: $current, rules: .optional)
                AmountRow(title: "Effort mensuel", text: $monthly, rules: .optional)
                FormError(message: error)
            }
            .navigationTitle("Nouvel objectif").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") {
                    guard let tv = t.value else { return }
                    ctx.insert(SavingsGoal(name: name, target: tv, current: c.value ?? 0, monthly: m.value ?? 0))
                    commitForm(ctx, error: $error, dismiss: dismiss)
                }.disabled(!canSave) }
            }
        }
    }
}

// MARK: - Scaffold agrégation bancaire

/// Vue « Solde global » : agrège tous les comptes saisis + le cashflow du mois.
/// (La connexion bancaire automatique DSP2 exige un agrégateur agréé — hors app.)
struct BankOverviewView: View {
    @Query private var accounts: [Account]
    @Query private var txns: [Txn]

    private var total: Double { accounts.reduce(0) { $0 + $1.balance } }
    private func totalOf(_ kind: String) -> Double {
        accounts.filter { $0.kind == kind }.reduce(0) { $0 + $1.balance }
    }
    private var monthTxns: [Txn] {
        txns.filter { Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }
    private var income: Double { monthTxns.filter { $0.amount > 0 }.reduce(0) { $0 + $1.amount } }
    private var expense: Double { monthTxns.filter { $0.amount < 0 }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("Solde global").font(.subheadline).foregroundStyle(.secondary)
                        Text(total, format: .currency(code: "EUR"))
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(total < 0 ? Theme.danger : Theme.textPrimary)
                        Text("\(accounts.count) compte\(accounts.count > 1 ? "s" : "") agrégé\(accounts.count > 1 ? "s" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 22).card()

                    HStack(spacing: 12) {
                        kindTile("Courant", "creditcard.fill")
                        kindTile("Épargne", "banknote.fill")
                        kindTile("Cash", "eurosign.circle.fill")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Ce mois-ci").font(.headline).foregroundStyle(Theme.textPrimary)
                        cashRow("Entrées", income, Theme.success)
                        cashRow("Sorties", expense, Theme.danger)
                        Divider()
                        cashRow("Net", income + expense, (income + expense) >= 0 ? Theme.success : Theme.danger)
                    }.card()

                    if accounts.isEmpty {
                        Text("Ajoute des comptes dans « Comptes & dépenses » pour les voir agrégés ici.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).card()
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(accounts) { a in
                                HStack {
                                    Image(systemName: a.kind == "Épargne" ? "banknote" : a.kind == "Cash" ? "eurosign.circle" : "creditcard")
                                        .foregroundStyle(.finTint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(a.name.isEmpty ? a.kind : a.name).foregroundStyle(Theme.textPrimary)
                                        Text(a.kind).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(a.balance, format: .currency(code: "EUR")).bold()
                                        .foregroundStyle(a.balance < 0 ? Theme.danger : Theme.textPrimary)
                                }.padding(.vertical, 11)
                                Divider().opacity(a.persistentModelID == accounts.last?.persistentModelID ? 0 : 1)
                            }
                        }.card()
                    }

                    Text("Agrégation de tes comptes saisis manuellement. La connexion bancaire automatique (norme DSP2) nécessite un agrégateur agréé et n'est pas incluse.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Solde global").navigationBarTitleDisplayMode(.inline)
    }

    private func kindTile(_ kind: String, _ icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(.finTint)
            Text(totalOf(kind), format: .currency(code: "EUR"))
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(kind).font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).card()
    }
    private func cashRow(_ label: String, _ v: Double, _ color: Color) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(v, format: .currency(code: "EUR")).bold().foregroundStyle(color)
        }
    }
}
