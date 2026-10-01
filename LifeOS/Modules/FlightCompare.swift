import SwiftUI
import SwiftData
import EventKit
import UserNotifications

// MARK: - Comparateur de vols LifeOS
//
// Le moteur est a nous (flights-api). Cet ecran ne montre jamais un autre
// comparateur et ne prete a aucune source plus qu'elle ne donne: bagages
// inconnus, frais inconnus, source en panne et donnees de demo sont dits.

struct FlightCompareView: View {
    @StateObject private var library = FlightLibrary()
    @State private var query = FlightSearch.Query()
    @State private var filters = FlightSearch.Filters()
    @State private var sort: Sort = .best
    @State private var result: FlightSearch.Result?
    @State private var searchedQuery: FlightSearch.Query?
    @State private var loading = false
    @State private var errorText: String?
    @State private var task: Task<Void, Never>?
    @State private var showSaved = false
    @State private var alertDraft: Double?
    @State private var info: FlightSearch.Info?

    enum Sort: String, CaseIterable, Identifiable { case best, cheapest, fastest
        var id: String { rawValue }
        var label: String { switch self { case .best: "Meilleur"; case .cheapest: "Moins cher"; case .fastest: "Plus rapide" } }
    }

    private var endpoint: FlightSearch.Endpoint? { FlightSearch.endpoint }

    /// Filtres et classement viennent du serveur: une seule regle, et le "meilleur"
    /// est recalcule apres filtrage au lieu de garder un ordre devenu faux.
    private var shown: [FlightSearch.Group] {
        guard let r = result else { return [] }
        return switch sort { case .best: r.best; case .cheapest: r.cheapest; case .fastest: r.fastest }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                LazyVStack(spacing: 14) {
                    if endpoint == nil { notConnectedCard }
                    FlightQueryForm(query: $query, searching: loading, onSearch: { runSearch() }, onCancel: cancel)
                    if !library.saved.history.isEmpty && result == nil && !loading { historyCard }
                    if let errorText { errorCard(errorText) }
                    if let writeError = library.writeError { errorCard(writeError) }
                    if loading { ProgressView(result == nil ? "Recherche dans les sources…" : "D'autres sources répondent encore…").padding(.vertical, 12) }
                    if let r = result, let q = searchedQuery { results(r, query: q) }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Comparateur de vols").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSaved = true } label: { Image(systemName: "star") }
                    .accessibilityLabel("Favoris et alertes")
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
        .sheet(isPresented: $showSaved) { FlightSavedSheet(library: library) { q in query = q; showSaved = false; runSearch() } }
        .onDisappear { task?.cancel() }
        .onChange(of: filters) { _, _ in if searchedQuery != nil { runSearch(searchedQuery) } }
        .task { await loadInfo() }
        #if DEBUG
        .task { debugPrefill() }
        #endif
    }

    #if DEBUG
    /// `-flightsQuery LIS-CDG-30` : remplit le trajet (depart dans 30 jours) et lance
    /// la recherche. Le simulateur tape mal au clavier, d'ou ce crochet.
    private func debugPrefill() {
        let args = ProcessInfo.processInfo.arguments
        guard result == nil, let i = args.firstIndex(of: "-flightsQuery"), i + 1 < args.count else { return }
        let parts = args[i + 1].split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return }
        let days = parts.count > 2 ? Int(parts[2]) ?? 30 : 30
        let out = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        query.legs = [.init(origin: parts[0], destination: parts[1], date: out)]
        query.returnDate = Calendar.current.date(byAdding: .day, value: 7, to: out) ?? out
        runSearch()
    }
    #endif

    // MARK: Cartes

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Moteur de vols pas encore branché", systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Le comparateur interroge le serveur LifeOS, qui garde les clés des compagnies et distributeurs. Ce serveur n'est pas encore en ligne, donc aucune recherche ne peut partir. Aucun prix n'est inventé en attendant.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Récentes", actionTitle: "Effacer") { library.clearHistory() }
            ForEach(library.saved.history.prefix(5), id: \.self) { q in
                Button { query = q; runSearch() } label: {
                    HStack { Image(systemName: "clock.arrow.circlepath").foregroundStyle(.travelTint); Text(q.summary).foregroundStyle(Theme.textPrimary); Spacer()
                        Text(q.cabin.label).font(.caption).foregroundStyle(Theme.textSecondary) }
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }.card()
    }

    private func errorCard(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote).foregroundStyle(Theme.warning)
            .frame(maxWidth: .infinity, alignment: .leading).card()
    }

    @ViewBuilder private func results(_ r: FlightSearch.Result, query q: FlightSearch.Query) -> some View {
        SourcesStrip(result: r)
        if (r.best + r.cheapest).contains(where: \.isDemo) {
            Label("Données de démonstration : sources de test, prix fictifs. Rien ici ne se réserve.", systemImage: "theatermasks.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.mind)
                .frame(maxWidth: .infinity, alignment: .leading).card()
        }
        VStack(alignment: .leading, spacing: 10) {
            Picker("Tri", selection: $sort) { ForEach(Sort.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
            FilterChips(filters: $filters)
            if let aside = r.setAside, aside.count > 0 {
                Text("\(aside.count) offre\(aside.count > 1 ? "s" : "") en \(aside.currencies.joined(separator: ", ")) mise\(aside.count > 1 ? "s" : "") à part : pas de taux de change daté pour les comparer honnêtement.")
                    .font(.caption).foregroundStyle(Theme.warning)
            }
            if sort == .best { Text("Meilleur : équilibre prix, durée et escales. Les transferts autonomes, changements d'aéroport et frais inconnus sont pénalisés. Aucun résultat sponsorisé.")
                .font(.caption).foregroundStyle(Theme.textSecondary) }
        }.card()

        if shown.isEmpty {
            EmptyState(icon: "airplane.departure", title: "Aucun vol", message: r.count == 0 ? "Les sources n'ont rien renvoyé pour ce trajet." : "Aucun vol ne passe ces filtres.", tint: .travelTint)
        } else {
            ForEach(shown) { g in
                NavigationLink { FlightDetailView(group: g, query: q) } label: {
                    FlightGroupCard(group: g, favorite: library.isFavorite(g)) { library.toggleFavorite(g, query: q) }
                }.buttonStyle(.plain)
            }
            alertCard(query: q)
        }
    }

    private func alertCard(query q: FlightSearch.Query) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Surveiller le prix", systemImage: "bell.badge").font(.headline).foregroundStyle(Theme.textPrimary)
            // Seulement un prix reel, aux frais connus, facture dans la devise de la recherche.
            let best = shown.flatMap(\.offers).filter { !$0.demo && $0.price.taxesKnown && $0.price.original == nil }.map(\.price.total).min()
            if info?.alerts.serverChecks != true {
                Text("La surveillance des prix n'est pas encore activée sur le serveur LifeOS. Aucune alerte ne peut être créée pour l'instant.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            } else if let best {
                let threshold = alertDraft ?? (best * 0.9).rounded()
                Stepper(value: Binding(get: { threshold }, set: { alertDraft = $0 }), in: 1...max(best * 2, 10), step: 5) {
                    Text("Seuil : \(threshold.formatted(.currency(code: q.currency).precision(.fractionLength(0))))")
                }
                Button { createAlert(q, maxPrice: threshold) } label: { Label("Surveiller ce trajet", systemImage: "plus") }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true))
                Text("Le serveur revérifie ce trajet plusieurs fois par jour, sur des prix aux frais connus et facturés en \(q.currency). Quand le prix passe sous le seuil, Envol te le signale à la prochaine ouverture. Désinscription dans Favoris et alertes.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                Text("Pas de surveillance possible ici : aucun prix réel aux frais connus, facturé en \(q.currency).")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    // MARK: Actions

    /// Lance une recherche. Sans argument: la requete du formulaire; avec: la meme
    /// recherche relancee avec d'autres filtres.
    private func runSearch(_ again: FlightSearch.Query? = nil) {
        let q = again ?? query
        let problems = q.problems()
        guard problems.isEmpty else { errorText = problems.joined(separator: "\n"); return }
        task?.cancel()
        errorText = nil; loading = true
        if again == nil { alertDraft = nil; result = nil }
        let f = filters
        task = Task {
            do {
                let r = try await FlightSearch.searchStream(q, filters: f) { partial in
                    guard !Task.isCancelled else { return }
                    result = partial; searchedQuery = q
                }
                guard !Task.isCancelled else { return }
                result = r; searchedQuery = q
                if again == nil { library.remember(q) }
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled { errorText = error.localizedDescription }
            }
            if !Task.isCancelled { loading = false }
        }
    }

    private func loadInfo() async {
        guard FlightSearch.endpoint != nil else { return }
        info = try? await FlightSearch.info()
        await FlightAlertsCheck.run(library)
    }

    private func cancel() { task?.cancel(); loading = false }

    private func createAlert(_ q: FlightSearch.Query, maxPrice: Double) {
        Task {
            do {
                let ticket = try await FlightSearch.createAlert(q, maxPrice: maxPrice)
                library.add(.init(ticket: ticket, query: q, maxPrice: maxPrice, createdAt: .now))
                errorText = nil; showSaved = true
            } catch { errorText = error.localizedDescription }
        }
    }
}

// MARK: - Formulaire

struct FlightQueryForm: View {
    @Binding var query: FlightSearch.Query
    var searching: Bool
    var onSearch: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Type", selection: $query.kind) { ForEach(FlightSearch.TripKind.allCases) { Text($0.label).tag($0) } }
                .pickerStyle(.segmented)
                .onChange(of: query.kind) { _, k in
                    if k == .multiCity && query.legs.count < 2 {
                        let first = query.legs.first ?? .init()
                        query.legs = [first, .init(origin: first.destination, date: Calendar.current.date(byAdding: .day, value: 3, to: first.date) ?? first.date)]
                    }
                    if k != .multiCity { query.legs = Array(query.legs.prefix(1)) }
                }

            ForEach($query.legs) { $leg in
                VStack(alignment: .leading, spacing: 8) {
                    if query.kind == .multiCity { Text("Trajet \((query.legs.firstIndex(where: { $0.id == leg.id }) ?? 0) + 1)").font(.caption.bold()).foregroundStyle(.travelTint) }
                    HStack(spacing: 8) {
                        airportField("De", text: $leg.origin)
                        Button { let o = leg.origin; leg.origin = leg.destination; leg.destination = o } label: { Image(systemName: "arrow.left.arrow.right") }
                            .buttonStyle(.plain).foregroundStyle(.travelTint).accessibilityLabel("Inverser départ et arrivée")
                        airportField("Vers", text: $leg.destination)
                    }
                    DatePicker(query.kind == .roundTrip ? "Aller" : "Date", selection: $leg.date, in: Date()..., displayedComponents: .date)
                }
            }
            if query.kind == .roundTrip, let out = query.legs.first {
                DatePicker("Retour", selection: $query.returnDate, in: out.date..., displayedComponents: .date)
            }
            if query.kind == .multiCity {
                HStack {
                    Button { query.legs.append(.init(origin: query.legs.last?.destination ?? "", date: query.legs.last?.date ?? .now)) } label: { Label("Ajouter un trajet", systemImage: "plus") }
                        .disabled(query.legs.count >= 6)
                    Spacer()
                    Button(role: .destructive) { query.legs.removeLast() } label: { Label("Retirer", systemImage: "minus") }
                        .disabled(query.legs.count <= 2)
                }.font(.subheadline)
            }

            Divider()
            Stepper("Adultes : \(query.passengers.adults)", value: $query.passengers.adults, in: 1...9)
            Stepper("Enfants (2 à 17 ans) : \(query.passengers.children)", value: $query.passengers.children, in: 0...8)
                .onChange(of: query.passengers.children) { _, n in
                    var ages = query.passengers.childAges
                    if ages.count > n { ages.removeLast(ages.count - n) }
                    while ages.count < n { ages.append(0) }          // 0 = age a choisir, jamais devine
                    query.passengers.childAges = ages
                }
            ForEach(0..<query.passengers.children, id: \.self) { i in
                LabeledContent("Âge de l'enfant \(i + 1)") {
                    Picker("Âge de l'enfant \(i + 1)", selection: Binding(
                        get: { query.passengers.childAges[safe: i] ?? 0 },
                        set: { v in if query.passengers.childAges.indices.contains(i) { query.passengers.childAges[i] = v } })) {
                        Text("À choisir").tag(0)
                        ForEach(2...17, id: \.self) { Text("\($0) ans").tag($0) }
                    }.labelsHidden()
                }
            }
            Stepper("Bébés (sur les genoux) : \(query.passengers.infants)", value: $query.passengers.infants, in: 0...query.passengers.adults)
            LabeledContent("Classe") {
                Picker("Classe", selection: $query.cabin) { ForEach(FlightSearch.Cabin.allCases) { Text($0.label).tag($0) } }.labelsHidden()
            }
            LabeledContent("Escales au plus") {
                Picker("Escales au plus", selection: $query.maxConnections) { Text("Direct").tag(0); Text("1").tag(1); Text("2").tag(2) }.labelsHidden()
            }

            HStack {
                if searching {
                    Button(role: .cancel, action: onCancel) { Label("Annuler", systemImage: "xmark") }
                        .buttonStyle(LifeOSGlassButtonStyle()).keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(action: onSearch) { Label("Rechercher", systemImage: "magnifyingglass") }
                    .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.travelTint)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(searching)
            }
        }.card()
    }

    private func airportField(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.uppercased().filter(\.isLetter).prefix(3)) }))
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .font(.title3.monospaced().weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .glassControl(Capsule())
            .onSubmit(onSearch)
            .accessibilityLabel("\(label), code aéroport")
    }
}

// MARK: - Bandeau des sources

struct SourcesStrip: View {
    let result: FlightSearch.Result
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(result.partial ? "Résultats partiels" : "Toutes les sources ont répondu",
                      systemImage: result.partial ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(result.partial ? Theme.warning : Theme.success)
                Spacer()
                if result.cached { Text("en cache, \((result.cachedAgeMs ?? 0) / 60000) min").font(.caption).foregroundStyle(Theme.textSecondary) }
            }
            ForEach(result.statuses.keys.sorted(), id: \.self) { id in
                let s = result.statuses[id]!
                HStack { Text(id).font(.caption.monospaced()); Spacer(); Text(FlightSearch.statusLabel(s)).font(.caption).foregroundStyle(s.status == "ok" ? Theme.textSecondary : Theme.warning) }
            }
        }.card()
    }
}

// MARK: - Filtres

struct FilterChips: View {
    @Binding var filters: FlightSearch.Filters
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Direct", on: filters.maxStops == 0) { filters.maxStops = filters.maxStops == 0 ? nil : 0 }
                chip("Bagage soute inclus", on: filters.checkedBagRequired) { filters.checkedBagRequired.toggle() }
                chip("Sans transfert autonome", on: filters.noSelfTransfer) { filters.noSelfTransfer.toggle() }
                chip("Même aéroport", on: filters.noAirportChange) { filters.noAirportChange.toggle() }
            }
        }
    }
    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) { if on { Image(systemName: "checkmark") }; Text(title) }
                .font(.caption.weight(.semibold)).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(on ? Color.travelTint : Theme.textPrimary)
                .glassControl(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Carte d'itineraire

struct FlightGroupCard: View {
    let group: FlightSearch.Group
    var favorite: Bool
    var onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.displaySlices(group).enumerated()), id: \.offset) { i, s in
                let a = group.analysis.slices[safe: i]
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.timesLabel(s))
                            .font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                        Text("\(s.origin.iata) → \(s.destination.iata) · \(Self.carrierLabel(s))")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(FlightSearch.duration(a?.durationMinutes)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                        Text(FlightSearch.stopsLabel(a?.stops ?? 0)).font(.caption).foregroundStyle((a?.stops ?? 0) == 0 ? Theme.success : Theme.textSecondary)
                    }
                }
            }
            ForEach(group.analysis.warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warning)
            }
            if let explanation = group.explanation { Text(explanation).font(.caption2).foregroundStyle(Theme.textSecondary) }
            Divider()
            HStack {
                if let o = group.cheapest {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dès \(FlightSearch.priceLabel(o.price))").font(.headline).foregroundStyle(.travelTint)
                        Text("\(group.offers.count) offre\(group.offers.count > 1 ? "s" : "") · \(group.sources.count) source\(group.sources.count > 1 ? "s" : "")\(o.price.taxesKnown ? "" : " · frais inconnus")")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                if group.isDemo { Text("FICTIF").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3).background(Theme.mind.opacity(0.18), in: Capsule()).foregroundStyle(Theme.mind) }
                Spacer()
                Button(action: onFavorite) { Image(systemName: favorite ? "star.fill" : "star").foregroundStyle(favorite ? Theme.learning : Theme.textSecondary) }
                    .buttonStyle(.plain).accessibilityLabel(favorite ? "Retirer des favoris" : "Ajouter aux favoris")
            }
        }.card()
    }
}

extension FlightGroupCard {
    /// Donnees serveur: un groupe sans offre ou un trajet sans segment ne doit
    /// jamais faire planter l'app (avant: offers[0] et segments.first!).
    static func displaySlices(_ group: FlightSearch.Group) -> [FlightSearch.Slice] {
        group.offers.first?.slices ?? []
    }

    static func timesLabel(_ s: FlightSearch.Slice) -> String {
        guard let first = s.segments.first, let last = s.segments.last else { return "Horaires inconnus" }
        return "\(FlightSearch.clock(first.departingAt)) → \(FlightSearch.clock(last.arrivingAt))"
    }

    static func carrierLabel(_ s: FlightSearch.Slice) -> String {
        s.segments.compactMap(\.marketingCarrier.name).first
            ?? s.segments.compactMap(\.marketingCarrier.code).first
            ?? "Compagnie inconnue"
    }
}

extension Array { subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil } }

// MARK: - Detail

struct FlightDetailView: View {
    let group: FlightSearch.Group
    let query: FlightSearch.Query

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    let slices = FlightGroupCard.displaySlices(group)
                    ForEach(Array(slices.enumerated()), id: \.offset) { i, s in
                        SliceTimeline(slice: s, analysis: group.analysis.slices[safe: i], index: i, total: slices.count)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Offres", subtitle: "\(group.offers.count) pour ce même itinéraire, triées par prix")
                        Text("Chaque offre reste séparée : vendeur, tarif, bagages et conditions peuvent différer. Le prix affiché est revérifié chez la source avant toute suite.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                    ForEach(group.offers) { o in
                        OfferCard(group: group, offer: o, reference: group.offers.first, query: query)
                    }
                }.padding(Theme.pad).frame(maxWidth: 820).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(FlightGroupCard.displaySlices(group).map { "\($0.origin.iata)→\($0.destination.iata)" }.joined(separator: " · "))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SliceTimeline: View {
    let slice: FlightSearch.Slice
    let analysis: FlightSearch.SliceAnalysis?
    let index: Int, total: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: total == 1 ? "Vol" : index == 0 ? "Aller" : (total == 2 ? "Retour" : "Trajet \(index + 1)"),
                          subtitle: "\(FlightSearch.duration(analysis?.durationMinutes)) · \(FlightSearch.stopsLabel(analysis?.stops ?? 0))")
            ForEach(Array(slice.segments.enumerated()), id: \.offset) { i, seg in
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(FlightSearch.clock(seg.departingAt))  \(seg.origin.iata)").font(.headline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    Text("\(seg.flightLabel) · \(seg.marketingCarrier.name ?? seg.marketingCarrier.code ?? "")\(seg.codeshare ? ", opéré par \(seg.operatingCarrier.name ?? seg.operatingCarrier.code ?? "?")" : "")\(seg.fareBrand.map { " · \($0)" } ?? "")")
                        .font(.caption).foregroundStyle(Theme.textSecondary).padding(.leading, 14)
                    Text("\(FlightSearch.clock(seg.arrivingAt))  \(seg.destination.iata)\(seg.arrivingAt.prefix(10) != seg.departingAt.prefix(10) ? "  (+1 j)" : "")")
                        .font(.headline.monospacedDigit()).foregroundStyle(Theme.textPrimary)
                    Text("Heures locales de chaque aéroport.").font(.caption2).foregroundStyle(Theme.textSecondary).opacity(i == 0 ? 1 : 0)
                }
                if let l = analysis?.layovers[safe: i] {
                    VStack(alignment: .leading, spacing: 3) {
                        Label("Correspondance à \(l.at) : \(FlightSearch.duration(l.minutes))", systemImage: "clock").font(.caption.weight(.semibold))
                        if l.airportChange { Label("Changement d'aéroport", systemImage: "arrow.triangle.swap").font(.caption).foregroundStyle(Theme.warning) }
                        if l.overnight { Label("Nuit sur place", systemImage: "moon.zzz").font(.caption).foregroundStyle(Theme.warning) }
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading).glassControl(RoundedRectangle(cornerRadius: 14))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct OfferCard: View {
    let group: FlightSearch.Group
    let offer: FlightSearch.Offer
    let reference: FlightSearch.Offer?
    let query: FlightSearch.Query
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Trip.start) private var trips: [Trip]
    @State private var checking = false
    @State private var confirmation: FlightSearch.Confirmation?
    @State private var errorText: String?
    @State private var addedTo: String?
    @State private var calendarText: String?

    private var current: FlightSearch.Offer { confirmation?.offer ?? offer }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.seller.name).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text("source : \(offer.provider)").font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(FlightSearch.priceLabel(current.price)).font(.title3.bold()).foregroundStyle(.travelTint)
            }
            facts
            if let ref = reference, ref.id != offer.id {
                let diff = FlightSearch.differences(ref, offer)
                if !diff.isEmpty { Text("Diffère de l'offre la moins chère : \(diff.joined(separator: ", ")). Comparer les prix seuls serait trompeur.").font(.caption).foregroundStyle(Theme.warning) }
            }
            confirmationView
            actions
            if let errorText { Text(errorText).font(.caption).foregroundStyle(Theme.warning) }
        }.card()
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("suitcase.rolling", "Bagage soute", current.baggage.checked.map { $0 == 0 ? "non inclus pour tous" : "\($0) garanti à chaque voyageur" } ?? "inconnu")
            fact("bag", "Bagage cabine", current.baggage.carryOn.map { $0 == 0 ? "non inclus pour tous" : "\($0) garanti à chaque voyageur" } ?? "inconnu")
            if current.baggage.varies == true, let list = current.baggage.perPassenger {
                ForEach(list, id: \.self) { p in
                    fact("person", p.label, "soute \(p.checked.map(String.init) ?? "?") · cabine \(p.carryOn.map(String.init) ?? "?")")
                }
            }
            if let note = FlightSearch.billedNote(current.price) { fact("banknote", "Devise", note) }
            fact("arrow.uturn.backward", "Remboursable", yesNo(current.conditions.refundable))
            fact("calendar.badge.clock", "Modifiable", yesNo(current.conditions.changeable))
            fact("eurosign", "Taxes et frais", current.price.taxesKnown ? "inclus et connus" : "pas tous connus, le prix peut augmenter")
            if let e = current.expiry { fact("hourglass", "Offre valable jusqu'à", e.formatted(.dateTime.day().month().hour().minute())) }
            if current.selfTransfer { fact("figure.walk", "Transfert autonome", "oui, correspondance à ta charge") }
        }.font(.caption)
    }

    private func fact(_ icon: String, _ k: String, _ v: String) -> some View {
        HStack(alignment: .top) { Image(systemName: icon).frame(width: 18).foregroundStyle(.travelTint); Text(k).foregroundStyle(Theme.textSecondary); Spacer(); Text(v).multilineTextAlignment(.trailing).foregroundStyle(v == "inconnu" ? Theme.warning : Theme.textPrimary) }
    }
    private func yesNo(_ b: Bool?) -> String { b.map { $0 ? "oui" : "non" } ?? "inconnu" }

    @ViewBuilder private var confirmationView: some View {
        if let c = confirmation {
            switch c.status {
            case "same_price": Label("Prix confirmé chez la source.", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.success)
            case "price_changed":
                if let delta = c.delta {
                    Label("Nouveau prix : \(c.offer.map { FlightSearch.priceLabel($0.price) } ?? "?") (\(delta > 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(0...2)))) \(c.previousCurrency ?? offer.price.currency) facturés).",
                          systemImage: "arrow.up.arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                } else {
                    Label(c.reason ?? "Le prix a changé.", systemImage: "arrow.up.arrow.down.circle.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                }
            case "error": Label("Vérification impossible : \(c.reason ?? "la source ne répond pas").", systemImage: "wifi.exclamationmark").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
            default: Label("Plus disponible : \(c.reason ?? "offre expirée ou vendue").", systemImage: "xmark.octagon.fill").font(.caption.weight(.semibold)).foregroundStyle(Theme.danger)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        let confirmedOK = confirmation.map { $0.status == "same_price" || $0.status == "price_changed" } ?? false
        HStack {
            Button { check() } label: { Label(checking ? "Vérification…" : "Vérifier le prix", systemImage: "arrow.clockwise") }
                .buttonStyle(LifeOSGlassButtonStyle()).disabled(checking)
            Spacer()
            Menu {
                ForEach(trips) { t in Button(t.name.isEmpty ? t.destination : t.name) { addToTrip(t) } }
                Button("Nouveau voyage") { addToNewTrip() }
                Divider()
                Button("Ajouter au calendrier") { addToCalendar() }
            } label: { Label("Ajouter", systemImage: "plus.circle") }
                .disabled(!confirmedOK && !offer.demo)
        }
        if !confirmedOK && !offer.demo { Text("Vérifie le prix avant de l'ajouter à un voyage.").font(.caption2).foregroundStyle(Theme.textSecondary) }
        if let addedTo { Label("Ajouté à « \(addedTo) », marqué non réservé.", systemImage: "checkmark").font(.caption).foregroundStyle(Theme.success) }
        if let calendarText { Text(calendarText).font(.caption).foregroundStyle(Theme.textSecondary) }
        Text(handoffText).font(.caption2).foregroundStyle(Theme.textSecondary)
    }

    private var handoffText: String {
        if offer.demo { return "Démo : rien à réserver." }
        return "Réservation non activée dans LifeOS : cette source ne fournit pas de lien vers le vendeur, et réserver par son API ferait de LifeOS le vendeur (paiement, émission, service client)."
    }

    private func check() {
        checking = true; errorText = nil
        Task {
            do { confirmation = try await FlightSearch.confirm(offer, query: query) }
            catch { errorText = error.localizedDescription }
            checking = false
        }
    }

    private func addToTrip(_ t: Trip) {
        let note = FlightSearch.tripNote(group: group, offer: current)
        t.notes = t.notes.isEmpty ? note : t.notes + "\n\n" + note
        do { try ctx.save(); addedTo = t.name.isEmpty ? t.destination : t.name }
        catch { errorText = "Voyage non enregistré : \(error.localizedDescription)" }
    }

    private func addToNewTrip() {
        let slices = current.slices
        guard let first = slices.first?.segments.first, let lastSlice = slices.last, let lastSeg = lastSlice.segments.last else { return }
        let dest = slices.count == 2 && slices[1].destination.iata == slices[0].origin.iata ? slices[0].destination.iata : lastSlice.destination.iata
        let t = Trip(name: "Voyage \(dest)", destination: dest,
                     start: first.departure ?? .now, end: lastSeg.arrival ?? first.departure ?? .now)
        ctx.insert(t)
        addToTrip(t)
    }

    private func addToCalendar() {
        let store = EKEventStore()
        store.requestWriteOnlyAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                guard granted else { calendarText = "Accès calendrier refusé."; return }
                do {
                    for seg in current.slices.flatMap(\.segments) {
                        guard let start = seg.departure, let end = seg.arrival else { continue }
                        let e = EKEvent(eventStore: store)
                        e.title = "✈︎ \(seg.flightLabel) \(seg.origin.iata)→\(seg.destination.iata) (envisagé, non réservé)"
                        e.notes = FlightSearch.tripNote(group: group, offer: current)
                        e.startDate = start; e.endDate = end
                        e.timeZone = seg.origin.timeZone.flatMap(TimeZone.init(identifier:))
                        e.calendar = store.defaultCalendarForNewEvents
                        try store.save(e, span: .thisEvent, commit: false)
                    }
                    try store.commit()
                    calendarText = "Ajouté au calendrier, marqué « envisagé, non réservé »."
                } catch { calendarText = "Calendrier : \(error.localizedDescription)" }
            }
        }
    }
}

// MARK: - Favoris et alertes

struct FlightSavedSheet: View {
    @ObservedObject var library: FlightLibrary
    var onSearch: (FlightSearch.Query) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var states: [String: FlightSearch.AlertState?] = [:]
    @State private var alertsOn: Bool?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if alertsOn == false { Text("La surveillance serveur n'est pas encore activée : les alertes existantes ne sont pas revérifiées.").font(.caption).foregroundStyle(Theme.warning) }
                    if library.saved.alerts.isEmpty { Text("Aucune alerte. Crée-en une sous des résultats.").foregroundStyle(.secondary) }
                    ForEach(library.saved.alerts) { a in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(a.query.summary).font(.subheadline.weight(.semibold))
                            Text("Seuil : \(a.maxPrice.formatted(.currency(code: a.query.currency).precision(.fractionLength(0))))").font(.caption)
                            alertStatus(a)
                        }
                        .swipeActions { Button("Désinscrire", role: .destructive) { unsubscribe(a) } }
                        .contextMenu { Button("Désinscrire", role: .destructive) { unsubscribe(a) } }
                    }
                } header: { Text("Alertes de prix") } footer: {
                    Text("Le serveur fait la vérification ; Envol te signale une baisse quand tu l'ouvres. Pas encore de notification poussée hors de l'app.")
                }
                Section("Itinéraires favoris") {
                    if library.saved.favorites.isEmpty { Text("Aucun favori. Touche l'étoile d'un vol.").foregroundStyle(.secondary) }
                    ForEach(library.saved.favorites) { f in
                        Button { onSearch(f.query) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.query.summary).font(.subheadline.weight(.semibold))
                                if let o = f.group.cheapest {
                                    Text("Vu à \(FlightSearch.money(o.price)) le \(f.savedAt.formatted(.dateTime.day().month())). Toucher pour relancer la recherche.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions { Button("Retirer", role: .destructive) { library.removeFavorite(f) } }
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(Theme.warning) } }
            }
            .navigationTitle("Favoris et alertes").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .task { await refresh() }
        }
    }

    @ViewBuilder private func alertStatus(_ a: FlightLibrary.Alert) -> some View {
        switch states[a.id] {
        case .none: Text("État serveur : lecture…").font(.caption2).foregroundStyle(.secondary)
        case .some(.none): Text("Cette alerte n'existe plus sur le serveur.").font(.caption2).foregroundStyle(Theme.warning)
        case .some(.some(let s)):
            if s.triggered, let p = s.lastPrice { Label("Sous le seuil : \(p.total.formatted(.currency(code: p.currency)))", systemImage: "bell.fill").font(.caption).foregroundStyle(Theme.success) }
            else if let p = s.lastPrice { Text("Dernier prix vu : \(p.total.formatted(.currency(code: p.currency)))").font(.caption2).foregroundStyle(.secondary) }
            else { Text(s.lastError.map { "Dernière vérification : \($0)" } ?? "Pas encore vérifiée par le serveur.").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func refresh() async {
        alertsOn = (try? await FlightSearch.info())?.alerts.serverChecks
        for a in library.saved.alerts {
            do { states[a.id] = .some(try await FlightSearch.fetchAlert(a.ticket)) }
            catch { errorText = error.localizedDescription }
        }
        await FlightAlertsCheck.notify(library, states: states.compactMapValues { $0 })
    }

    private func unsubscribe(_ a: FlightLibrary.Alert) {
        Task {
            do { try await FlightSearch.deleteAlert(a.ticket); library.removeAlert(a) }
            catch { errorText = "Désinscription impossible : \(error.localizedDescription). L'alerte est gardée pour réessayer." }
        }
    }
}

// MARK: - Signalement des alertes declenchees

/// La verification tourne sur le serveur. Ici on lit l'etat de chaque alerte et on
/// signale une baisse UNE fois (notification locale), a l'ouverture d'Envol.
@MainActor enum FlightAlertsCheck {
    static func run(_ library: FlightLibrary) async {
        var states: [String: FlightSearch.AlertState] = [:]
        for a in library.saved.alerts {
            if let s = try? await FlightSearch.fetchAlert(a.ticket) { states[a.id] = s }
        }
        await notify(library, states: states)
    }

    static func notify(_ library: FlightLibrary, states: [String: FlightSearch.AlertState]) async {
        for (a, s) in library.newTriggers(states) {
            guard let at = s.triggeredAt, let p = s.lastPrice else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Prix en baisse : \(a.query.summary)"
            content.body = "\(p.total.formatted(.currency(code: p.currency))), sous ton seuil. Revérifie le prix avant de décider."
            let req = UNNotificationRequest(identifier: "flight-alert-\(a.id)-\(at)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(req)
            library.markNotified(a.id, triggeredAt: at)
        }
    }
}
