import SwiftUI
import SwiftData
import Charts

extension ShapeStyle where Self == Color { static var investTint: Color { AppCategory.invest.tint } }

// MARK: - Hub Investissement

struct InvestHubView: View {
    var body: some View {
        HubScaffold(category: .invest) {
            ToolRow(icon: "bitcoinsign.circle.fill", title: "Crypto",
                    subtitle: "Marché, risque et potentiel en temps réel", tint: .investTint) { CryptoAppView() }
            ToolRow(icon: "chart.pie.fill", title: "Portefeuille",
                    subtitle: "Actions + crypto en un dashboard", tint: .investTint) { PortfolioView() }
            ToolRow(icon: "chart.line.uptrend.xyaxis", title: "Net worth & FIRE",
                    subtitle: "Patrimoine + projection", tint: .investTint) { NetWorthView() }
            ToolRow(icon: "house.fill", title: "Immobilier",
                    subtitle: "Biens, loyers, cashflow", tint: .investTint) { RealEstateView() }
            ToolRow(icon: "percent", title: "Simulateur fiscalité",
                    subtitle: "Impôt sur le revenu (FR)", tint: .investTint) { TaxSimulatorView() }
        }
    }
}

// MARK: - Portefeuille

struct PortfolioView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var holdings: [Holding]
    @State private var showAdd = false
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
                        IntegrationNotice(text: "Les prix sont saisis manuellement. Pour des cours en temps réel, branche une API gratuite : CoinGecko (crypto) ou Finnhub/Twelve Data (actions) — un simple appel HTTP qui met à jour currentPrice.")
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Portefeuille").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { HoldingEditor() }
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
    @AppStorage("fireMonthly") private var monthly = 500.0
    @AppStorage("fireReturn") private var annualReturn = 7.0
    @AppStorage("fireYears") private var years = 20.0

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

                    HStack { SectionHeader(title: "Actifs & passifs"); Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").foregroundStyle(.investTint) } }
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
                    IntegrationNotice(text: "Le scan d'annonces (LeBonCoin/SeLoger) pour estimer un bien est faisable via parsing d'URL + un modèle qui extrait surface/prix/loyer estimé. À brancher : champ « coller une annonce » → analyse → pré-remplissage du bien.")
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Immobilier").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { PropertyEditor() }
    }
    private func metric(_ label: String, _ v: Double, _ c: Color) -> some View {
        VStack { Text("\(Int(v))€").font(.subheadline.bold()).foregroundStyle(c); Text(label).font(.caption2).foregroundStyle(Theme.textSecondary) }.frame(maxWidth: .infinity)
    }
}

struct PropertyEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var value = ""; @State private var rent = ""
    @State private var charges = ""; @State private var loanRemaining = ""; @State private var loanPayment = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom / adresse", text: $name)
                HStack { Text("Valeur"); Spacer(); TextField("0", text: $value).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Loyer mensuel"); Spacer(); TextField("0", text: $rent).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Charges mensuelles"); Spacer(); TextField("0", text: $charges).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Capital restant dû"); Spacer(); TextField("0", text: $loanRemaining).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
                HStack { Text("Mensualité crédit"); Spacer(); TextField("0", text: $loanPayment).keyboardType(.numberPad).multilineTextAlignment(.trailing) }
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
