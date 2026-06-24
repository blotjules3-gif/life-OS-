import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var finTint: Color { AppCategory.finance.tint } }

// MARK: - Hub Finances

struct FinanceHubView: View {
    var body: some View {
        HubScaffold(category: .finance) {
            ToolRow(icon: "building.columns.fill", title: "Comptes & dépenses",
                    subtitle: "Solde + transactions + alertes", tint: .finTint) { AccountsView() }
            ToolRow(icon: "tray.2.fill", title: "Budget par enveloppes",
                    subtitle: "Catégorise et plafonne", tint: .finTint) { BudgetView() }
            ToolRow(icon: "repeat.circle.fill", title: "Abonnements",
                    subtitle: "Détecte les oubliés + résilie", tint: .finTint) { SubscriptionsView() }
            ToolRow(icon: "person.2.circle.fill", title: "Split entre potes",
                    subtitle: "Tricount intégré", tint: .finTint) { SplitView() }
            ToolRow(icon: "target", title: "Objectifs d'épargne",
                    subtitle: "Projection temps restant", tint: .finTint) { SavingsView() }
            ToolRow(icon: "link.circle.fill", title: "Agrégation bancaire",
                    subtitle: "Bankin / Linxo — à brancher", tint: .finTint) { BankScaffold() }
        }
    }
}

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
                        Text(total, format: .currency(code: "EUR")).font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("Dépensé ce mois : \(monthSpend, format: .currency(code: "EUR"))").font(.caption).foregroundStyle(.orange)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    // Alerte dépense anormale / risque découvert
                    if let alert = anomalyAlert() {
                        HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red); Text(alert).font(.footnote).foregroundStyle(Theme.textPrimary) }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }

                    HStack {
                        SectionHeader(title: "Comptes")
                        Button { showAddAccount = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }
                    }
                    ForEach(accounts) { a in
                        HStack {
                            Image(systemName: a.kind == "Épargne" ? "banknote" : a.kind == "Cash" ? "eurosign.circle" : "creditcard").foregroundStyle(.finTint)
                            VStack(alignment: .leading) { Text(a.name).foregroundStyle(Theme.textPrimary); Text(a.kind).font(.caption).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Text(a.balance, format: .currency(code: "EUR")).bold().foregroundStyle(a.balance < 0 ? .red : Theme.textPrimary)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { ctx.delete(a) } label: { Label("Supprimer", systemImage: "trash") } }
                    }

                    HStack {
                        SectionHeader(title: "Dernières opérations")
                        Button { showAddTxn = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) }
                    }
                    if txns.isEmpty { Text("Aucune opération.").font(.footnote).foregroundStyle(Theme.textSecondary) }
                    ForEach(txns.prefix(15)) { t in
                        HStack {
                            VStack(alignment: .leading) { Text(t.note.isEmpty ? t.category : t.note).foregroundStyle(Theme.textPrimary); Text(t.date, style: .date).font(.caption).foregroundStyle(Theme.textSecondary) }
                            Spacer()
                            Text(t.amount, format: .currency(code: "EUR")).bold().foregroundStyle(t.amount < 0 ? .red : .green)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { ctx.delete(t) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Comptes & dépenses").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddAccount) { AccountEditor() }
        .sheet(isPresented: $showAddTxn) { TxnEditor(accounts: accounts.map { $0.name }) }
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
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom du compte", text: $name)
                Picker("Type", selection: $kind) { ForEach(["Courant","Épargne","Cash"], id: \.self) { Text($0) } }
                HStack { Text("Solde"); Spacer(); TextField("0", text: $balance).keyboardType(.numbersAndPunctuation).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("Nouveau compte").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Account(name: name, kind: kind, balance: Double(balance.replacingOccurrences(of: ",", with: ".")) ?? 0)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

struct TxnEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let accounts: [String]
    @State private var amount = ""; @State private var isExpense = true
    @State private var category = "Courses"; @State private var note = ""; @State private var account = ""
    private let cats = ["Courses","Restau","Transport","Logement","Loisirs","Santé","Shopping","Salaire","Divers"]
    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $isExpense) { Text("Dépense").tag(true); Text("Revenu").tag(false) }.pickerStyle(.segmented)
                HStack { Text("Montant"); Spacer(); TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("Catégorie", selection: $category) { ForEach(cats, id: \.self) { Text($0) } }
                if !accounts.isEmpty { Picker("Compte", selection: $account) { ForEach(accounts, id: \.self) { Text($0) } } }
                TextField("Note", text: $note)
            }
            .navigationTitle("Nouvelle opération").navigationBarTitleDisplayMode(.inline)
            .onAppear { account = accounts.first ?? "Courant" }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    let v = (Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0) * (isExpense ? -1 : 1)
                    ctx.insert(Txn(amount: v, category: category, account: account, note: note))
                    if let acc = (try? ctx.fetch(FetchDescriptor<Account>()))?.first(where: { $0.name == account }) { acc.balance += v }
                    dismiss()
                }.disabled(amount.isEmpty) }
            }
        }
    }
}

// MARK: - Budget enveloppes

struct BudgetView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var envelopes: [Envelope]
    @State private var showAdd = false
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    if envelopes.isEmpty {
                        EmptyState(icon: "tray.2", title: "Aucune enveloppe", message: "Crée des enveloppes (Courses, Loisirs…) avec un plafond mensuel.")
                    } else {
                        ForEach(envelopes) { e in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Circle().fill(Color(hex: UInt(e.colorHex))).frame(width: 12, height: 12)
                                    Text(e.name).font(.headline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(Int(e.spent)) / \(Int(e.monthlyBudget)) €").font(.subheadline.bold()).foregroundStyle(e.remaining < 0 ? .red : Theme.textPrimary)
                                }
                                ProgressView(value: e.progress).tint(e.remaining < 0 ? .red : Color(hex: UInt(e.colorHex)))
                                HStack {
                                    Text(e.remaining >= 0 ? "Reste \(Int(e.remaining))€" : "Dépassé de \(Int(-e.remaining))€").font(.caption).foregroundStyle(e.remaining < 0 ? .red : Theme.textSecondary)
                                    Spacer()
                                    Button("-10") { e.spent = max(0, e.spent-10) }.font(.caption).buttonStyle(.bordered).tint(.finTint)
                                    Button("+10€") { e.spent += 10 }.font(.caption).buttonStyle(.borderedProminent).tint(.finTint)
                                }
                            }.card()
                                .contextMenu { Button(role: .destructive) { ctx.delete(e) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Budget enveloppes").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { EnvelopeEditor() }
    }
}

struct EnvelopeEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var budget = ""; @State private var color = 0x618EF1
    private let colors = [0x618EF1, 0x4CC38A, 0xF1746C, 0xE0A23C, 0x9B6CF1, 0x3CD0C8]
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex: Courses)", text: $name)
                HStack { Text("Plafond mensuel"); Spacer(); TextField("0", text: $budget).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { ForEach(colors, id: \.self) { c in Circle().fill(Color(hex: UInt(c))).frame(width: 28, height: 28).overlay(color == c ? Circle().stroke(.white, lineWidth: 2) : nil).onTapGesture { color = c } } }
            }
            .navigationTitle("Nouvelle enveloppe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") { ctx.insert(Envelope(name: name, monthlyBudget: Double(budget) ?? 0, colorHex: color)); dismiss() }.disabled(name.isEmpty) }
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
                        Text(monthlyTotal, format: .currency(code: "EUR")).font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("Soit \(monthlyTotal*12, format: .currency(code: "EUR")) / an").font(.caption).foregroundStyle(.orange)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    ForEach(subs) { s in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(s.name).font(.headline).foregroundStyle(s.active ? Theme.textPrimary : Theme.textSecondary)
                                if forgotten(s) { Text("Oublié ?").font(.caption2.bold()).padding(.horizontal,6).padding(.vertical,2).background(Color.orange.opacity(0.2), in: Capsule()).foregroundStyle(.orange) }
                                Spacer()
                                Text("\(s.amount, format: .currency(code: "EUR"))/\(s.cycle == "Annuel" ? "an" : "mois")").bold().foregroundStyle(.finTint)
                            }
                            HStack {
                                Text("Prochain : \(s.nextDate, style: .date)").font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Toggle("Actif", isOn: Binding(get: { s.active }, set: { s.active = $0 })).labelsHidden().tint(.finTint)
                                Link(destination: cancelURL(s.name)) { Text("Résilier").font(.caption.bold()).foregroundStyle(.red) }
                            }
                        }.card()
                            .contextMenu { Button(role: .destructive) { ctx.delete(s) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    IntegrationNotice(text: "La détection automatique des abonnements oubliés (analyse de tes relevés) et la résiliation « en un tap » nécessitent l'agrégation bancaire (voir module dédié) + des mandats de résiliation. Ici tu les listes et le bouton Résilier ouvre une recherche d'aide à la résiliation.")
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Abonnements").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { SubscriptionEditor() }
    }
    private func forgotten(_ s: Subscription) -> Bool { s.active && s.nextDate < Calendar.current.date(byAdding: .month, value: -2, to: .now)! }
    private func cancelURL(_ name: String) -> URL { URL(string: "https://www.google.com/search?q=résilier+\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name)")! }
}

struct SubscriptionEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var amount = ""; @State private var cycle = "Mensuel"; @State private var next = Date()
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (Netflix, Spotify…)", text: $name)
                HStack { Text("Montant"); Spacer(); TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("Cycle", selection: $cycle) { Text("Mensuel").tag("Mensuel"); Text("Annuel").tag("Annuel") }
                DatePicker("Prochain prélèvement", selection: $next, displayedComponents: .date)
            }
            .navigationTitle("Nouvel abonnement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(Subscription(name: name, amount: Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0, cycle: cycle, nextDate: next)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Split (Tricount)

struct SplitView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SplitExpense.date, order: .reverse) private var expenses: [SplitExpense]
    @State private var showAdd = false
    @AppStorage("splitMembers") private var membersRaw = "Moi,Alex,Sam"

    private var members: [String] { membersRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }

    /// Solde de chacun : payé - sa part due.
    private var balances: [String: Double] {
        var bal: [String: Double] = [:]
        for m in members { bal[m] = 0 }
        for e in expenses {
            let parts = e.participants.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let split = parts.isEmpty ? members : parts
            guard !split.isEmpty else { continue }
            let share = e.amount / Double(split.count)
            bal[e.payer, default: 0] += e.amount
            for p in split { bal[p, default: 0] -= share }
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
                                    .bold().foregroundStyle(b >= 0 ? .green : .red)
                            }
                        }
                        Text(settlementHint).font(.caption).foregroundStyle(Theme.textSecondary).padding(.top, 4)
                    }.card()

                    HStack { SectionHeader(title: "Dépenses"); Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.finTint) } }
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
    private var settlementHint: String {
        let sorted = balances.sorted { $0.value < $1.value }
        guard let debtor = sorted.first, let creditor = sorted.last, debtor.value < -0.5 else { return "Tout est équilibré ✓" }
        return "\(debtor.key) doit \(Int(-debtor.value))€ à \(creditor.key)."
    }
}

struct SplitEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let members: [String]
    @State private var desc = ""; @State private var amount = ""; @State private var payer = ""
    @State private var selected: Set<String> = []
    var body: some View {
        NavigationStack {
            Form {
                TextField("Description", text: $desc)
                HStack { Text("Montant"); Spacer(); TextField("0", text: $amount).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Picker("Payé par", selection: $payer) { ForEach(members, id: \.self) { Text($0) } }
                Section("Partagé entre") {
                    ForEach(members, id: \.self) { m in
                        Button { if selected.contains(m) { selected.remove(m) } else { selected.insert(m) } } label: {
                            HStack { Text(m).foregroundStyle(Theme.textPrimary); Spacer(); if selected.contains(m) { Image(systemName: "checkmark").foregroundStyle(.finTint) } }
                        }
                    }
                }
            }
            .navigationTitle("Nouvelle dépense").navigationBarTitleDisplayMode(.inline)
            .onAppear { payer = members.first ?? "Moi"; selected = Set(members) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(SplitExpense(payer: payer, amount: Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0, desc: desc, participants: selected.joined(separator: ","))); dismiss()
                }.disabled(amount.isEmpty) }
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
                                HStack { Text(g.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text("\(Int(g.current)) / \(Int(g.target)) €").bold().foregroundStyle(.finTint) }
                                ProgressView(value: g.progress).tint(.finTint)
                                HStack {
                                    Text(g.monthsLeft > 0 ? "≈ \(g.monthsLeft) mois restants (\(Int(g.monthly))€/mois)" : "Objectif atteint 🎉").font(.caption).foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Button("+\(Int(g.monthly))€") { g.current += g.monthly }.font(.caption).buttonStyle(.borderedProminent).tint(.finTint)
                                }
                            }.card()
                                .contextMenu { Button(role: .destructive) { ctx.delete(g) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Épargne").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { SavingsEditor() }
    }
}

struct SavingsEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var target = ""; @State private var current = ""; @State private var monthly = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Objectif (ex: Apport immo)", text: $name)
                HStack { Text("Montant cible"); Spacer(); TextField("0", text: $target).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Déjà épargné"); Spacer(); TextField("0", text: $current).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Effort mensuel"); Spacer(); TextField("0", text: $monthly).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("Nouvel objectif").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Créer") { ctx.insert(SavingsGoal(name: name, target: Double(target) ?? 0, current: Double(current) ?? 0, monthly: Double(monthly) ?? 0)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Scaffold agrégation bancaire

struct BankScaffold: View {
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill").font(.system(size: 56)).foregroundStyle(.finTint).padding(.top, 30)
                    Text("Agrégation bancaire").font(.title3.bold()).foregroundStyle(Theme.textPrimary)
                    IntegrationNotice(text: "Connecter automatiquement tes comptes bancaires (Bankin/Linxo) impose la réglementation DSP2 : tu dois passer par un agrégateur agréé (Bridge by Bankin', Powens/Budget Insight, Tink, Plaid). C'est un service payant avec contrat + agrément. Aucune app ne peut lire tes comptes sans cet intermédiaire — c'est une protection légale.")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chemin d'activation").font(.headline).foregroundStyle(Theme.textPrimary)
                        bullet("Choisir un agrégateur DSP2 (ex: Bridge API)")
                        bullet("OAuth bancaire : l'utilisateur autorise sa banque")
                        bullet("Webhook → transactions → catégorisation auto (déjà modélisée ici)")
                        bullet("La catégorisation, le budget, les abonnements et alertes sont DÉJÀ codés et fonctionnent en saisie manuelle")
                    }.card()
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Agrégation").navigationBarTitleDisplayMode(.inline)
    }
    private func bullet(_ t: String) -> some View { Text("• " + t).font(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading) }
}
