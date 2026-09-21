import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var investTint: Color { AppCategory.invest.tint } }

// MARK: - Hub Investissement


// MARK: - Portefeuille

struct PortfolioView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var holdings: [Holding]
    @State private var showAdd = false
    @State private var refreshing = false
    @State private var priceError: String?
    @State private var lastRefresh: Date?
    private var cryptoSymbols: [String] { holdings.filter { $0.kind == "Crypto" }.map(\.symbol) }
    private var stockSymbols: [String] { holdings.filter { $0.kind != "Crypto" }.map(\.symbol) }
    private var total: Double { holdings.reduce(0) { $0 + $1.value } }
    private var totalPnL: Double { holdings.reduce(0) { $0 + $1.pnl } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valeur du portefeuille").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(total, format: .currency(code: "EUR")).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                        Text("\(totalPnL >= 0 ? "+" : "")\(totalPnL, format: .currency(code: "EUR")) (\(total-totalPnL == 0 ? 0 : totalPnL/(total-totalPnL)*100, specifier: "%.1f")%)")
                            .font(.subheadline.bold()).foregroundStyle(totalPnL >= 0 ? .green : .red)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    if !holdings.isEmpty {
                        Chart(holdings) { h in
                            SectorMark(angle: .value("Valeur", h.value), innerRadius: .ratio(0.6))
                                .foregroundStyle(by: .value("Actif", h.symbol))
                        }.frame(height: 200).card()
                    }

                    if holdings.isEmpty {
                        EmptyState(icon: "chart.pie", title: "Portefeuille vide", message: "Ajoute tes actions, ETF et cryptos.")
                    } else {
                        ForEach(holdings) { h in
                            HStack {
                                VStack(alignment: .leading) {
                                    HStack { Text(h.symbol).font(.headline).foregroundStyle(Theme.textPrimary); Text(h.kind).font(.caption2).padding(.horizontal,5).padding(.vertical,1).background(Theme.bg2, in: Capsule()).foregroundStyle(Theme.textSecondary) }
                                    Text("\(h.quantity, specifier: "%.4g") × \(h.currentPrice, format: .currency(code: "EUR"))").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(h.value, format: .currency(code: "EUR")).bold().foregroundStyle(Theme.textPrimary)
                                    Text("\(h.pnlPct >= 0 ? "+" : "")\(h.pnlPct, specifier: "%.1f")%").font(.caption).foregroundStyle(h.pnl >= 0 ? .green : .red)
                                }
                            }.card(padding: 12)
                                .contextMenu { Button(role: .destructive) { ctx.delete(h) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                        priceStatus
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Portefeuille").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter")
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { Task { await refreshPrices(force: true) } } label: {
                    if refreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(refreshing || (cryptoSymbols.isEmpty && stockSymbols.isEmpty))
                .accessibilityLabel("Actualiser les cours")
            }
        }
        .sheet(isPresented: $showAdd) { HoldingEditor() }
        .refreshable { await refreshPrices(force: true) }
        .task { await refreshPrices(force: false) }
    }

    /// Etat de la synchro des cours, affiche a la place de l'ancienne notice.
    @ViewBuilder private var priceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let priceError {
                Label(priceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            } else if let lastRefresh {
                Label("Cours à jour · \(lastRefresh, style: .time)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
            // On ne pretend pas suivre les actions: aucune API boursiere n'est
            // gratuite sans cle. Le dire vaut mieux qu'un chiffre faux.
            if holdings.contains(where: { $0.kind != "Crypto" }) {
                // Cours differes selon la place: on le dit plutot que de
                // laisser croire a du temps reel.
                Text("Actions et ETF : cours différés. Utilise le symbole de la place (MC.PA, AAPL, CW8.PA).")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Va chercher les cours et les ecrit dans le modele.
    ///
    /// Crypto et actions viennent de deux sources differentes. Un echec d'un
    /// cote ne doit pas empecher l'autre de se mettre a jour, sinon une panne
    /// de Yahoo gelerait aussi les cryptos.
    private func refreshPrices(force: Bool) async {
        guard !cryptoSymbols.isEmpty || !stockSymbols.isEmpty else { return }
        refreshing = true
        defer { refreshing = false }
        var problems: [String] = []
        var updated = 0

        if !cryptoSymbols.isEmpty {
            switch await PriceService.cryptoPrices(symbols: cryptoSymbols, force: force) {
            case .success(let prices):
                for h in holdings where h.kind == "Crypto" {
                    if let p = prices[h.symbol.lowercased()] { h.currentPrice = p; updated += 1 }
                }
            case .failure(let e):
                problems.append("Crypto : \(e)")
            }
        }

        if !stockSymbols.isEmpty {
            switch await StockService.pricesInEUR(symbols: stockSymbols, force: force) {
            case .success(let prices):
                for h in holdings where h.kind != "Crypto" {
                    if let p = prices[h.symbol.uppercased()] { h.currentPrice = p; updated += 1 }
                }
            case .failure(let e):
                problems.append("Actions : \(e)")
            }
        }

        if updated > 0 {
            // On garde les derniers prix connus en cas d'echec partiel plutot
            // que de vider l'ecran.
            do { try ctx.save() } catch {
                AppLog.data.error("cours non sauvegardes: \(error.localizedDescription, privacy: .public)")
            }
            lastRefresh = .now
        }
        priceError = problems.isEmpty ? nil : problems.joined(separator: " · ")
    }
}

struct HoldingEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = ""; @State private var kind = "Action"
    @State private var qty = ""; @State private var buy = ""; @State private var current = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Symbole (AAPL, BTC…)", text: $symbol).textInputAutocapitalization(.characters)
                Picker("Type", selection: $kind) { ForEach(["Action","ETF","Crypto"], id: \.self) { Text($0) } }
                HStack { Text("Quantité"); Spacer(); TextField("0", text: $qty).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Prix d'achat"); Spacer(); TextField("0", text: $buy).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                HStack { Text("Prix actuel"); Spacer(); TextField("0", text: $current).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("Nouvelle position").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    let b = Double(buy.replacingOccurrences(of: ",", with: ".")) ?? 0
                    ctx.insert(Holding(symbol: symbol, kind: kind, quantity: Double(qty.replacingOccurrences(of: ",", with: ".")) ?? 0, buyPrice: b, currentPrice: Double(current.replacingOccurrences(of: ",", with: ".")) ?? b)); dismiss()
                }.disabled(symbol.isEmpty) }
            }
        }
    }
}

// MARK: - Net worth & FIRE

struct NetWorthView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var items: [NetWorthItem]
    @Query private var holdings: [Holding]
    @State private var showAdd = false
    @AppStorage(AppStorageKeys.fireMonthly) private var monthly = 500.0
    @AppStorage(AppStorageKeys.fireReturn) private var annualReturn = 7.0
    @AppStorage(AppStorageKeys.fireYears) private var years = 20.0

    private var assets: Double { items.filter { $0.kind == "Actif" }.reduce(0) { $0 + $1.value } + holdings.reduce(0) { $0 + $1.value } }
    private var liabilities: Double { items.filter { $0.kind == "Passif" }.reduce(0) { $0 + $1.value } }
    private var netWorth: Double { assets - liabilities }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Patrimoine net").font(.caption).foregroundStyle(Theme.textSecondary)
                        Text(netWorth, format: .currency(code: "EUR")).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(netWorth >= 0 ? Theme.textPrimary : .red)
                        HStack {
                            Label("\(Int(assets))€ actifs", systemImage: "arrow.up").font(.caption).foregroundStyle(.green)
                            Label("\(Int(liabilities))€ passifs", systemImage: "arrow.down").font(.caption).foregroundStyle(.red)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Projection FIRE", subtitle: "Intérêts composés")
                        sliderRow("Investi / mois", value: $monthly, range: 0...5000, step: 50, format: "%.0f €")
                        sliderRow("Rendement annuel", value: $annualReturn, range: 1...12, step: 0.5, format: "%.1f %%")
                        sliderRow("Horizon", value: $years, range: 1...40, step: 1, format: "%.0f ans")
                        let proj = fireProjection()
                        Chart(proj, id: \.0) { p in
                            AreaMark(x: .value("Année", p.0), y: .value("Capital", p.1)).foregroundStyle(Color.investTint.opacity(0.3))
                            LineMark(x: .value("Année", p.0), y: .value("Capital", p.1)).foregroundStyle(Color.investTint)
                        }.frame(height: 160)
                        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                        .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                        let final = proj.last?.1 ?? 0
                        Text("Dans \(Int(years)) ans : \(final, format: .currency(code: "EUR"))").font(.headline).foregroundStyle(.investTint)
                        Text("Revenu passif à 4% : \(final*0.04/12, format: .currency(code: "EUR"))/mois").font(.caption).foregroundStyle(Theme.textSecondary)
                    }.card()

                    HStack { SectionHeader(title: "Actifs & passifs"); Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.investTint) }.accessibilityLabel("Ajouter") }
                    ForEach(items) { it in
                        HStack {
                            Image(systemName: it.kind == "Actif" ? "plus.circle" : "minus.circle").foregroundStyle(it.kind == "Actif" ? .green : .red)
                            Text(it.name).foregroundStyle(Theme.textPrimary); Spacer()
                            Text(it.value, format: .currency(code: "EUR")).bold().foregroundStyle(Theme.textPrimary)
                        }.card(padding: 12)
                            .contextMenu { Button(role: .destructive) { ctx.delete(it) } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Net worth & FIRE").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) { NetWorthEditor() }
    }
    private func sliderRow(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary); Spacer(); Text(String(format: format, value.wrappedValue)).font(.subheadline.bold()).foregroundStyle(.investTint) }
            Slider(value: value, in: range, step: step).tint(.investTint)
        }
    }
    private func fireProjection() -> [(Int, Double)] {
        let r = annualReturn / 100 / 12
        var capital = netWorth > 0 ? netWorth : 0
        var result: [(Int, Double)] = [(0, capital)]
        for year in 1...Int(years) {
            for _ in 0..<12 { capital = capital * (1 + r) + monthly }
            result.append((year, capital))
        }
        return result
    }
}

struct NetWorthEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var kind = "Actif"; @State private var value = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (Livret A, Prêt auto…)", text: $name)
                Picker("Type", selection: $kind) { Text("Actif").tag("Actif"); Text("Passif").tag("Passif") }.pickerStyle(.segmented)
                HStack { Text("Valeur"); Spacer(); TextField("0", text: $value).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
            }
            .navigationTitle("Actif / Passif").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { ctx.insert(NetWorthItem(name: name, kind: kind, value: Double(value) ?? 0)); dismiss() }.disabled(name.isEmpty) }
            }
        }
    }
}

// MARK: - Immobilier

struct RealEstateView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var props: [Property]
    @State private var showAdd = false
    @State private var showImport = false
    /// Fiche lue dans une annonce, en attente de confirmation par l'utilisateur.
    @State private var imported: ListingParser.Draft?
    private var totalCashflow: Double { props.reduce(0) { $0 + $1.monthlyCashflow } }
    private var totalEquity: Double { props.reduce(0) { $0 + $1.netEquity } }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        StatTile(value: "\(Int(totalCashflow))€", label: "Cashflow/mois", icon: "arrow.left.arrow.right", tint: totalCashflow >= 0 ? .green : .red)
                        StatTile(value: "\(Int(totalEquity/1000))k€", label: "Equity nette", icon: "house")
                    }
                    if props.isEmpty {
                        EmptyState(icon: "house", title: "Aucun bien", message: "Ajoute un bien : valeur, loyer, charges, crédit. (Utile pour ta thèse Action Logement.)")
                    } else {
                        ForEach(props) { p in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(p.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text(p.value, format: .currency(code: "EUR")).bold().foregroundStyle(.investTint) }
                                HStack {
                                    metric("Loyer", p.monthlyRent, .green)
                                    metric("Charges", -p.monthlyCharges, .orange)
                                    metric("Crédit", -p.loanPayment, .red)
                                }
                                Divider().overlay(Theme.stroke)
                                HStack {
                                    Text("Cashflow net").font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(p.monthlyCashflow >= 0 ? "+" : "")\(p.monthlyCashflow, format: .currency(code: "EUR"))/mois").bold().foregroundStyle(p.monthlyCashflow >= 0 ? .green : .red)
                                }
                                Text("Rendement brut : \(p.value > 0 ? p.monthlyRent*12/p.value*100 : 0, specifier: "%.1f")%").font(.caption).foregroundStyle(Theme.textSecondary)
                            }.card()
                                .contextMenu { Button(role: .destructive) { ctx.delete(p) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                    Button { showImport = true } label: {
                        Label("Coller une annonce", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered).tint(.investTint)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Immobilier").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { PropertyEditor() }
        .sheet(isPresented: $showImport) {
            ListingImportSheet { draft in imported = draft }
        }
        // Rien n'est enregistre directement depuis l'annonce: la fiche lue
        // s'ouvre dans l'editeur normal pour etre relue et corrigee.
        .sheet(item: $imported) { draft in PropertyEditor(draft: draft) }
    }
    private func metric(_ label: String, _ v: Double, _ c: Color) -> some View {
        VStack { Text("\(Int(v))€").font(.subheadline.bold()).foregroundStyle(c); Text(label).font(.caption2).foregroundStyle(Theme.textSecondary) }.frame(maxWidth: .infinity)
    }
}

struct PropertyEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name: String; @State private var value: String; @State private var rent: String
    @State private var charges: String; @State private var loanRemaining = ""; @State private var loanPayment = ""

    /// Prix au m2 de l'annonce, affiche seulement quand l'annonce le permet.
    /// C'est le chiffre qui dit tout de suite si le bien est cher.
    private let pricePerM2: Double?

    /// Vide par defaut, pre-rempli quand la fiche vient d'une annonce collee.
    init(draft: ListingParser.Draft? = nil) {
        func money(_ v: Double) -> String { v > 0 ? String(Int(v.rounded())) : "" }
        _name    = State(initialValue: draft?.name ?? "")
        _value   = State(initialValue: money(draft?.value ?? 0))
        _rent    = State(initialValue: money(draft?.monthlyRent ?? 0))
        _charges = State(initialValue: money(draft?.monthlyCharges ?? 0))
        pricePerM2 = draft?.pricePerM2
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom / adresse", text: $name)
                HStack { Text("Valeur"); Spacer(); TextField("0", text: $value).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Loyer mensuel"); Spacer(); TextField("0", text: $rent).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Charges mensuelles"); Spacer(); TextField("0", text: $charges).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Capital restant dû"); Spacer(); TextField("0", text: $loanRemaining).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Mensualité crédit"); Spacer(); TextField("0", text: $loanPayment).keyboardType(.numberPad).multilineTextAlignment(.trailing) }

                if let pricePerM2 {
                    LabeledContent("Prix au m²", value: "\(Int(pricePerM2.rounded())) €")
                }
                if rent.isEmpty {
                    Text("L'annonce ne donne pas de loyer. Saisis-le toi-même : un loyer estimé fausserait le cashflow et le rendement.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Nouveau bien").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(Property(name: name, value: Double(value) ?? 0, monthlyRent: Double(rent) ?? 0, monthlyCharges: Double(charges) ?? 0, loanRemaining: Double(loanRemaining) ?? 0, loanPayment: Double(loanPayment) ?? 0)); dismiss()
                }.disabled(name.isEmpty) }
            }
        }
    }
}

/// Colle une annonce, obtiens une fiche pre-remplie.
///
/// Le texte n'est jamais enregistre tel quel: il sert a remplir l'editeur
/// normal, que l'utilisateur relit. C'est la meme regle que pour le CV, et
/// elle compte plus ici: un chiffre faux dans un bien se propage au cashflow,
/// au rendement, et donc a une decision d'achat.
struct ListingImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onParsed: (ListingParser.Draft) -> Void

    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var aiReady = false

    private var longEnough: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Le texte de l'annonce") {
                    TextField("Colle ici l'annonce (prix, surface, charges…)", text: $text, axis: .vertical)
                        .lineLimit(5...16)
                }
                Section {
                    if aiReady {
                        Button {
                            Task { await run() }
                        } label: {
                            HStack {
                                if busy { ProgressView().controlSize(.small) }
                                Text(busy ? "Lecture…" : "Lire l'annonce")
                            }
                        }
                        .disabled(busy || !longEnough)
                    } else {
                        Text("Ajoute une clé dans Profil › Coach pour lire une annonce automatiquement.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                } footer: {
                    Text("Seuls les chiffres écrits dans l'annonce sont repris. Rien n'est estimé, et rien n'est enregistré avant que tu aies relu la fiche.")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Coller une annonce").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } } }
            .task { aiReady = await MainActor.run { AIText.isConfigured } }
        }
    }

    private func run() async {
        busy = true; error = nil
        defer { busy = false }
        switch await AIText.ask(system: ListingParser.systemPrompt, user: text,
                                maxTokens: 350, temperature: 0) {
        case .failure(let e):
            error = e.message
        case .success(let raw):
            guard let draft = ListingParser.parse(raw) else {
                error = "Aucun chiffre exploitable dans ce texte. Colle l'annonce complète, prix et surface compris."
                return
            }
            onParsed(draft)
            dismiss()
        }
    }
}

// MARK: - Simulateur fiscalité (IR France)

struct TaxSimulatorView: View {
    @State private var income = 35000.0
    @State private var parts = 1.0
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Tes paramètres")
                        VStack(alignment: .leading) { HStack { Text("Revenu net imposable"); Spacer(); Text("\(Int(income)) €").bold().foregroundStyle(.investTint) }; Slider(value: $income, in: 10000...200000, step: 1000).tint(.investTint) }
                        VStack(alignment: .leading) { HStack { Text("Parts fiscales"); Spacer(); Text(String(format: "%.1f", parts)).bold().foregroundStyle(.investTint) }; Slider(value: $parts, in: 1...5, step: 0.5).tint(.investTint) }
                    }.card()

                    let tax = FrenchTax.computeIR(income: income, parts: parts)
                    VStack(spacing: 12) {
                        ZStack {
                            ProgressRing(progress: income > 0 ? tax/income : 0, lineWidth: 14, tint: .investTint)
                            VStack { Text(tax, format: .currency(code: "EUR")).font(.title2.bold()).foregroundStyle(Theme.textPrimary); Text("d'impôt").font(.caption).foregroundStyle(Theme.textSecondary) }
                        }.frame(width: 190, height: 190)
                        HStack(spacing: 12) {
                            StatTile(value: String(format: "%.1f%%", income > 0 ? tax/income*100 : 0), label: "Taux moyen", icon: "percent")
                            StatTile(value: "\(Int(income-tax))€", label: "Net après IR", icon: "eurosign.circle")
                        }
                    }.card()

                    Text("Barème IR 2024 progressif par tranches, appliqué au quotient familial. Estimation indicative — hors décote, réductions et crédits d'impôt.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Fiscalité").navigationBarTitleDisplayMode(.inline)
    }
}

enum FrenchTax {
    /// Barème de l'impôt sur le revenu 2024 (revenus 2023), par part.
    static func computeIR(income: Double, parts: Double) -> Double {
        let brackets: [(Double, Double, Double)] = [
            (0, 11294, 0.0), (11294, 28797, 0.11), (28797, 82341, 0.30),
            (82341, 177106, 0.41), (177106, .infinity, 0.45)
        ]
        let perPart = income / parts
        var taxPerPart = 0.0
        for (low, high, rate) in brackets where perPart > low {
            taxPerPart += (min(perPart, high) - low) * rate
        }
        return (taxPerPart * parts).rounded()
    }
}
