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
    private var totals: (value: Double, pnl: Double, costKnown: Double, excluded: Int) {
        HoldingMath.totals(holdings.map { (value: $0.value, cost: $0.costEUR) })
    }
    @State private var editingHolding: Holding?

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Valeur du portefeuille").font(.caption).foregroundStyle(Theme.textSecondary)
                        let t = totals
                        Text(t.value, format: .currency(code: "EUR")).font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.textPrimary)
                        if t.costKnown > 0 {
                            Text("\(t.pnl >= 0 ? "+" : "")\(t.pnl, format: .currency(code: "EUR")) (\(t.pnl / t.costKnown * 100, specifier: "%.1f")%)")
                                .font(.subheadline.bold()).foregroundStyle(t.pnl >= 0 ? Theme.success : Theme.danger)
                        }
                        if t.excluded > 0 {
                            Text("\(t.excluded) position\(t.excluded > 1 ? "s" : "") sans coût en euros connu (devise ou taux d'achat à confirmer) : hors plus-value.")
                                .font(.caption).foregroundStyle(Theme.warning)
                        }
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
                                    HStack { Text(h.symbol).font(.headline).foregroundStyle(Theme.textPrimary); Text(h.kind).font(.caption2).padding(.horizontal,5).padding(.vertical,1).raisedSurface(Capsule(), .nested).foregroundStyle(Theme.textSecondary) }
                                    Text("\(h.quantity, specifier: "%.4g") × \(h.currentPrice, format: .currency(code: "EUR"))").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text(h.value, format: .currency(code: "EUR")).bold().foregroundStyle(Theme.textPrimary)
                                    if let pct = h.pnlPct, let pnl = h.pnl {
                                        Text("\(pct >= 0 ? "+" : "")\(pct, specifier: "%.1f")%").font(.caption).foregroundStyle(pnl >= 0 ? Theme.success : Theme.danger)
                                    } else {
                                        Text(h.buyCurrency.isEmpty ? "Devise d'achat à confirmer" : "Taux d'achat indisponible")
                                            .font(.caption2).foregroundStyle(Theme.warning)
                                    }
                                }
                            }.card(padding: 12)
                                .onTapGesture { editingHolding = h }
                                .contextMenu {
                                    Button { editingHolding = h } label: { Label("Modifier", systemImage: "pencil") }
                                    Button(role: .destructive) { ctx.delete(h) } label: { Label("Supprimer", systemImage: "trash") }
                                }
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
        .sheet(item: $editingHolding) { HoldingEditor(holding: $0) }
        .refreshable { await refreshPrices(force: true) }
        .task { await refreshPrices(force: false) }
    }

    /// Etat de la synchro des cours, affiche a la place de l'ancienne notice.
    @ViewBuilder private var priceStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let priceError {
                Label(priceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Theme.warning)
            } else if let lastRefresh {
                Label("Cours à jour · \(lastRefresh, style: .time)", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(Theme.success)
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
        var notFound: [String] = []

        if !cryptoSymbols.isEmpty {
            switch await PriceService.cryptoPrices(symbols: cryptoSymbols, force: force) {
            case .success(let prices):
                for h in holdings where h.kind == "Crypto" {
                    if let p = prices[h.symbol.lowercased()] { h.currentPrice = p; updated += 1 } else { notFound.append(h.symbol) }
                }
            case .failure(let e):
                problems.append("Crypto : \(e)")
            }
        }

        if !stockSymbols.isEmpty {
            switch await StockService.pricesInEUR(symbols: stockSymbols, force: force) {
            case .success(let prices):
                for h in holdings where h.kind != "Crypto" {
                    if let p = prices[h.symbol.uppercased()] { h.currentPrice = p; updated += 1 } else { notFound.append(h.symbol) }
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
        // Un symbole introuvable garde son prix manuel : le dire, sinon sa ligne semble a jour.
        if !notFound.isEmpty { problems.append("Cours introuvable, prix saisi gardé : \(notFound.joined(separator: ", "))") }
        priceError = problems.isEmpty ? nil : problems.joined(separator: " · ")
    }
}

struct HoldingEditor: View {
    /// nil = nouvelle position ; sinon on corrige celle-ci (devise, date, quantite...).
    var holding: Holding? = nil
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var symbol = ""; @State private var kind = "Action"
    @State private var qty = ""; @State private var buy = ""; @State private var current = ""
    @State private var currency = "EUR"
    @State private var hasDate = false
    @State private var buyDate = Date.now
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    static let currencies = ["EUR", "USD", "GBP", "CHF", "JPY", "CAD", "SEK", "DKK", "NOK"]
    // Quantite ou prix illisible: refuse avec explication. Avant, "abc" ou
    // "1 234,5" devenait 0 et creait une position a 0.
    private var q: AmountInput.Parsed { AmountInput.parse(qty) }
    private var b: AmountInput.Parsed { AmountInput.parse(buy) }
    private var c: AmountInput.Parsed { AmountInput.parse(current, rules: .init(required: false)) }
    private var canSave: Bool {
        !symbol.trimmingCharacters(in: .whitespaces).isEmpty && q.value != nil && b.value != nil && c.message == nil
            && (currency == "EUR" || hasDate) && !saving
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Symbole (AAPL, BTC…)", text: $symbol).textInputAutocapitalization(.characters)
                Picker("Type", selection: $kind) { ForEach(["Action","ETF","Crypto"], id: \.self) { Text($0) } }
                field("Quantité", $qty, q)
                Section {
                    field("Prix d'achat (par unité)", $buy, b)
                    Picker("Devise du prix d'achat", selection: $currency) {
                        if currency.isEmpty { Text("À confirmer").tag("") }
                        ForEach(Self.currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Date d'achat", isOn: $hasDate)
                    if hasDate { DatePicker("Acheté le", selection: $buyDate, in: ...Date.now, displayedComponents: .date) }
                } footer: {
                    Text(currency == "EUR" || currency.isEmpty
                         ? "Le cours actuel est en euros. La plus-value se calcule en euros."
                         : "Prix en \(currency) : converti en euros au taux BCE du jour d'achat (date obligatoire), pour ne pas compter le change comme une plus-value.")
                }
                field("Prix actuel en euros (sinon mis à jour par le cours)", $current, c)
                if let error { Text(error).font(.caption).foregroundStyle(Theme.warning) }
            }
            .navigationTitle(holding == nil ? "Nouvelle position" : "Modifier la position").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(holding == nil ? "Ajouter" : "Enregistrer") {
                    Task { await save() }
                }.disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let h = holding else { return }
        symbol = h.symbol; kind = h.kind; qty = AmountInput.format(h.quantity); buy = AmountInput.format(h.buyPrice)
        current = AmountInput.format(h.currentPrice); currency = h.buyCurrency
        if let d = h.buyDate { hasDate = true; buyDate = d }
    }

    private func save() async {
        guard let qv = q.value, let bv = b.value, !currency.isEmpty else { error = "Choisis la devise du prix d'achat."; return }
        saving = true; defer { saving = false }
        var fx = 1.0
        if currency != "EUR" {
            do { fx = try await ExchangeRates.historicalEURPerUnit(currency, on: buyDate).eurPerUnit }
            catch {
                // Pas de taux : on enregistre quand meme, la plus-value reste « non calculée » et
                // l'ecran le dit, au lieu d'inventer un taux.
                fx = 0
            }
        }
        let current = c.value
        if let h = holding {
            h.symbol = symbol; h.kind = kind; h.quantity = qv; h.buyPrice = bv
            if let current { h.currentPrice = current }
            h.buyCurrency = currency; h.buyDate = hasDate ? buyDate : nil; h.buyFXToEUR = fx
        } else {
            // Sans prix actuel : en euros, le prix d'achat converti ; le cours le remplacera.
            let start = current ?? (fx > 0 ? bv * fx : bv)
            ctx.insert(Holding(symbol: symbol, kind: kind, quantity: qv, buyPrice: bv, currentPrice: start,
                               buyCurrency: currency, buyDate: hasDate ? buyDate : nil, buyFXToEUR: fx))
        }
        do { try ctx.save(); dismiss() }
        catch { ctx.rollback(); self.error = "Enregistrement impossible, réessaie." }
        if fx == 0 { AppLog.data.notice("taux BCE indisponible pour \(currency, privacy: .public)") }
    }

    private func field(_ title: String, _ text: Binding<String>, _ parsed: AmountInput.Parsed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title); Spacer(); TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
            if !text.wrappedValue.isEmpty, let m = parsed.message { Text(m).font(.caption).foregroundStyle(Theme.warning) }
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
    @AppStorage(AppStorageKeys.fireFees) private var fees = 0.5
    @AppStorage(AppStorageKeys.fireInflation) private var inflation = 2.0
    @AppStorage(AppStorageKeys.fireIncludeOther) private var includeOtherAssets = false

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
                        Text(netWorth, format: .currency(code: "EUR")).font(.system(size: 34, weight: .bold)).foregroundStyle(netWorth >= 0 ? Theme.textPrimary : Theme.danger)
                        HStack {
                            Label("\(Int(assets))€ actifs", systemImage: "arrow.up").font(.caption).foregroundStyle(Theme.success)
                            Label("\(Int(liabilities))€ passifs", systemImage: "arrow.down").font(.caption).foregroundStyle(Theme.danger)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).card()

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Projection FIRE", subtitle: "Trois scénarios, frais et inflation compris")
                        sliderRow("Investi / mois", value: $monthly, range: 0...5000, step: 50, format: "%.0f €")
                        sliderRow("Rendement annuel central", value: $annualReturn, range: -5...12, step: 0.5, format: "%.1f %%")
                        sliderRow("Frais annuels", value: $fees, range: 0...3, step: 0.1, format: "%.1f %%")
                        sliderRow("Inflation", value: $inflation, range: 0...8, step: 0.5, format: "%.1f %%")
                        sliderRow("Horizon", value: $years, range: 1...40, step: 1, format: "%.0f ans")
                        Toggle("Compter aussi les autres actifs", isOn: $includeOtherAssets)
                            .font(.subheadline).tint(.investTint)
                        Text(includeOtherAssets
                             ? "Départ : \(Int(startCapital)) € (placements + autres actifs, moins les dettes). Un logement ou une voiture ne rapportent pas ce rendement : le résultat est optimiste."
                             : "Départ : \(Int(startCapital)) € de placements. L'immobilier et les biens restent à part : ils ne rapportent pas le rendement d'un portefeuille.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        let scen = FireProjection.scenarios(start: startCapital, monthly: monthly, annualReturn: annualReturn,
                                                            fees: fees, inflation: inflation, years: Int(years))
                        Chart {
                            ForEach(scen) { s in
                                ForEach(s.points, id: \.year) { p in
                                    LineMark(x: .value("Année", p.year), y: .value("€ d'aujourd'hui", p.real))
                                        .foregroundStyle(by: .value("Scénario", s.label))
                                        // Motif propre a chaque scenario : lisible aussi en palette neutre (sans couleur).
                                        .lineStyle(StrokeStyle(lineWidth: s.id == "central" ? 3 : 1.5,
                                                               dash: s.id == "central" ? [] : (s.id == "pessimiste" ? [1.5, 3] : [7, 3])))
                                }
                            }
                        }
                        .chartForegroundStyleScale(["Pessimiste": Theme.danger, "Central": Color.investTint, "Optimiste": Theme.success])
                        .frame(height: 180)
                        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.stroke); AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                        .chartXAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                        ForEach(scen) { s in
                            let f = s.final
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(s.label) · \(s.annualReturn, specifier: "%.1f") %/an brut").font(.subheadline.weight(.semibold))
                                    Text("Versé \(Int(f.invested)) € · gain \(Int(f.nominal - f.invested)) €").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(f.real, format: .currency(code: "EUR").precision(.fractionLength(0))).font(.subheadline.bold())
                                    Text("\(f.nominal, format: .currency(code: "EUR").precision(.fractionLength(0))) nominal").font(.caption2).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        if let c = scen.first(where: { $0.id == "central" }) {
                            Text("Revenu passif à 4 %, central : \(FireProjection.safeMonthlyIncome(c.final), format: .currency(code: "EUR").precision(.fractionLength(0)))/mois en euros d'aujourd'hui.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Text("Montants en euros d'aujourd'hui (inflation retirée). Simulation, pas un conseil : les marchés peuvent faire pire que le scénario pessimiste.")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }.card()

                    HStack { SectionHeader(title: "Actifs & passifs"); Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.investTint) }.accessibilityLabel("Ajouter") }
                    ForEach(items) { it in
                        HStack {
                            Image(systemName: it.kind == "Actif" ? "plus.circle" : "minus.circle").foregroundStyle(it.kind == "Actif" ? Theme.success : Theme.danger)
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
    /// Capital qui travaille vraiment : les placements, et les autres actifs seulement
    /// si l'utilisateur le demande (dettes deduites dans ce cas).
    private var startCapital: Double {
        let invested = holdings.reduce(0) { $0 + $1.value }
        return max(0, includeOtherAssets ? netWorth : invested)
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
                        StatTile(value: "\(Int(totalCashflow))€", label: "Cashflow/mois", icon: "arrow.left.arrow.right", tint: totalCashflow >= 0 ? Theme.success : Theme.danger)
                        StatTile(value: "\(Int(totalEquity/1000))k€", label: "Equity nette", icon: "house")
                    }
                    if props.isEmpty {
                        EmptyState(icon: "house", title: "Aucun bien", message: "Ajoute un bien : valeur, loyer, charges, crédit. (Utile pour ta thèse Action Logement.)")
                    } else {
                        ForEach(props) { p in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Text(p.name).font(.headline).foregroundStyle(Theme.textPrimary); Spacer(); Text(p.value, format: .currency(code: "EUR")).bold().foregroundStyle(.investTint) }
                                HStack {
                                    metric("Loyer", p.monthlyRent, Theme.success)
                                    metric("Charges", -p.monthlyCharges, Theme.warning)
                                    metric("Crédit", -p.loanPayment, Theme.danger)
                                }
                                Divider().overlay(Theme.stroke)
                                HStack {
                                    Text("Cashflow net").font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text("\(p.monthlyCashflow >= 0 ? "+" : "")\(p.monthlyCashflow, format: .currency(code: "EUR"))/mois").bold().foregroundStyle(p.monthlyCashflow >= 0 ? Theme.success : Theme.danger)
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
                    .buttonStyle(LifeOSGlassButtonStyle()).tint(.investTint)
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

    /// Premier montant illisible, ou nil.
    private var propertyInputError: String? {
        for (label, raw) in [("Valeur", value), ("Loyer", rent), ("Charges", charges), ("Capital restant", loanRemaining), ("Mensualité", loanPayment)] {
            if let m = AmountInput.parse(raw, rules: .optional).message { return "\(label) : \(m)" }
        }
        return nil
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
                if let propertyInputError {
                    Text(propertyInputError).font(.caption).foregroundStyle(Theme.warning)
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
                    // Montants lus comme partout ailleurs ("1 200", "1 234,50") : `Double(x) ?? 0`
                    // transformait une saisie collee en 0 EUR sans rien dire.
                    func v(_ s: String) -> Double { AmountInput.parse(s, rules: .optional).value ?? 0 }
                    ctx.insert(Property(name: name, value: v(value), monthlyRent: v(rent), monthlyCharges: v(charges), loanRemaining: v(loanRemaining), loanPayment: v(loanPayment))); dismiss()
                }.disabled(name.isEmpty || propertyInputError != nil) }
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
                            .font(.footnote).foregroundStyle(Theme.warning)
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
    @State private var children = 0
    @State private var status: FrenchTax.Status = .single

    /// Le nombre de parts ne peut pas descendre sous la base de la situation:
    /// un couple fait deux parts, pas une.
    private var effectiveParts: Double { max(status.baseParts, parts) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Tes paramètres")
                        Picker("Situation", selection: $status) {
                            ForEach(FrenchTax.Status.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Revenu net imposable"); Spacer()
                                // Montant exact au clavier : le curseur seul n'allait que de
                                // 10 000 a 200 000 EUR par pas de 1 000.
                                TextField("Revenu", value: $income, format: .number.precision(.fractionLength(0)))
                                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 120).bold().foregroundStyle(.investTint)
                                Text("€").foregroundStyle(.investTint)
                            }
                            Slider(value: Binding(get: { min(max(income, 0), 300_000) }, set: { income = $0 }),
                                   in: 0...300_000, step: 500).tint(.investTint)
                        }
                        Stepper("Enfants à charge : \(children)", value: $children, in: 0...10)
                            .onChange(of: children) { _, c in parts = FrenchTax.parts(status: status, children: c) }
                            .onChange(of: status) { _, s in parts = FrenchTax.parts(status: s, children: children) }
                        VStack(alignment: .leading) {
                            HStack { Text("Parts fiscales"); Spacer()
                                Text(String(format: "%.1f", effectiveParts)).bold().foregroundStyle(.investTint) }
                            Slider(value: $parts, in: 1...8, step: 0.5).tint(.investTint)
                            Text("Une demi-part pour chacun des 2 premiers enfants, une part entière à partir du 3e. Ajuste les parts à la main pour un cas particulier (parent isolé, invalidité).")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }.card()

                    let r = FrenchTax.compute(income: income, parts: effectiveParts, status: status)
                    VStack(spacing: 12) {
                        ZStack {
                            ProgressRing(progress: income > 0 ? r.total / income : 0, lineWidth: 14, tint: .investTint)
                            VStack {
                                Text(r.total, format: .currency(code: "EUR"))
                                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                                Text("d'impôt").font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }.frame(width: 190, height: 190)
                        HStack(spacing: 12) {
                            StatTile(value: String(format: "%.1f%%", income > 0 ? r.total / income * 100 : 0),
                                     label: "Taux moyen", icon: "percent")
                            StatTile(value: String(format: "%.0f%%", r.marginalRate * 100),
                                     label: "Ta tranche", icon: "chart.bar")
                        }
                        StatTile(value: "\(Int(income - r.total))€", label: "Net après IR", icon: "eurosign.circle")
                    }.card()

                    // Le detail, parce qu'un seul montant n'explique pas
                    // pourquoi ajouter une part ne change presque rien.
                    if r.capLoss > 0 || r.decote > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Le détail")
                            if r.capLoss > 0 {
                                row("Avantage refusé (plafond des demi-parts)", r.capLoss, Theme.warning)
                                Text("Chaque demi-part rapporte au maximum \(Int(FrenchTax.halfPartCap)) € d'impôt en moins. Au-delà, l'avantage est plafonné.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            if r.decote > 0 {
                                row("Décote (revenus modestes)", -r.decote, Theme.success)
                            }
                        }.card()
                    }

                    Text("Barème 2026 sur les revenus 2025, quotient familial plafonné et décote comprise. Estimation indicative : les réductions et crédits d'impôt ne sont pas pris en compte.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Fiscalité").navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ amount: Double, _ tint: Color) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(amount, format: .currency(code: "EUR")).bold().foregroundStyle(tint)
        }
    }
}

