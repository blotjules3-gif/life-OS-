import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension ShapeStyle where Self == Color { static var learnTint: Color { AppCategory.learning.tint } }

/// Enregistrement commun: une erreur est journalisee et rendue, jamais avalee.
enum LearningSave {
    @MainActor @discardableResult
    static func commit(_ ctx: ModelContext, _ what: String) -> Bool {
        do { try ctx.save(); return true } catch {
            AppLog.data.error("\(what, privacy: .public) non sauvegarde: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    static let failure = "Enregistrement impossible. Réessaie, et redémarre l'app si le problème revient."
}

/// Bouton de rappel: demande la permission au moment ou on l'active, et montre
/// une sortie (Reglages) si elle est refusee.
struct LearningReminderToggle: View {
    let label: String
    @Binding var isOn: Bool
    @State private var denied = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Toggle(label, isOn: Binding(get: { isOn }, set: { wanted in
            guard wanted else { isOn = false; return }
            Task { @MainActor in
                let ok = await NotificationManager.shared.requestAuthorization()
                isOn = ok; denied = !ok
            }
        }))
        if denied {
            VStack(alignment: .leading, spacing: 6) {
                Text("Les notifications sont refusées: aucun rappel ne pourra s'afficher.")
                    .font(.caption).foregroundStyle(Theme.warning)
                Button("Ouvrir les réglages") {
                    if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) }
                }.font(.caption.bold())
            }
        }
    }
}

// MARK: - Anko (flashcards)

struct NotePreset {
    var front = ""
    var back = ""
    var deckName: String?
    var tags = ""
    var source = ""
    var type: NoteType = .basic
    /// Ecran simplifie de Headwave: titre, explication, source.
    var notion = false
}

struct NoteEditTarget: Identifiable {
    let id = UUID()
    var cards: [Flashcard] = []
    var preset = NotePreset()
}

struct ReviewBatch: Identifiable {
    let id = UUID()
    let cards: [Flashcard]
}

struct FlashcardsView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var cards: [Flashcard]
    @Query private var decks: [CardDeck]
    @Query(sort: \CardReview.date, order: .reverse) private var reviews: [CardReview]
    @State private var editTarget: NoteEditTarget?
    @State private var batch: ReviewBatch?
    @State private var deckPrompt: DeckPrompt?
    @State private var deckName = ""
    @State private var deckToDelete: CardDeck?
    @State private var showIO = false
    @State private var errorText: String?

    enum DeckPrompt: Identifiable {
        case create(parent: String?), rename(CardDeck)
        var id: String {
            switch self { case .create(let p): return "c" + (p ?? ""); case .rename(let d): return "r" + d.name }
        }
    }

    private var sortedDecks: [CardDeck] {
        var seen = Set<String>()
        return DeckTree.sorted(decks.map(\.name)).compactMap { n in seen.insert(n).inserted ? decks.first { $0.name == n } : nil }
    }
    private func cardsIn(_ deck: CardDeck) -> [Flashcard] {
        let ids = Set(DeckOps.subtree(deck, decks: decks).compactMap(\.uid))
        return cards.filter { $0.deckID.map(ids.contains) ?? false }
    }
    private var dueCards: [Flashcard] { CardScheduling.sessionCards(cards, now: .now) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("\(dueCards.count)").font(.system(size: 48, weight: .bold)).foregroundStyle(.learnTint)
                        Text("cartes à réviser").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }.frame(maxWidth: .infinity).card()
                    if !dueCards.isEmpty {
                        PrimaryButton(title: "Démarrer la révision", icon: "play.fill", tint: .learnTint) { batch = ReviewBatch(cards: dueCards) }
                    }
                    if let last = ReviewUndo.last(reviews: reviews, cards: cards) {
                        Button { undoLast(last.0, last.1) } label: {
                            Label("Annuler la dernière réponse", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                        }.buttonStyle(LifeOSGlassButtonStyle()).tint(.learnTint)
                    }
                    if cards.isEmpty {
                        EmptyState(icon: "rectangle.on.rectangle.angled", title: "Aucune carte",
                                   message: "Crée tes flashcards ou importe un fichier CSV. L'algorithme planifie les révisions pour ancrer durablement.",
                                   actionTitle: "Créer une carte") { editTarget = NoteEditTarget() }
                    }
                    decksSection
                    toolsSection
                }
                .padding(Theme.pad).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Flashcards").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editTarget = NoteEditTarget() } label: { Label("Nouvelle carte", systemImage: "rectangle.badge.plus") }
                    Button { deckName = ""; deckPrompt = .create(parent: nil) } label: { Label("Nouveau paquet", systemImage: "square.stack.3d.up") }
                    Button { showIO = true } label: { Label("Importer ou exporter", systemImage: "arrow.up.arrow.down") }
                } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter")
            }
        }
        .sheet(item: $editTarget) { FlashcardEditor(target: $0) }
        .sheet(isPresented: $showIO) { AnkoImportExportSheet() }
        .fullScreenCover(item: $batch) { ReviewSession(cards: $0.cards) }
        .alert(deckPromptTitle, isPresented: Binding(get: { deckPrompt != nil }, set: { if !$0 { deckPrompt = nil } }), presenting: deckPrompt) { p in
            TextField("Nom du paquet", text: $deckName)
            Button("Annuler", role: .cancel) {}
            Button("Valider") { commitDeck(p) }
        } message: { _ in Text("Utilise :: pour un sous-paquet, par exemple Langues::Anglais.") }
        .confirmationDialog("Supprimer le paquet ?", isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }), titleVisibility: .visible, presenting: deckToDelete) { d in
            let n = cardsIn(d).count
            Button("Déplacer les \(n) cartes vers \(DeckTree.defaultName)") { deleteDeck(d, keepCards: true) }
            Button("Supprimer aussi les \(n) cartes", role: .destructive) { deleteDeck(d, keepCards: false) }
            Button("Annuler", role: .cancel) {}
        } message: { d in Text("« \(d.name) » et ses sous-paquets seront supprimés.") }
        .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear(perform: migrate)
    }

    private var deckPromptTitle: String {
        switch deckPrompt {
        case .rename: return "Renommer le paquet"
        case .create(let p?): return "Sous-paquet de \(DeckTree.leaf(p))"
        default: return "Nouveau paquet"
        }
    }

    @ViewBuilder private var decksSection: some View {
        if !sortedDecks.isEmpty && !cards.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Paquets")
                ForEach(sortedDecks) { d in deckRow(d) }
            }
        }
    }

    private func deckRow(_ d: CardDeck) -> some View {
        let inDeck = cardsIn(d)
        let due = CardScheduling.sessionCards(inDeck, now: .now)
        let depth = DeckTree.depth(d.name)
        return HStack(spacing: 10) {
            NavigationLink { CardBrowserView(deckID: d.uid) } label: {
                HStack(spacing: 10) {
                    Image(systemName: depth == 0 ? "square.stack.fill" : "arrow.turn.down.right").foregroundStyle(.learnTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DeckTree.leaf(d.name)).foregroundStyle(Theme.textPrimary)
                        Text("\(inDeck.count) cartes · \(due.count) à réviser").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !due.isEmpty {
                Button { batch = ReviewBatch(cards: due) } label: { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.learnTint) }
                    .buttonStyle(.plain).accessibilityLabel("Réviser \(d.name)")
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .card(padding: 12)
        .contextMenu {
            Button { deckName = ""; deckPrompt = .create(parent: d.name) } label: { Label("Nouveau sous-paquet", systemImage: "plus") }
            Button { editTarget = NoteEditTarget(preset: NotePreset(deckName: d.name)) } label: { Label("Nouvelle carte ici", systemImage: "rectangle.badge.plus") }
            if d.name != DeckTree.defaultName {
                Button { deckName = d.name; deckPrompt = .rename(d) } label: { Label("Renommer", systemImage: "pencil") }
                Button(role: .destructive) { deckToDelete = d } label: { Label("Supprimer", systemImage: "trash") }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cards.isEmpty {
                NavigationLink { CardBrowserView() } label: { toolRow("magnifyingglass", "Parcourir et rechercher", "\(cards.count) cartes, étiquettes, suspendues") }.buttonStyle(.plain)
                NavigationLink { CardStatsView() } label: { toolRow("chart.bar.fill", "Statistiques", "Révisions par jour, taux de réussite") }.buttonStyle(.plain)
            }
            Button { showIO = true } label: { toolRow("arrow.up.arrow.down", "Importer ou exporter", "CSV et texte tabulé (export Anki en texte brut)") }.buttonStyle(.plain)
        }
    }

    private func toolRow(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(.learnTint).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Theme.textPrimary)
                Text(sub).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }.contentShape(Rectangle()).card(padding: 12)
    }

    private func migrate() {
        if DeckMigration.run(cards: cards, decks: decks, in: ctx) > 0 { LearningSave.commit(ctx, "migration paquets") }
    }

    private func undoLast(_ r: CardReview, _ c: Flashcard) {
        ReviewUndo.undo(r, on: c)
        ctx.delete(r)
        if !LearningSave.commit(ctx, "annulation revision") { errorText = LearningSave.failure }
    }

    private func commitDeck(_ p: DeckPrompt) {
        var all = decks
        let error: DeckError?
        switch p {
        case .create(let parent):
            let full = parent.map { $0 + DeckTree.separator + deckName } ?? deckName
            if case .failure(let e) = DeckOps.create(full, decks: &all, in: ctx) { error = e } else { error = nil }
        case .rename(let d):
            error = DeckOps.rename(d, to: deckName, decks: decks, cards: cards)
        }
        if let error { errorText = error.message; return }
        if !LearningSave.commit(ctx, "paquet") { errorText = LearningSave.failure }
    }

    private func deleteDeck(_ d: CardDeck, keepCards: Bool) {
        let target = keepCards ? decks.first { $0.name == DeckTree.defaultName } : nil
        if let e = DeckOps.delete(d, decks: decks, cards: cards, moveTo: target, in: ctx) { errorText = e.message; return }
        if !LearningSave.commit(ctx, "suppression paquet") { errorText = LearningSave.failure }
    }
}

/// Creation et modification d'une note (une ou plusieurs cartes).
struct FlashcardEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var decks: [CardDeck]
    let target: NoteEditTarget
    @State private var type: NoteType = .basic
    @State private var front = ""
    @State private var back = ""
    @State private var tags = ""
    @State private var source = ""
    @State private var deckName = DeckTree.defaultName
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var errorText: String?

    private var isEditing: Bool { !target.cards.isEmpty }
    private var notion: Bool { target.preset.notion }
    private var specs: [CardSpec] { NoteFactory.specs(type: notion ? .basic : type, front: front, back: back) }
    private var deckNames: [String] { DeckTree.sorted(Array(Set(decks.map(\.name) + [deckName, DeckTree.defaultName]))) }

    var body: some View {
        NavigationStack {
            Form {
                if !notion {
                    Section {
                        Picker("Type", selection: $type) { ForEach(NoteType.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                        Picker("Paquet", selection: $deckName) { ForEach(deckNames, id: \.self) { Text($0).tag($0) } }
                    }
                }
                Section(notion ? "Notion" : (type == .cloze ? "Texte" : "Recto")) {
                    TextField(notion ? "Titre (ex: Loi de Parkinson)" : (type == .cloze ? "La capitale du Portugal est {{c1::Lisbonne}}." : "Question"), text: $front, axis: .vertical).lineLimit(2...8)
                    if type == .cloze && !notion {
                        Button("Ajouter le trou c\((Cloze.indices(in: front).max() ?? 0) + 1)") {
                            front += (front.isEmpty || front.hasSuffix(" ") ? "" : " ") + "{{c\((Cloze.indices(in: front).max() ?? 0) + 1)::réponse}}"
                        }.font(.caption)
                        Text("Chaque trou {{c1::…}} devient une carte. Un indice s'écrit {{c1::réponse::indice}}.").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Section(notion ? "Explication" : (type == .cloze ? "En plus (facultatif)" : "Verso")) {
                    TextField(notion ? "Ce que tu en retiens, dans tes mots" : "Réponse", text: $back, axis: .vertical).lineLimit(2...10)
                }
                Section(notion ? "Source" : "Étiquettes et source") {
                    if !notion { TextField("Étiquettes séparées par des espaces", text: $tags).textInputAutocapitalization(.never) }
                    TextField("Source (livre, article, lien), facultatif", text: $source)
                }
                Section {
                    Text(summary).font(.caption).foregroundStyle(specs.isEmpty ? Theme.warning : Theme.textSecondary)
                }
                if isEditing {
                    Section { Button(notion ? "Supprimer la notion" : "Supprimer la note", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(isEditing ? (notion ? "Modifier la notion" : "Modifier la note") : (notion ? "Nouvelle notion" : "Nouvelle carte"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isEditing ? "Enregistrer" : "Ajouter") { save() }.disabled(specs.isEmpty) }
            }
            .confirmationDialog("Supprimer ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(target.cards.count > 1 ? "Supprimer les \(target.cards.count) cartes" : "Supprimer", role: .destructive) { deleteNote() }
            } message: { Text("La note et toutes ses cartes seront supprimées.") }
            .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
            .onAppear(perform: load)
        }
    }

    private var summary: String {
        if front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return notion ? "Donne un titre à la notion." : "Écris le recto pour créer la carte." }
        if notion { return "Elle reviendra en révision au bon moment." }
        switch (type, specs.count) {
        case (.cloze, 0): return "Ajoute au moins un trou {{c1::…}}."
        case (.basicReversed, 1): return "Écris aussi le verso pour créer la carte inversée."
        case (_, 1): return "1 carte sera créée."
        default: return "\(specs.count) cartes seront créées."
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let c = target.cards.first {
            front = c.front; back = c.back; tags = c.tags; source = c.source; deckName = c.deck
            type = NoteFactory.type(of: target.cards.map(\.kind))
        } else {
            let p = target.preset
            front = p.front; back = p.back; tags = p.tags; source = p.source; type = p.type
            deckName = p.deckName.map(DeckTree.normalize) ?? DeckTree.defaultName
            if deckName.isEmpty { deckName = DeckTree.defaultName }
        }
    }

    private func save() {
        var all = decks
        let deck = DeckOps.ensure(notion ? DeckTree.notionsName : deckName, decks: &all, in: ctx)
        let finalTags = notion ? CardTags.normalize(tags + " " + NotionStore.tag) : tags
        NoteStore.save(existing: target.cards, type: notion ? .basic : type, front: front, back: back,
                       deck: deck, tags: finalTags, source: source, in: ctx)
        if LearningSave.commit(ctx, "note flashcard") { dismiss() } else { errorText = LearningSave.failure }
    }

    private func deleteNote() {
        target.cards.forEach { ctx.delete($0) }
        if LearningSave.commit(ctx, "suppression note") { dismiss() } else { errorText = LearningSave.failure }
    }
}

/// Liste de toutes les cartes: recherche, etiquettes, suspension, modification, suppression.
struct CardBrowserView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Flashcard.createdAt, order: .reverse) private var cards: [Flashcard]
    @Query private var decks: [CardDeck]
    @State private var query = ""
    @State private var deckFilter: UUID?
    @State private var editTarget: NoteEditTarget?
    @State private var toDelete: Flashcard?
    @State private var errorText: String?

    init(deckID: UUID? = nil) { _deckFilter = State(initialValue: deckID) }

    private var filterDeck: CardDeck? { decks.first { $0.uid != nil && $0.uid == deckFilter } }
    private var filtered: [Flashcard] {
        let ids = filterDeck.map { Set(DeckOps.subtree($0, decks: decks).compactMap(\.uid)) }
        return cards.filter { c in
            (ids == nil || (c.deckID.map { ids!.contains($0) } ?? false)) && CardSearch.matches(c, query: query)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                Text(cards.isEmpty ? "Aucune carte pour l'instant." : "Aucune carte ne correspond.").foregroundStyle(Theme.textSecondary)
            }
            ForEach(filtered) { c in
                row(c)
                    .contentShape(Rectangle())
                    .onTapGesture { editTarget = NoteEditTarget(cards: NoteStore.siblings(of: c, in: cards)) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { toDelete = c } label: { Label("Supprimer", systemImage: "trash") }
                        Button { c.suspended.toggle(); persist() } label: { Label(c.suspended ? "Réactiver" : "Suspendre", systemImage: c.suspended ? "play" : "pause") }.tint(.orange)
                    }
                    .swipeActions(edge: .leading) {
                        if CardScheduling.isBuried(c, now: .now) {
                            Button { c.buriedUntil = nil; persist() } label: { Label("Déterrer", systemImage: "arrow.up") }.tint(.blue)
                        } else {
                            Button { CardScheduling.bury(c, now: .now); persist() } label: { Label("Enterrer", systemImage: "moon.zzz") }.tint(.indigo)
                        }
                    }
            }
        }
        .searchable(text: $query, prompt: "Rechercher, tag:mot, is:suspendue")
        .navigationTitle(filterDeck.map { DeckTree.leaf($0.name) } ?? "Toutes les cartes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Paquet", selection: $deckFilter) {
                        Text("Tous les paquets").tag(UUID?.none)
                        ForEach(DeckTree.sorted(decks.map(\.name)), id: \.self) { n in
                            Text(n).tag(decks.first { $0.name == n }?.uid)
                        }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }.accessibilityLabel("Filtrer par paquet")
            }
        }
        .sheet(item: $editTarget) { FlashcardEditor(target: $0) }
        .confirmationDialog("Supprimer la note ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible, presenting: toDelete) { c in
            let sib = NoteStore.siblings(of: c, in: cards)
            Button(sib.count > 1 ? "Supprimer les \(sib.count) cartes de la note" : "Supprimer la carte", role: .destructive) {
                sib.forEach { ctx.delete($0) }; persist()
            }
        }
        .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func row(_ c: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(CardFace.question(c)).lineLimit(2).foregroundStyle(c.suspended ? Theme.textSecondary : Theme.textPrimary)
            HStack(spacing: 6) {
                Text(c.deck)
                if let k = CardFace.kindLabel(c) { Text("· \(k)") }
                if !c.tags.isEmpty { Text("· " + CardTags.list(c.tags).map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
            }.font(.caption).foregroundStyle(Theme.textSecondary)
            Text(status(c)).font(.caption2).foregroundStyle(c.suspended ? Theme.warning : Theme.textSecondary)
        }.padding(.vertical, 2)
    }

    private func status(_ c: Flashcard) -> String {
        if c.suspended { return "Suspendue" }
        if CardScheduling.isBuried(c, now: .now) { return "Enterrée jusqu'à demain" }
        if c.due <= .now { return "À réviser" }
        return "Prochaine révision le " + c.due.formatted(.dateTime.day().month(.abbreviated))
    }

    private func persist() { if !LearningSave.commit(ctx, "carte") { errorText = LearningSave.failure } }
}

struct ReviewSession: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    let cards: [Flashcard]
    @State private var queue: ReviewQueue
    @State private var flipped = false
    @State private var actions: [SessionAction] = []
    @State private var saveFailed = false

    enum SessionAction { case graded(CardReview), buried(Flashcard, Date?), suspended(Flashcard) }

    init(cards: [Flashcard]) {
        self.cards = cards
        _queue = State(initialValue: ReviewQueue(count: cards.count))
    }

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 20) {
                topBar
                if let i = queue.current, cards.indices.contains(i) {
                    cardView(cards[i])
                } else {
                    doneView
                }
            }.padding().frame(maxWidth: 700).frame(maxWidth: .infinity)
        }
        .alert("Action impossible", isPresented: $saveFailed) { Button("OK", role: .cancel) {} } message: { Text(LearningSave.failure) }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Text("\(queue.answered) faites · \(queue.remaining) restantes").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { undo() } label: { Image(systemName: "arrow.uturn.backward.circle") }
                .disabled(!queue.canUndo).accessibilityLabel("Annuler la dernière réponse")
            if queue.current != nil {
                Menu {
                    Button { bury() } label: { Label("Enterrer jusqu'à demain", systemImage: "moon.zzz") }
                    Button { suspend() } label: { Label("Suspendre la carte", systemImage: "pause.circle") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Plus d'actions")
            }
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary) }.accessibilityLabel("Fermer")
        }.font(.title3).foregroundStyle(.learnTint)
    }

    private func cardView(_ card: Flashcard) -> some View {
        VStack(spacing: 20) {
            Spacer()
            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text(flipped ? "RÉPONSE" : "QUESTION")
                    if let k = CardFace.kindLabel(card) { Text("· \(k.uppercased())") }
                }.font(.caption.bold()).foregroundStyle(.learnTint)
                if flipped && card.kind != CardKind.cloze {
                    Text(CardFace.question(card)).font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                Text(flipped ? CardFace.answer(card) : CardFace.question(card))
                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
                if flipped && !card.source.isEmpty {
                    Text("Source: \(card.source)").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240).card()
            .onTapGesture { withAnimation { flipped.toggle() } }
            Spacer()
            if !flipped {
                PrimaryButton(title: "Voir la réponse", icon: "eye.fill", tint: .learnTint) { withAnimation { flipped = true } }
            } else {
                HStack(spacing: 10) {
                    gradeButton("À revoir", Theme.danger, 2)
                    gradeButton("Correct", Theme.warning, 4)
                    gradeButton("Facile", Theme.success, 5)
                }
            }
        }
    }

    private var doneView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 60)).foregroundStyle(Theme.success)
            Text("Révision terminée").font(.title2.bold()).foregroundStyle(Theme.textPrimary)
            Text("\(actions.count) réponses").font(.subheadline).foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Fermer", tint: .learnTint) { dismiss() }.padding(.horizontal, 40)
            Spacer()
        }
    }

    private func gradeButton(_ label: String, _ color: Color, _ q: Int) -> some View {
        Button { grade(q) } label: { Text(label).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(.vertical, 14).background(color, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.white) }
    }

    private func grade(_ q: Int) {
        guard let i = queue.current else { return }
        let c = cards[i]
        let before = CardScheduling.answer(c, quality: q)
        let r = CardReview(cardUID: c.uid, quality: q, before: before)
        ctx.insert(r)
        queue.answer(quality: q)
        actions.append(.graded(r))
        flipped = false
        persist()
    }

    private func bury() {
        guard let i = queue.current else { return }
        let c = cards[i]
        actions.append(.buried(c, c.buriedUntil))
        CardScheduling.bury(c, now: .now)
        queue.skip(); flipped = false; persist()
    }

    private func suspend() {
        guard let i = queue.current else { return }
        let c = cards[i]
        actions.append(.suspended(c))
        c.suspended = true
        queue.skip(); flipped = false; persist()
    }

    private func undo() {
        guard let a = actions.popLast(), let i = queue.undo() else { return }
        switch a {
        case .graded(let r): ReviewUndo.undo(r, on: cards[i]); ctx.delete(r)
        case .buried(let c, let prev): c.buriedUntil = prev
        case .suspended(let c): c.suspended = false
        }
        flipped = false
        persist()
    }

    private func persist() { if !LearningSave.commit(ctx, "revision") { saveFailed = true } }
}

struct CardStatsView: View {
    @Query private var cards: [Flashcard]
    @Query private var reviews: [CardReview]

    var body: some View {
        let s = CardStats.summary(cards: cards, reviews: reviews)
        let maxCount = max(1, s.reviewsPerDay.map(\.count).max() ?? 1)
        return ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        tile("\(s.dueToday)", "À réviser aujourd'hui")
                        tile("\(s.total)", "Cartes")
                        tile("\(s.suspended)", "Suspendues")
                        tile(s.retention.map { "\(Int(($0 * 100).rounded())) %" } ?? "Pas encore", "Réussite sur 30 jours")
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Révisions par jour", subtitle: "14 derniers jours")
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(s.reviewsPerDay, id: \.day) { d in
                                VStack(spacing: 4) {
                                    Text(d.count > 0 ? "\(d.count)" : "").font(.caption2).foregroundStyle(Theme.textSecondary)
                                    RoundedRectangle(cornerRadius: 3).fill(Color.learnTint.opacity(d.count > 0 ? 1 : 0.25))
                                        .frame(height: max(3, 110 * CGFloat(d.count) / CGFloat(maxCount)))
                                    Text(d.day.formatted(.dateTime.day())).font(.caption2).foregroundStyle(Theme.textSecondary)
                                }.frame(maxWidth: .infinity)
                            }
                        }.frame(height: 150)
                    }.card()
                    Text("Réussite = part des réponses Correct ou Facile parmi tes \(s.reviews30) réponses des 30 derniers jours.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(Theme.pad).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Statistiques").navigationBarTitleDisplayMode(.inline)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(.learnTint).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).card(padding: 12)
    }
}

struct AnkoImportExportSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [Flashcard]
    @Query private var decks: [CardDeck]
    @State private var picking = false
    @State private var result: String?
    @State private var resultIsError = false
    @State private var exportURL: URL?
    @State private var exportCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Formats pris en charge") {
                    Text("CSV (virgule ou point-virgule) et texte tabulé, y compris l'export Anki « Notes en texte brut ». Colonnes: recto, verso, paquet, étiquettes, type (basique, inversee, trous).")
                        .font(.footnote)
                    Label("Le paquet Anki .apkg n'est pas pris en charge, ni les images et les sons.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(Theme.warning)
                }
                Section("Importer") {
                    Button { picking = true } label: { Label("Choisir un fichier", systemImage: "doc.badge.plus") }
                    if let result {
                        Text(result).font(.footnote).foregroundStyle(resultIsError ? Theme.danger : Theme.success)
                    }
                    Text("Les notes déjà présentes (même recto, verso et paquet) sont ignorées.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Section("Exporter") {
                    if let exportURL, exportCount > 0 {
                        ShareLink(item: exportURL) { Label("Exporter \(exportCount) notes en CSV", systemImage: "square.and.arrow.up") }
                    } else {
                        Text("Aucune carte à exporter.").foregroundStyle(Theme.textSecondary)
                    }
                    Text("Une ligne par note: la carte inversée et les trous se recréent à l'import. L'historique des révisions n'est pas exporté.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Importer ou exporter").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { r in
                switch r {
                case .success(let url): importFile(url)
                case .failure(let e): show("Fichier non ouvert: \(e.localizedDescription)", error: true)
                }
            }
            .onAppear(perform: prepareExport)
        }
    }

    private func show(_ text: String, error: Bool) { result = text; resultIsError = error }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { show("Lecture du fichier impossible (accès refusé ou fichier déplacé).", error: true); return }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            show("Ce fichier n'est pas du texte lisible.", error: true); return
        }
        let parsed = FlashcardCSV.parse(text)
        guard !parsed.notes.isEmpty else { show("Aucune carte trouvée dans ce fichier.", error: true); return }
        DeckMigration.run(cards: cards, decks: decks, in: ctx)
        let r = FlashcardCSV.apply(parsed.notes, cards: cards, decks: decks, in: ctx)
        guard LearningSave.commit(ctx, "import flashcards") else { show(LearningSave.failure, error: true); return }
        var parts = ["\(r.added) notes ajoutées"]
        if r.duplicates > 0 { parts.append("\(r.duplicates) déjà présentes") }
        if parsed.skipped > 0 { parts.append("\(parsed.skipped) lignes ignorées (recto vide ou sans trou)") }
        show(parts.joined(separator: ", ") + ".", error: false)
        prepareExport()
    }

    private func prepareExport() {
        let notes = FlashcardCSV.notes(from: cards)
        exportCount = notes.count
        guard !notes.isEmpty else { exportURL = nil; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("LifeOS-flashcards.csv")
        do { try FlashcardCSV.export(notes).write(to: url, atomically: true, encoding: .utf8); exportURL = url }
        catch { exportURL = nil; show("Export impossible: \(error.localizedDescription)", error: true) }
    }
}

// MARK: - Micro-learning (Headwave)

struct MicroLearningView: View {
    @Environment(\.modelContext) private var ctx
    @Query private var cards: [Flashcard]
    @Query private var decks: [CardDeck]
    @ObservedObject private var speech = CoachSpeech.shared
    @State private var editTarget: NoteEditTarget?
    @State private var batch: ReviewBatch?
    @State private var query = ""
    @State private var toDelete: Flashcard?
    @State private var errorText: String?

    private let facts = [
        ("Effet de simple exposition", "Plus on est exposé à quelque chose, plus on l'apprécie. Utile en marketing… et en networking."),
        ("Loi de Parkinson", "Le travail s'étale pour occuper le temps disponible. Donne-toi des deadlines courtes."),
        ("Règle des 2 minutes", "Si une tâche prend moins de 2 min, fais-la tout de suite (GTD, David Allen)."),
        ("Intérêts composés", "Le plus puissant levier financier : commencer tôt bat épargner beaucoup."),
        ("Biais de confirmation", "On cherche ce qui confirme nos croyances. Cherche activement le contre-argument."),
        ("Pareto 80/20", "80% des résultats viennent de 20% des actions. Identifie ces 20%."),
        ("Pic-fin", "On juge une expérience sur son pic émotionnel et sa fin, pas sa moyenne."),
        ("Dette technique", "Les raccourcis d'aujourd'hui sont les ralentissements de demain. Refactore tôt.")
    ]
    private var todayFact: (String, String) { facts[(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0) % facts.count] }
    private var notions: [Flashcard] { NotionStore.notions(cards) }
    private var shown: [Flashcard] { notions.filter { CardSearch.matches($0, query: query) } }
    private var due: [Flashcard] { CardScheduling.sessionCards(notions, now: .now) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    todayCard
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Mes notions", subtitle: "\(notions.count) notées · \(due.count) à revoir")
                        if !due.isEmpty {
                            PrimaryButton(title: "Revoir mes notions (\(due.count))", icon: "arrow.triangle.2.circlepath", tint: .learnTint) { batch = ReviewBatch(cards: due) }
                        }
                        if notions.isEmpty {
                            EmptyState(icon: "lightbulb", title: "Aucune notion",
                                       message: "Note une idée apprise (livre, article, podcast) avec sa source. Elle revient au bon moment pour s'ancrer.",
                                       actionTitle: "Ajouter une notion") { editTarget = newNotion() }
                        } else if shown.isEmpty {
                            Text("Aucune notion ne correspond.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(shown) { n in notionRow(n) }
                    }
                    Text("Pas de catalogue de contenus pour l'instant: Headwave fait revenir les notions que tu notes, avec la même répétition espacée que tes flashcards.")
                        .font(.caption).foregroundStyle(Theme.textSecondary).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Theme.pad).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Micro-learning").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Rechercher une notion")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editTarget = newNotion() } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter une notion")
            }
        }
        .sheet(item: $editTarget) { FlashcardEditor(target: $0) }
        .fullScreenCover(item: $batch) { ReviewSession(cards: $0.cards) }
        .confirmationDialog("Supprimer la notion ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible, presenting: toDelete) { n in
            Button("Supprimer", role: .destructive) { NoteStore.siblings(of: n, in: cards).forEach { ctx.delete($0) }; persist() }
        }
        .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onDisappear { speech.stop() }
    }

    private func newNotion(front: String = "", back: String = "") -> NoteEditTarget {
        NoteEditTarget(preset: NotePreset(front: front, back: back, deckName: DeckTree.notionsName, tags: NotionStore.tag, notion: true))
    }

    private var todayCard: some View {
        let saved = NotionStore.exists(title: todayFact.0, in: cards)
        return VStack(spacing: 12) {
            Label("Pépite du jour", systemImage: "lightbulb.max.fill").font(.caption.bold()).foregroundStyle(.learnTint)
            Text(todayFact.0).font(.title3.bold()).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.center)
            Text(todayFact.1).font(.body).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            // Peu de fiches qui tournent en boucle: on ne promet pas du neuf chaque jour.
            Text("Une notion par jour, parmi \(facts.count) qui reviennent en boucle.").font(.caption).foregroundStyle(Theme.textSecondary)
            Button {
                var all = decks
                let deck = DeckOps.ensure(DeckTree.notionsName, decks: &all, in: ctx)
                NoteStore.save(existing: [], type: .basic, front: todayFact.0, back: todayFact.1, deck: deck, tags: NotionStore.tag, source: "", in: ctx)
                persist()
            } label: {
                Label(saved ? "Déjà dans tes notions" : "Garder dans mes notions", systemImage: saved ? "checkmark" : "plus")
            }
            .buttonStyle(LifeOSGlassButtonStyle()).tint(.learnTint).disabled(saved)
        }.frame(maxWidth: .infinity).card()
    }

    private func notionRow(_ n: Flashcard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(n.front).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    speech.toggle(text: n.front + ". " + n.back, id: n.uid ?? UUID())
                } label: {
                    Image(systemName: speech.speakingID != nil && speech.speakingID == n.uid ? "stop.circle.fill" : "speaker.wave.2.fill").foregroundStyle(.learnTint)
                }.buttonStyle(.plain).accessibilityLabel("Écouter")
                Menu {
                    Button { editTarget = NoteEditTarget(cards: NoteStore.siblings(of: n, in: cards), preset: NotePreset(notion: true)) } label: { Label("Modifier", systemImage: "pencil") }
                    Button(role: .destructive) { toDelete = n } label: { Label("Supprimer", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Theme.textSecondary) }.accessibilityLabel("Actions")
            }
            if !n.back.isEmpty { Text(n.back).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9)) }
            HStack {
                if !n.source.isEmpty { Label(n.source, systemImage: "book.closed").lineLimit(1) }
                Spacer()
                Text(n.due <= .now ? "À revoir" : "Revient le " + n.due.formatted(.dateTime.day().month(.abbreviated)))
            }.font(.caption).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    private func persist() { if !LearningSave.commit(ctx, "notion") { errorText = LearningSave.failure } }
}

// MARK: - Résumés de livres (Blinklist)

struct BookSummariesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \BookSummary.date, order: .reverse) private var books: [BookSummary]
    @Query private var passages: [BookPassage]
    @State private var showAdd = false
    @State private var showAI = false
    @State private var aiReady = false
    @State private var query = ""
    @State private var collection: String?
    @State private var toDelete: BookSummary?

    private var collections: [String] { BookCollections.all(books) }
    private var filtered: [BookSummary] {
        books.filter { b in
            (collection.map { c in BookCollections.list(b.collections).contains { $0.caseInsensitiveCompare(c) == .orderedSame } } ?? true)
                && BookOps.matches(b, passages: passages, query: query)
        }
    }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if !collections.isEmpty { collectionChips }
                    if books.isEmpty {
                        EmptyState(icon: "books.vertical", title: "Aucun résumé", message: "Note les idées clés, les chapitres et les passages de tes lectures pour les retenir.")
                    } else if filtered.isEmpty {
                        Text("Aucun livre ne correspond.").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(filtered) { b in
                        NavigationLink { BookDetailView(book: b) } label: { bookRow(b) }
                            .buttonStyle(.plain)
                            .contextMenu { Button(role: .destructive) { toDelete = b } label: { Label("Supprimer", systemImage: "trash") } }
                    }
                    if aiReady {
                        Button { showAI = true } label: {
                            Label("Résumer un livre avec ton coach", systemImage: "infinity")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(LifeOSGlassButtonStyle(prominent: true)).tint(.learnTint)
                    } else {
                        // Pas de cle: on le dit une fois, sans promettre une
                        // fonctionnalite qui echouerait au premier appui.
                        Text("Ajoute une clé dans Profil › Coach pour générer un résumé automatiquement.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(Theme.pad).frame(maxWidth: 760).frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Résumés de livres").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Titre, auteur, idée, passage")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("Ajouter") } }
        .sheet(isPresented: $showAdd) { BookEditor() }
        .sheet(isPresented: $showAI) { BookAISheet() }
        .confirmationDialog("Supprimer ce livre ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible, presenting: toDelete) { b in
            Button("Supprimer le livre et ses notes", role: .destructive) { BookOps.delete(b, passages: passages, in: ctx); LearningSave.commit(ctx, "suppression livre") }
        }
        .task { aiReady = await MainActor.run { AIText.isConfigured } }
        .onAppear { if BookOps.migrate(books) > 0 { LearningSave.commit(ctx, "migration livres") } }
    }

    private var collectionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Tous", selected: collection == nil) { collection = nil }
                ForEach(collections, id: \.self) { c in chip(c, selected: collection == c) { collection = collection == c ? nil : c } }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.caption.bold()).padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? Color.learnTint.opacity(0.3) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(Color.learnTint.opacity(0.5)))
                .foregroundStyle(Theme.textPrimary)
        }.buttonStyle(.plain)
    }

    private func bookRow(_ b: BookSummary) -> some View {
        let mine = BookOps.passages(of: b, in: passages)
        let chapters = mine.filter { $0.kind == BookPassageKind.chapter.rawValue }.count
        let highlights = mine.filter { $0.kind == BookPassageKind.highlight.rawValue }.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(b.title).font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(String(repeating: "★", count: max(0, b.rating))).foregroundStyle(.learnTint).font(.caption)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if !b.author.isEmpty { Text(b.author).font(.caption).foregroundStyle(Theme.textSecondary) }
            if BookSummaryOrigin.isAI(b.keyIdeas) { Label("Synthèse du coach, non vérifiée", systemImage: "infinity").font(.caption2).foregroundStyle(Theme.warning) }
            if !b.keyIdeas.isEmpty { Text(BookSummaryOrigin.body(b.keyIdeas)).font(.subheadline).foregroundStyle(Theme.textPrimary.opacity(0.9)).lineLimit(4) }
            if chapters + highlights > 0 || !b.collections.isEmpty {
                HStack(spacing: 6) {
                    if chapters > 0 { Text("\(chapters) chapitres") }
                    if highlights > 0 { Text("\(highlights) surlignages") }
                    if !b.collections.isEmpty { Text(BookCollections.list(b.collections).joined(separator: ", ")).lineLimit(1) }
                }.font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

struct BookPassageTarget: Identifiable {
    let id = UUID()
    var passage: BookPassage?
    var kind: BookPassageKind
}

struct BookDetailView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let book: BookSummary
    @Query private var allPassages: [BookPassage]
    @State private var showEdit = false
    @State private var passageTarget: BookPassageTarget?
    @State private var cardTarget: NoteEditTarget?
    @State private var confirmDelete = false

    private var ordered: [BookPassage] { BookOps.passages(of: book, in: allPassages) }

    var body: some View {
        let outline = BookOps.outline(ordered)
        let chapters = ordered.filter { $0.kind == BookPassageKind.chapter.rawValue }
        return ZStack {
            Theme.background
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header
                        if !book.keyIdeas.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionHeader(title: "Idées clés")
                                Text(BookSummaryOrigin.body(book.keyIdeas)).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                        if !chapters.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: "Sommaire")
                                ForEach(chapters) { ch in
                                    Button { withAnimation { proxy.scrollTo(ch.uid, anchor: .top) } } label: {
                                        Label(ch.text, systemImage: "list.number").font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    }.buttonStyle(.plain)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).card()
                        }
                        ForEach(Array(outline.enumerated()), id: \.offset) { _, section in
                            if let ch = section.chapter {
                                passageRow(ch).id(ch.uid)
                            }
                            ForEach(section.items) { p in passageRow(p) }
                        }
                        HStack(spacing: 8) {
                            ForEach(BookPassageKind.allCases) { k in
                                Button { passageTarget = BookPassageTarget(kind: k) } label: {
                                    Label(k.label, systemImage: k.icon).font(.caption.bold()).frame(maxWidth: .infinity)
                                }.buttonStyle(LifeOSGlassButtonStyle()).tint(.learnTint)
                            }
                        }
                    }.padding(Theme.pad).frame(maxWidth: 760).frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(book.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showEdit = true } label: { Label("Modifier le livre", systemImage: "pencil") }
                    ForEach(BookPassageKind.allCases) { k in
                        Button { passageTarget = BookPassageTarget(kind: k) } label: { Label("Ajouter: \(k.label.lowercased())", systemImage: k.icon) }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Supprimer le livre", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Actions")
            }
        }
        .sheet(isPresented: $showEdit) { BookEditor(book: book) }
        .sheet(item: $passageTarget) { BookPassageEditor(book: book, target: $0) }
        .sheet(item: $cardTarget) { FlashcardEditor(target: $0) }
        .confirmationDialog("Supprimer ce livre ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer le livre et ses notes", role: .destructive) {
                BookOps.delete(book, passages: allPassages, in: ctx)
                if LearningSave.commit(ctx, "suppression livre") { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title).font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            if !book.author.isEmpty { Text(book.author).font(.subheadline).foregroundStyle(Theme.textSecondary) }
            if book.rating > 0 { Text(String(repeating: "★", count: book.rating)).foregroundStyle(.learnTint) }
            if BookSummaryOrigin.isAI(book.keyIdeas) { Label("Synthèse du coach, non vérifiée", systemImage: "infinity").font(.caption).foregroundStyle(Theme.warning) }
            if !book.collections.isEmpty {
                Text(BookCollections.list(book.collections).joined(separator: " · ")).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }

    @ViewBuilder private func passageRow(_ p: BookPassage) -> some View {
        let kind = BookPassageKind(rawValue: p.kind) ?? .idea
        Group {
            if kind == .chapter {
                Text(p.text).font(.headline).foregroundStyle(Theme.textPrimary).padding(.top, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label(kind.label + (p.page.isEmpty ? "" : " · p. \(p.page)"), systemImage: kind.icon).font(.caption.bold()).foregroundStyle(.learnTint)
                    Text(p.text).font(kind == .highlight ? .subheadline.italic() : .subheadline).foregroundStyle(Theme.textPrimary)
                }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 12)
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { passageTarget = BookPassageTarget(passage: p, kind: kind) } label: { Label("Modifier", systemImage: "pencil") }
            Button { BookOps.move(p, by: -1, in: ordered); LearningSave.commit(ctx, "ordre passage") } label: { Label("Monter", systemImage: "arrow.up") }
            Button { BookOps.move(p, by: 1, in: ordered); LearningSave.commit(ctx, "ordre passage") } label: { Label("Descendre", systemImage: "arrow.down") }
            if kind != .chapter {
                Button {
                    let src = [book.title, book.author].filter { !$0.isEmpty }.joined(separator: ", ") + (p.page.isEmpty ? "" : ", p. \(p.page)")
                    cardTarget = NoteEditTarget(preset: NotePreset(front: kind == .highlight ? "Passage de « \(book.title) »" : "Idée clé de « \(book.title) »",
                                                                   back: p.text, deckName: "Livres" + DeckTree.separator + book.title, tags: "livre", source: src))
                } label: { Label("Créer une flashcard", systemImage: "rectangle.on.rectangle.angled") }
            }
            Button(role: .destructive) { ctx.delete(p); LearningSave.commit(ctx, "suppression passage") } label: { Label("Supprimer", systemImage: "trash") }
        }
    }
}

struct BookPassageEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let book: BookSummary
    let target: BookPassageTarget
    @Query private var allPassages: [BookPassage]
    @State private var kind: BookPassageKind = .idea
    @State private var text = ""
    @State private var page = ""
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $kind) { ForEach(BookPassageKind.allCases) { Text($0.label).tag($0) } }.pickerStyle(.segmented)
                Section(kind == .chapter ? "Titre du chapitre" : (kind == .idea ? "L'idée, dans tes mots" : "Le passage que tu surlignes")) {
                    TextField(kind == .chapter ? "Ex: Chapitre 3" : "Écris ici", text: $text, axis: .vertical).lineLimit(kind == .chapter ? 1...3 : 3...12)
                }
                if kind == .highlight { TextField("Page (facultatif)", text: $page).keyboardType(.numbersAndPunctuation) }
                if failed { Text(LearningSave.failure).font(.caption).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(target.passage == nil ? "Ajouter" : "Modifier").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true; kind = target.kind
                if let p = target.passage { text = p.text; page = p.page }
            }
        }
    }

    private func save() {
        if book.uid == nil { book.uid = UUID() }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pg = kind == .highlight ? page.trimmingCharacters(in: .whitespaces) : ""
        if let p = target.passage {
            p.text = t; p.kind = kind.rawValue; p.page = pg
        } else {
            let next = (BookOps.passages(of: book, in: allPassages).map(\.sortIndex).max() ?? -1) + 1
            ctx.insert(BookPassage(bookUID: book.uid, kind: kind.rawValue, text: t, page: pg, sortIndex: next))
        }
        book.updatedAt = .now
        if LearningSave.commit(ctx, "passage livre") { dismiss() } else { failed = true }
    }
}

/// Genere les idees cles d'un livre a partir de son titre.
///
/// Le modele ecrit sa PROPRE synthese: on lui interdit explicitement de citer
/// le texte du livre. Un resume est une oeuvre nouvelle, un extrait recopie
/// n'en est pas une.
struct BookAISheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var author = ""
    @State private var ideas = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titre du livre", text: $title)
                    TextField("Auteur (optionnel)", text: $author)
                }
                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack {
                            if busy { ProgressView().controlSize(.small) }
                            Text(busy ? "Rédaction…" : "Générer les idées clés")
                        }
                    }
                    .disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning).font(.footnote) }
                }
                if !ideas.isEmpty {
                    Section("Idées clés") {
                        // Editable: c'est une estimation du modele, pas une
                        // verite, et l'utilisateur retient mieux ce qu'il reecrit.
                        TextEditor(text: $ideas).frame(minHeight: 200)
                    }
                    Section { Label("Synthèse de ton coach, non vérifiée: elle restera marquée ainsi.", systemImage: "infinity").font(.caption).foregroundStyle(Theme.warning) }
                }
            }
            .navigationTitle("Résumé du coach").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(ideas.isEmpty)
                }
            }
        }
    }

    private func generate() async {
        busy = true; error = nil
        defer { busy = false }
        let who = author.trimmingCharacters(in: .whitespaces)
        let sys = """
        Tu résumes des livres pour quelqu'un qui veut en retenir l'essentiel.         Écris TES PROPRES phrases: ne cite pas le texte du livre, ne recopie         aucun passage. Réponds en français, 5 à 7 idées clés en puces courtes,         puis une ligne "À retenir :". Si tu ne connais pas ce livre, dis-le         franchement au lieu d'inventer.
        """
        let ask = "Livre : \(title)" + (who.isEmpty ? "" : "\nAuteur : \(who)")
        switch await AIText.ask(system: sys, user: ask, maxTokens: 600) {
        case .success(let t): ideas = t
        case .failure(let e): error = e.message
        }
    }

    private func save() {
        // Note 0 (aucune etoile): l'utilisateur n'a rien note. Et le texte porte la
        // marque d'origine, sinon la synthese du modele passait pour son resume.
        let b = BookSummary(title: title.trimmingCharacters(in: .whitespaces),
                            author: author.trimmingCharacters(in: .whitespaces),
                            keyIdeas: BookSummaryOrigin.markAI(ideas), rating: 0)
        ctx.insert(b)
        do { try ctx.save() } catch {
            AppLog.data.error("resume livre non sauvegarde: \(error.localizedDescription, privacy: .public)")
        }
        dismiss()
    }
}

/// Creation et modification d'un livre. Un resume du coach garde sa marque
/// "non verifiee" meme apres modification.
struct BookEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    var book: BookSummary? = nil
    @Query private var books: [BookSummary]
    @State private var title = ""
    @State private var author = ""
    @State private var ideas = ""
    @State private var rating = 4
    @State private var collections = ""
    @State private var loaded = false
    @State private var failed = false

    private var isAI: Bool { book.map { BookSummaryOrigin.isAI($0.keyIdeas) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre", text: $title)
                TextField("Auteur", text: $author)
                Stepper(rating == 0 ? "Pas de note" : "Note : \(rating)/5", value: $rating, in: 0...5)
                Section("Collections") {
                    TextField("Ex: Business, À relire (séparées par des virgules)", text: $collections)
                    let existing = BookCollections.all(books)
                    if !existing.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(existing, id: \.self) { c in
                                    let on = BookCollections.list(collections).contains { $0.caseInsensitiveCompare(c) == .orderedSame }
                                    Button {
                                        collections = BookCollections.toggled(collections, c).replacingOccurrences(of: "\n", with: ", ")
                                    } label: { Label(c, systemImage: on ? "checkmark" : "plus") }
                                        .buttonStyle(LifeOSGlassButtonStyle()).tint(.learnTint).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("Idées clés") {
                    if isAI { Label("Synthèse du coach, non vérifiée", systemImage: "infinity").font(.caption).foregroundStyle(Theme.warning) }
                    TextField("Ce que tu retiens…", text: $ideas, axis: .vertical).lineLimit(4...14)
                }
                if failed { Text(LearningSave.failure).font(.caption).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(book == nil ? "Nouveau résumé" : "Modifier le résumé").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(book == nil ? "Ajouter" : "Enregistrer") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let b = book {
                    title = b.title; author = b.author; rating = b.rating
                    ideas = BookSummaryOrigin.body(b.keyIdeas)
                    collections = BookCollections.list(b.collections).joined(separator: ", ")
                }
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces), a = author.trimmingCharacters(in: .whitespaces)
        let body = isAI ? BookSummaryOrigin.markAI(ideas) : ideas
        let cols = BookCollections.join(BookCollections.list(collections))
        if let b = book {
            b.title = t; b.author = a; b.rating = rating; b.keyIdeas = body; b.collections = cols; b.updatedAt = .now
        } else {
            let b = BookSummary(title: t, author: a, keyIdeas: body, rating: rating)
            b.collections = cols
            ctx.insert(b)
        }
        if LearningSave.commit(ctx, "resume livre") { dismiss() } else { failed = true }
    }
}

// MARK: - Programmes (Coursia)

enum LearningReminders {
    static func sync(course: Course, now: Date = .now) {
        let id = CourseOps.courseReminderID(course)
        NotificationManager.shared.cancel(id: id)
        guard course.remind, let d = course.deadline, let at = CourseOps.reminderDate(for: d, now: now) else { return }
        NotificationManager.shared.schedule(id: id, title: "Échéance: \(course.title)", body: "C'est aujourd'hui l'échéance de ton programme.", at: at)
    }
    static func sync(lesson: CourseLesson, courseTitle: String, now: Date = .now) {
        let id = CourseOps.lessonReminderID(lesson.uid)
        NotificationManager.shared.cancel(id: id)
        guard lesson.remind, !lesson.done, let d = lesson.deadline, let at = CourseOps.reminderDate(for: d, now: now) else { return }
        NotificationManager.shared.schedule(id: id, title: "Leçon à finir: \(lesson.title)", body: "Échéance aujourd'hui dans « \(courseTitle) ».", at: at)
    }
    static func cancel(lessonIDs: [UUID]) { lessonIDs.forEach { NotificationManager.shared.cancel(id: CourseOps.lessonReminderID($0)) } }
    static func cancel(course: Course) { NotificationManager.shared.cancel(id: CourseOps.courseReminderID(course)) }
}

struct SkillPlanView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Course.sortIndex) private var courses: [Course]
    @Query private var modules: [CourseModule]
    @Query private var lessons: [CourseLesson]
    @AppStorage(AppStorageKeys.skillPlanName) private var skill = ""
    @AppStorage(AppStorageKeys.skillPlanSteps) private var stepsRaw = ""
    @AppStorage(AppStorageKeys.skillPlanDone) private var doneRaw = ""
    @State private var showNew = false
    @State private var toDelete: Course?
    @State private var errorText: String?

    var body: some View {
        List {
            if courses.isEmpty {
                EmptyState(icon: "graduationcap", title: "Aucun programme",
                           message: "Crée un programme (une compétence, un cours), découpe-le en modules et en leçons, avec tes liens et tes notes.",
                           actionTitle: "Créer un programme") { showNew = true }
                    .listRowBackground(Color.clear)
            }
            ForEach(courses) { c in
                NavigationLink { CourseDetailView(course: c) } label: { courseRow(c) }
            }
            .onMove { from, to in
                CourseOps.renumber(CourseOps.moved(courses, from: from, to: to)); persist()
            }
            .onDelete { idx in toDelete = idx.first.map { courses[$0] } }
            Section {
                EmptyView()
            } footer: {
                Text("Évaluations notées, discussions et certificats ne sont pas proposés: ils demandent un établissement et un service de vérification.")
            }
        }
        .navigationTitle("Programmes").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button { showNew = true } label: { Image(systemName: "plus") }.accessibilityLabel("Nouveau programme") }
            if courses.count > 1 { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
        }
        .sheet(isPresented: $showNew) { CourseEditor(course: nil, nextIndex: courses.count) }
        .confirmationDialog("Supprimer le programme ?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible, presenting: toDelete) { c in
            Button("Supprimer « \(c.title) » et ses leçons", role: .destructive) {
                LearningReminders.cancel(course: c)
                LearningReminders.cancel(lessonIDs: CourseOps.delete(c, modules: modules, lessons: lessons, in: ctx))
                persist()
            }
        }
        .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
        .onAppear(perform: migrateLegacyPlan)
    }

    private func courseRow(_ c: Course) -> some View {
        let ls = CourseOps.lessons(of: c, modules: modules, lessons: lessons)
        let p = CourseOps.progress(ls)
        return VStack(alignment: .leading, spacing: 6) {
            Text(c.title).font(.headline)
            if !c.goal.isEmpty { Text(c.goal).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2) }
            if p.total > 0 { ProgressView(value: Double(p.done), total: Double(p.total)).tint(.learnTint) }
            HStack {
                Text(p.total == 0 ? "Aucune leçon" : "\(p.done)/\(p.total) leçons faites")
                Spacer()
                if let d = c.deadline {
                    let l = CourseOps.deadlineLabel(d)
                    Text(l.text).foregroundStyle(l.overdue && p.done < p.total ? Theme.danger : Theme.textSecondary)
                }
            }.font(.caption).foregroundStyle(Theme.textSecondary)
        }.padding(.vertical, 4)
    }

    /// L'ancien plan unique (AppStorage) devient un programme, une seule fois.
    private func migrateLegacyPlan() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: SkillPlanMigration.flagKey) else { return }
        guard SkillPlanMigration.migrate(skill: skill, stepsRaw: stepsRaw, doneRaw: doneRaw, in: ctx) != nil else {
            ud.set(true, forKey: SkillPlanMigration.flagKey); return
        }
        if LearningSave.commit(ctx, "reprise plan de competence") { ud.set(true, forKey: SkillPlanMigration.flagKey) } else { ctx.rollback() }
    }

    private func persist() { if !LearningSave.commit(ctx, "programme") { errorText = LearningSave.failure } }
}

struct CourseLessonTarget: Identifiable {
    let id = UUID()
    var lesson: CourseLesson?
    var module: CourseModule
}

struct CourseDetailView: View {
    @Environment(\.modelContext) private var ctx
    let course: Course
    @Query private var allModules: [CourseModule]
    @Query private var allLessons: [CourseLesson]
    @State private var lessonTarget: CourseLessonTarget?
    @State private var cardTarget: NoteEditTarget?
    @State private var showEditCourse = false
    @State private var modulePrompt: CourseModule?
    @State private var addingModule = false
    @State private var moduleTitle = ""
    @State private var moduleToDelete: CourseModule?
    @State private var errorText: String?

    private var mods: [CourseModule] { CourseOps.modules(of: course, in: allModules) }
    private var courseLessons: [CourseLesson] { CourseOps.lessons(of: course, modules: allModules, lessons: allLessons) }

    var body: some View {
        let p = CourseOps.progress(courseLessons)
        return List {
            Section {
                if !course.goal.isEmpty { Text(course.goal).font(.subheadline) }
                if p.total > 0 { ProgressView(value: Double(p.done), total: Double(p.total)).tint(.learnTint) }
                Text(p.total == 0 ? "Aucune leçon pour l'instant" : "\(p.done)/\(p.total) leçons faites").font(.caption).foregroundStyle(Theme.textSecondary)
                if let d = course.deadline {
                    let l = CourseOps.deadlineLabel(d)
                    Label(l.text + (course.remind ? " · rappel à 9 h" : ""), systemImage: "calendar").font(.caption)
                        .foregroundStyle(l.overdue && p.done < p.total ? Theme.danger : Theme.textSecondary)
                }
                if let next = CourseOps.next(courseLessons), let m = mods.first(where: { $0.uid == next.moduleUID }) {
                    Button { lessonTarget = CourseLessonTarget(lesson: next, module: m) } label: {
                        Label("Reprendre: \(next.title)", systemImage: "play.fill")
                    }.tint(.learnTint)
                }
            }
            if mods.isEmpty {
                Section { Text("Ajoute un module (par exemple Semaine 1), puis ses leçons.").foregroundStyle(Theme.textSecondary) }
            }
            ForEach(mods) { m in moduleSection(m) }
        }
        .navigationTitle(course.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { moduleTitle = ""; addingModule = true } label: { Label("Ajouter un module", systemImage: "folder.badge.plus") }
                    Button { showEditCourse = true } label: { Label("Modifier le programme", systemImage: "pencil") }
                } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Actions")
            }
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $lessonTarget) { CourseLessonEditor(target: $0, courseTitle: course.title) }
        .sheet(item: $cardTarget) { FlashcardEditor(target: $0) }
        .sheet(isPresented: $showEditCourse) { CourseEditor(course: course, nextIndex: 0) }
        .alert(modulePrompt == nil ? "Nouveau module" : "Renommer le module", isPresented: Binding(get: { addingModule || modulePrompt != nil }, set: { if !$0 { addingModule = false; modulePrompt = nil } })) {
            TextField("Titre du module", text: $moduleTitle)
            Button("Annuler", role: .cancel) {}
            Button("Valider") { commitModule() }
        }
        .confirmationDialog("Supprimer le module ?", isPresented: Binding(get: { moduleToDelete != nil }, set: { if !$0 { moduleToDelete = nil } }), titleVisibility: .visible, presenting: moduleToDelete) { m in
            Button("Supprimer « \(m.title) » et ses leçons", role: .destructive) {
                LearningReminders.cancel(lessonIDs: CourseOps.delete(m, lessons: allLessons, in: ctx)); persist()
            }
        }
        .alert("Action impossible", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorText ?? "") }
    }

    private func moduleSection(_ m: CourseModule) -> some View {
        let ls = CourseOps.lessons(of: m, in: allLessons)
        return Section {
            ForEach(ls) { l in lessonRow(l, module: m) }
                .onMove { from, to in CourseOps.renumber(CourseOps.moved(ls, from: from, to: to)); persist() }
                .onDelete { idx in
                    let gone = idx.map { ls[$0] }
                    LearningReminders.cancel(lessonIDs: gone.compactMap(\.uid))
                    gone.forEach { ctx.delete($0) }
                    persist()
                }
            Button { lessonTarget = CourseLessonTarget(module: m) } label: { Label("Ajouter une leçon", systemImage: "plus") }.tint(.learnTint)
        } header: {
            HStack {
                Text(m.title)
                Spacer()
                Menu {
                    Button { moduleTitle = m.title; modulePrompt = m } label: { Label("Renommer", systemImage: "pencil") }
                    Button { moveModule(m, by: -1) } label: { Label("Monter", systemImage: "arrow.up") }
                    Button { moveModule(m, by: 1) } label: { Label("Descendre", systemImage: "arrow.down") }
                    Button(role: .destructive) { moduleToDelete = m } label: { Label("Supprimer", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Actions du module \(m.title)")
            }
        }
    }

    private func lessonRow(_ l: CourseLesson, module m: CourseModule) -> some View {
        HStack(spacing: 12) {
            Button {
                CourseOps.toggle(l); LearningReminders.sync(lesson: l, courseTitle: course.title); persist()
            } label: {
                Image(systemName: l.done ? "checkmark.circle.fill" : "circle").foregroundStyle(l.done ? Theme.success : Theme.textSecondary).font(.title3)
            }.buttonStyle(.borderless).accessibilityLabel(l.done ? "Marquer comme à faire" : "Marquer comme faite")
            VStack(alignment: .leading, spacing: 3) {
                Text(l.title).strikethrough(l.done)
                if let d = l.deadline, !l.done {
                    let lab = CourseOps.deadlineLabel(d)
                    Text(lab.text).font(.caption).foregroundStyle(lab.overdue ? Theme.danger : Theme.textSecondary)
                }
                if !l.notes.isEmpty { Text(l.notes).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
            if let url = CourseOps.url(from: l.link) {
                Link(destination: url) { Image(systemName: "link") }.buttonStyle(.borderless).accessibilityLabel("Ouvrir la ressource")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { lessonTarget = CourseLessonTarget(lesson: l, module: m) }
        .contextMenu {
            Button { lessonTarget = CourseLessonTarget(lesson: l, module: m) } label: { Label("Modifier", systemImage: "pencil") }
            Button {
                cardTarget = NoteEditTarget(preset: NotePreset(front: l.title, back: l.notes, deckName: "Cours" + DeckTree.separator + course.title, tags: "cours", source: l.link))
            } label: { Label("Créer une flashcard", systemImage: "rectangle.on.rectangle.angled") }
        }
    }

    private func moveModule(_ m: CourseModule, by delta: Int) {
        guard let i = mods.firstIndex(where: { $0 === m }), mods.indices.contains(i + delta) else { return }
        var l = mods; l.swapAt(i, i + delta)
        CourseOps.renumber(l); persist()
    }

    private func commitModule() {
        let t = moduleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { addingModule = false; modulePrompt = nil }
        guard !t.isEmpty else { return }
        if let m = modulePrompt { m.title = t } else {
            if course.uid == nil { course.uid = UUID() }
            ctx.insert(CourseModule(courseUID: course.uid, title: t, sortIndex: (mods.map(\.sortIndex).max() ?? -1) + 1))
        }
        persist()
    }

    private func persist() { if !LearningSave.commit(ctx, "programme") { errorText = LearningSave.failure } }
}

struct CourseEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let course: Course?
    let nextIndex: Int
    @State private var title = ""
    @State private var goal = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
    @State private var remind = false
    @State private var loaded = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre (ex: Parler anglais couramment)", text: $title)
                TextField("Objectif, en une phrase (facultatif)", text: $goal, axis: .vertical).lineLimit(1...4)
                Section("Échéance") {
                    Toggle("Fixer une échéance", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                        LearningReminderToggle(label: "Me le rappeler (9 h le jour même)", isOn: $remind)
                        if remind && CourseOps.reminderDate(for: deadline) == nil {
                            Text("Cette date est passée: aucun rappel ne sera envoyé.").font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
                if failed { Text(LearningSave.failure).font(.caption).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(course == nil ? "Nouveau programme" : "Modifier le programme").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(course == nil ? "Créer" : "Enregistrer") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear {
                guard !loaded, let c = course else { loaded = true; return }
                loaded = true
                title = c.title; goal = c.goal; remind = c.remind
                if let d = c.deadline { hasDeadline = true; deadline = d }
            }
        }
    }

    private func save() {
        let c: Course
        if let course { c = course } else {
            c = Course(sortIndex: nextIndex)
            ctx.insert(c)
            // Un premier module pret: on peut ajouter une lecon tout de suite.
            ctx.insert(CourseModule(courseUID: c.uid, title: "Module 1"))
        }
        if c.uid == nil { c.uid = UUID() }
        c.title = title.trimmingCharacters(in: .whitespaces)
        c.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
        c.deadline = hasDeadline ? deadline : nil
        c.remind = hasDeadline && remind
        guard LearningSave.commit(ctx, "programme") else { failed = true; return }
        LearningReminders.sync(course: c)
        dismiss()
    }
}

struct CourseLessonEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let target: CourseLessonTarget
    let courseTitle: String
    @Query private var allLessons: [CourseLesson]
    @State private var title = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var done = false
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var remind = false
    @State private var loaded = false
    @State private var failed = false
    @State private var confirmDelete = false

    private var linkInvalid: Bool { !link.trimmingCharacters(in: .whitespaces).isEmpty && CourseOps.url(from: link) == nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre de la leçon", text: $title)
                Toggle("Faite", isOn: $done)
                Section("Ressource") {
                    TextField("Lien (vidéo, article, cours)", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    if linkInvalid { Text("Ce lien n'est pas une adresse web valide.").font(.caption).foregroundStyle(Theme.warning) }
                    if let url = CourseOps.url(from: link) { Link(destination: url) { Label("Ouvrir la ressource", systemImage: "safari") } }
                }
                Section("Notes") { TextField("Ce que tu retiens, tes questions…", text: $notes, axis: .vertical).lineLimit(3...12) }
                Section("Échéance") {
                    Toggle("Fixer une échéance", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                        LearningReminderToggle(label: "Me le rappeler (9 h le jour même)", isOn: $remind)
                        if remind && CourseOps.reminderDate(for: deadline) == nil {
                            Text("Cette date est passée: aucun rappel ne sera envoyé.").font(.caption).foregroundStyle(Theme.warning)
                        }
                    }
                }
                if target.lesson != nil {
                    Section { Button("Supprimer la leçon", role: .destructive) { confirmDelete = true } }
                }
                if failed { Text(LearningSave.failure).font(.caption).foregroundStyle(Theme.danger) }
            }
            .navigationTitle(target.lesson == nil ? "Nouvelle leçon" : "Leçon").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || linkInvalid) }
            }
            .confirmationDialog("Supprimer la leçon ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    guard let l = target.lesson else { return }
                    LearningReminders.cancel(lessonIDs: l.uid.map { [$0] } ?? [])
                    ctx.delete(l)
                    if LearningSave.commit(ctx, "suppression lecon") { dismiss() } else { failed = true }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let l = target.lesson {
                    title = l.title; link = l.link; notes = l.notes; done = l.done; remind = l.remind
                    if let d = l.deadline { hasDeadline = true; deadline = d }
                }
            }
        }
    }

    private func save() {
        let l: CourseLesson
        if let existing = target.lesson { l = existing } else {
            if target.module.uid == nil { target.module.uid = UUID() }
            let next = (CourseOps.lessons(of: target.module, in: allLessons).map(\.sortIndex).max() ?? -1) + 1
            l = CourseLesson(moduleUID: target.module.uid, sortIndex: next)
            ctx.insert(l)
        }
        l.title = title.trimmingCharacters(in: .whitespaces)
        l.link = link.trimmingCharacters(in: .whitespaces)
        l.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if l.done != done { CourseOps.toggle(l) }
        l.deadline = hasDeadline ? deadline : nil
        l.remind = hasDeadline && remind
        guard LearningSave.commit(ctx, "lecon") else { failed = true; return }
        LearningReminders.sync(lesson: l, courseTitle: courseTitle)
        dismiss()
    }
}

/// Les jalons sont stockes en texte (AppStorage): l'etat fait est indexe par texte,
/// donc on refuse les doublons et on nettoie l'etat a la suppression.
/// (Ancien format, garde pour la reprise `SkillPlanMigration`.)
enum SkillPlanSteps {
    /// Nil si vide ou deja present (meme texte, sans tenir compte des espaces autour).
    static func adding(_ raw: String, to steps: [String]) -> [String]? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !t.isEmpty, !steps.contains(t) else { return nil }
        return steps + [t]
    }

    /// Retire le jalon a la position i; son etat fait ne part que si plus aucun jalon ne porte ce texte.
    static func removing(at i: Int, steps: [String], done: Set<String>) -> (steps: [String], done: Set<String>) {
        guard steps.indices.contains(i) else { return (steps, done) }
        var s = steps
        let removed = s.remove(at: i)
        var d = done
        if !s.contains(removed) { d.remove(removed) }
        return (s, d)
    }
}

/// Marque d'origine d'un resume genere par le coach, sans changer le modele SwiftData.
enum BookSummaryOrigin {
    static let aiMarker = "[Synthèse de ton coach, non vérifiée]"

    static func markAI(_ ideas: String) -> String {
        isAI(ideas) ? ideas : aiMarker + "\n" + ideas
    }

    static func isAI(_ keyIdeas: String) -> Bool { keyIdeas.hasPrefix(aiMarker) }

    /// Texte affiche sans la marque (elle est rendue en badge a part).
    static func body(_ keyIdeas: String) -> String {
        guard isAI(keyIdeas) else { return keyIdeas }
        return String(keyIdeas.dropFirst(aiMarker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
