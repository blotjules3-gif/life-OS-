import SwiftUI
import SwiftData

// MARK: - Ajouter un titre

/// Symbole + place, verifie par une vraie lecture avant l'ajout. Hors ligne, l'ajout
/// reste possible : le titre s'affiche "Cours en attente" puis son erreur s'il n'existe pas.
struct WatchlistAddSheet: View {
    let listNames: [String]
    let defaultList: String
    /// Appele apres un ajout (nom de la liste) ou une fermeture (nil).
    var onDone: (String?) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var place: StockPlace = .auto
    @State private var list = ""
    @State private var checking = false
    @State private var adding = false
    @State private var result: Result<StockQuote, StockFetchError>?
    @State private var checkedSymbol = ""
    @State private var message: String?

    private var symbol: String { WatchlistOps.normalizedSymbol(raw, place: place) }
    private var plausible: Bool { WatchlistOps.isPlausibleSymbol(symbol) }
    private var isChecked: Bool { checkedSymbol == symbol }
    private var canAdd: Bool {
        guard plausible, isChecked, !adding, let result else { return false }
        if case .failure(let e) = result, e == .notFound || e == .decoding { return false }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Symbole (MC, AAPL, CW8…)", text: $raw)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .onSubmit { Task { await check() } }
                    Picker("Place boursière", selection: $place) {
                        ForEach(StockPlace.allCases) { Text($0.label).tag($0) }
                    }
                    if !symbol.isEmpty {
                        LabeledContent("Symbole lu", value: symbol)
                    }
                } footer: {
                    Text("Symbole Yahoo Finance : MC.PA pour LVMH à Paris, AAPL pour Apple, VOD.L pour Londres.")
                }

                Section {
                    Button { Task { await check() } } label: {
                        HStack {
                            if checking { ProgressView().controlSize(.small) }
                            Text(checking ? "Vérification…" : "Vérifier le symbole")
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(!plausible || checking)
                    if isChecked, let result { resultView(result) }
                }

                Section("Liste") {
                    Picker("Ajouter à", selection: $list) {
                        ForEach(listNames, id: \.self) { Text($0).tag($0) }
                    }
                }
                if let message { Text(message).font(.caption).foregroundStyle(Theme.warning) }
            }
            .navigationTitle("Suivre un titre").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { onDone(nil); dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") { add() }.disabled(!canAdd) }
            }
            .onAppear { if list.isEmpty { list = listNames.contains(defaultList) ? defaultList : (listNames.first ?? WatchlistDefaults.listName) } }
        }
    }

    @ViewBuilder private func resultView(_ r: Result<StockQuote, StockFetchError>) -> some View {
        switch r {
        case .success(let q):
            VStack(alignment: .leading, spacing: 4) {
                Text(q.name.isEmpty ? q.symbol : q.name).font(.headline)
                Text("\(q.exchangeFullName) · \(q.currency)").font(.caption).foregroundStyle(Theme.textSecondary)
                Text(StockFormat.price(q.price, currency: q.currency)).font(.subheadline.bold().monospacedDigit())
                Text(StockFormat.statusLine(q)).font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case .failure(let e):
            VStack(alignment: .leading, spacing: 4) {
                Label(e.message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
                if e == .notFound {
                    Text("Vérifie la place boursière : un titre européen a souvent un suffixe (.PA, .DE, .L).")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Tu peux l'ajouter quand même : le cours sera vérifié plus tard.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func check() async {
        guard plausible, !checking else { return }
        checking = true; defer { checking = false }
        message = nil
        let s = symbol
        let r = await QuoteStore.shared.validate(s)
        checkedSymbol = s
        result = r
    }

    private func add() {
        guard canAdd else { return }
        adding = true
        var name = "", exchange = ""
        if case .success(let q)? = result { name = q.name; exchange = q.exchangeFullName }
        switch WatchlistOps.add(symbol: symbol, displayName: name, exchangeLabel: exchange, to: list, in: ctx) {
        case .added:
            do { try ctx.save(); onDone(list); dismiss() }
            catch { ctx.rollback(); message = "Enregistrement impossible, réessaie."; adding = false }
        case .duplicate:
            message = "\(symbol) est déjà dans « \(list) »."; adding = false
        case .invalid:
            message = "Symbole invalide."; adding = false
        }
    }
}

// MARK: - Options d'une liste

struct WatchlistOptionsSheet: View {
    let group: WatchlistGroup
    let otherNames: [String]
    var onSaved: (String) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency: StockDisplayCurrency = .original
    @State private var period: StockPeriod = .day1
    @State private var sparkline = true
    @State private var loaded = false
    @State private var saving = false

    private var validName: String? { WatchlistOps.validListName(name, existing: otherNames, current: group.name) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nom") { TextField("Nom de la liste", text: $name) }
                Section {
                    Picker("Devise d'affichage", selection: $currency) {
                        ForEach(StockDisplayCurrency.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Période du graphique", selection: $period) {
                        ForEach(StockPeriod.allCases) { Text($0.spoken).tag($0) }
                    }
                    Toggle("Afficher le graphique", isOn: $sparkline)
                } footer: {
                    Text("En euro, les cours sont convertis au dernier taux connu (Yahoo Finance) ; la devise de cotation reste indiquée.")
                }
                if validName == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Ce nom est déjà pris.").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            .navigationTitle("Options de la liste").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(validName == nil || saving) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = group.name; currency = group.currency; period = group.chartPeriod; sparkline = group.showSparkline
            }
        }
    }

    private func save() {
        guard let n = validName, !saving else { return }
        saving = true
        WatchlistOps.rename(group, to: n, in: ctx)
        group.displayCurrency = currency.rawValue
        group.period = period.rawValue
        group.showSparkline = sparkline
        do { try ctx.save(); onSaved(n); dismiss() }
        catch { ctx.rollback(); saving = false }
    }
}

// MARK: - Nouvelle liste

struct WatchlistNewListSheet: View {
    let existing: [String]
    let nextOrder: Int
    var onCreated: (String) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var saving = false
    private var valid: String? { WatchlistOps.validListName(name, existing: existing) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (Tech US, Dividendes…)", text: $name)
                if valid == nil && !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Ce nom est déjà pris.").font(.caption).foregroundStyle(Theme.warning)
                }
            }
            .navigationTitle("Nouvelle liste").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") {
                        guard let n = valid, !saving else { return }
                        saving = true
                        ctx.insert(WatchlistGroup(name: n, order: nextOrder))
                        do { try ctx.save(); onCreated(n); dismiss() } catch { ctx.rollback(); saving = false }
                    }.disabled(valid == nil || saving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Entree depuis un lien profond

/// lifeos://stocks?symbol=X&list=Y : ouvre la liste et met le titre en avant.
/// A presenter dans une NavigationStack (le routeur de l'app s'en charge).
struct StockDeepLinkView: View {
    let url: URL
    var body: some View {
        let link = StockDeepLink.parse(url)
        if link?.portfolio == true {
            PortfolioView()
        } else {
            WatchlistView(initialList: link?.list, focusSymbol: link?.symbol)
        }
    }
}
