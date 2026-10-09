import SwiftUI
import SwiftData

/// Capture universelle : on ecrit (ou dicte) une phrase, LifeOS propose une tache, une
/// depense ou une note, on corrige, on enregistre, et on peut annuler pendant 5 s.
///
/// Autonome : lit le `modelContext` de l'environnement et se ferme seule. L'onglet
/// central « + » et l'accueil l'ouvrent avec `UniversalCaptureSheet(prefill:)`.
struct UniversalCaptureSheet: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Account.name) private var accounts: [Account]

    private let prefill: String
    init(prefill: String = "") { self.prefill = prefill }

    // Texte et lecture
    @State private var text = ""
    @State private var proposal = CaptureProposal()
    /// L'utilisateur a corrige un champ : le texte ne l'ecrase plus.
    @State private var detached = false
    @State private var loaded = false

    // Champs corrigeables
    @State private var kind: CaptureKind = .note
    @State private var title = ""
    @State private var hasDate = false
    @State private var hasTime = false
    @State private var date = Date()
    @State private var amountText = ""
    @State private var category = CaptureParser.fallbackCategory
    @State private var accountID: UUID?
    @State private var noteBody = ""
    @State private var remindAtTime = false
    /// Ambiguites deja confirmees par l'utilisateur.
    @State private var confirmed: Set<CaptureFlag> = []

    // Enregistrement et annulation
    @State private var saving = false
    @State private var error: String?
    @State private var receipt: CaptureService.Receipt?
    @State private var undoToken = 0
    @State private var undoSecondsLeft = 5
    @State private var undone = false

    // Dictee
    @State private var speech = SpeechRecognizer()
    @State private var dictationBase = ""
    @FocusState private var textFocused: Bool

    private static let undoDelay = 5

    var body: some View {
        NavigationStack {
            Form {
                inputSection
                if receipt == nil {
                    previewSection
                    if let error {
                        Section {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.danger)
                        }
                    }
                }
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(receipt == nil ? "Annuler" : "Fermer") { close() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if receipt == nil {
                        Button { save() } label: {
                            if saving { ProgressView() } else { Text("Enregistrer").bold() }
                        }
                        .disabled(!canSave)
                        .accessibilityHint(pendingFlags.isEmpty ? "" : "Confirme d'abord les champs signalés")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let receipt { undoBar(receipt) }
            }
            .onAppear(perform: load)
            .onChange(of: text) { _, new in
                if !detached { apply(CaptureParser.parse(new, accounts: accounts.map(\.name))) }
            }
            .onChange(of: speech.transcript) { _, t in
                guard speech.isRecording || !t.isEmpty else { return }
                text = dictationBase.isEmpty ? t : dictationBase + " " + t
            }
            .onDisappear { if speech.isRecording { speech.stop() } }
        }
    }

    // MARK: Saisie

    private var inputSection: some View {
        Section {
            HStack(alignment: .top, spacing: 8) {
                TextField("Ex : café 3 € hier, appeler maman demain 18h…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($textFocused)
                    .disabled(receipt != nil)
                    .accessibilityLabel("Texte à capturer")
                Button(action: toggleDictation) {
                    Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .font(.title3)
                        .foregroundStyle(speech.isRecording ? Theme.danger : Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .glassControl(Circle())
                }
                .buttonStyle(.plain)
                .disabled(receipt != nil)
                .accessibilityLabel(speech.isRecording ? "Arrêter la dictée" : "Dicter")
            }
            if speech.isRecording {
                Label("Je t'écoute…", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            if let m = speech.errorMessage {
                Label(m, systemImage: "mic.slash").font(.caption).foregroundStyle(Theme.warning)
            }
            if detached && receipt == nil {
                Button("Relire le texte") {
                    detached = false
                    apply(CaptureParser.parse(text, accounts: accounts.map(\.name)))
                }
                .font(.caption.weight(.semibold))
            }
        } footer: {
            if receipt == nil {
                Text("Tout est lu sur ton téléphone. Vérifie ce qui a été compris avant d'enregistrer.")
            }
        }
    }

    // MARK: Apercu

    private var previewSection: some View {
        Section {
            Picker("Type", selection: Binding(get: { kind }, set: { kind = $0; detached = true })) {
                ForEach(CaptureKind.allCases) { k in Label(k.label, systemImage: k.icon).tag(k) }
            }
            .pickerStyle(.segmented)

            switch kind {
            case .task: taskFields
            case .expense: expenseFields
            case .note: noteFields
            }
        } header: {
            Text("Ce que j'ai compris")
        }
    }

    @ViewBuilder private var taskFields: some View {
        TextField("Titre", text: edit($title))
        if text.isEmpty == false, title.trimmingCharacters(in: .whitespaces).isEmpty {
            flagRow("Écris un titre pour la tâche.")
        }
        Toggle("Échéance", isOn: edit($hasDate))
        if hasDate {
            Toggle("Heure précise", isOn: edit($hasTime))
            DatePicker("Quand", selection: edit($date),
                       displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            if hasTime {
                Toggle("Me le rappeler à l'heure", isOn: $remindAtTime)
            }
        }
        if let t = proposal.task, !detached {
            CapturePreview(parsed: t)
        }
    }

    @ViewBuilder private var expenseFields: some View {
        let amountPending = amountFlagPending
        HStack {
            Label("Montant", systemImage: amountPending ? "exclamationmark.circle.fill" : "eurosign")
                .foregroundStyle(amountPending ? Theme.warning : Theme.textPrimary)
            Spacer()
            TextField("0,00", text: Binding(get: { amountText }, set: {
                amountText = $0
                detached = true
                if AmountInput.parse($0).value != nil { confirmAmount() }
            }))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 120)
            Text("€").foregroundStyle(Theme.textSecondary)
        }
        .listRowBackground(amountPending ? Theme.warning.opacity(0.14) : nil)
        if amountPending { amountFlagHelp }
        if !amountText.isEmpty, let m = AmountInput.parse(amountText).message {
            Text(m).font(.caption).foregroundStyle(Theme.warning)
        }

        TextField("Libellé", text: edit($title))
        Picker("Catégorie", selection: edit($category)) {
            ForEach(CaptureParser.expenseCategories, id: \.self) { Text($0).tag($0) }
        }
        DatePicker("Date", selection: edit($date), displayedComponents: [.date])

        if accounts.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Aucun compte", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.warning)
                Text("Une dépense doit appartenir à un compte pour compter dans ton solde.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                NavigationLink { AccountsView() } label: {
                    Label("Créer un compte dans Bankino", systemImage: "building.columns.fill")
                        .frame(minHeight: 44)
                }
            }
            .listRowBackground(Theme.warning.opacity(0.14))
        } else {
            let accountPending = pendingFlags.contains(.unknownAccount)
            Picker("Compte", selection: Binding(get: { accountID }, set: {
                accountID = $0
                detached = true
                confirmed.insert(.unknownAccount)
            })) {
                ForEach(accounts, id: \.id) { a in
                    Text(a.name.isEmpty ? a.kind : a.name).tag(Optional(a.id))
                }
            }
            .listRowBackground(accountPending ? Theme.warning.opacity(0.14) : nil)
            if accountPending, let mention = proposal.mentionedAccount {
                VStack(alignment: .leading, spacing: 6) {
                    flagRow("« \(mention) » n'est pas un de tes comptes. Choisis le bon compte.")
                    Button("Utiliser le compte choisi") { confirmed.insert(.unknownAccount); Haptics.tap() }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
            }
        }
    }

    @ViewBuilder private var noteFields: some View {
        TextField("Titre", text: edit($title))
        TextField("Contenu", text: edit($noteBody), axis: .vertical)
            .lineLimit(3...8)
    }

    @ViewBuilder private var amountFlagHelp: some View {
        if proposal.flags.contains(.multipleAmounts) && !proposal.amountCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                flagRow("Plusieurs montants trouvés. Lequel est la dépense ?")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(proposal.amountCandidates, id: \.self) { v in
                            Button(v.formatted(.currency(code: "EUR"))) {
                                amountText = Self.format(v)
                                confirmAmount()
                                Haptics.tap()
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .glassControl(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        } else if proposal.flags.contains(.unconfirmedAmount) && AmountInput.parse(amountText).value != nil {
            VStack(alignment: .leading, spacing: 6) {
                flagRow("Le nombre n'avait pas de « € ». Est-ce bien le montant ?")
                Button("Oui, c'est le montant") { confirmAmount(); Haptics.tap() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
            }
        } else {
            flagRow("Aucun montant trouvé. Indique-le.")
        }
    }

    private func flagRow(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.caption)
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Barre d'annulation

    private func undoBar(_ r: CaptureService.Receipt) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.label).font(.subheadline.weight(.semibold))
                Text("Fermeture dans \(undoSecondsLeft) s").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Annuler") { undo(r) }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .glassControl(Capsule())
                .buttonStyle(.plain)
                .accessibilityHint("Supprime ce qui vient d'être enregistré")
            Button("Nouvelle") { startOver() }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(14)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous), .floating)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: Regles

    /// Ambiguites encore a confirmer pour le type actuel.
    private var pendingFlags: Set<CaptureFlag> {
        guard kind == .expense else { return [] }
        return proposal.flags.subtracting(confirmed).subtracting([.emptyTitle])
    }

    private var amountFlagPending: Bool {
        if AmountInput.parse(amountText).value == nil { return true }
        return !pendingFlags.isDisjoint(with: [.missingAmount, .multipleAmounts, .unconfirmedAmount])
    }

    private var canSave: Bool {
        guard !saving, receipt == nil else { return false }
        switch kind {
        case .task: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .note: return !title.trimmingCharacters(in: .whitespaces).isEmpty || !noteBody.trimmingCharacters(in: .whitespaces).isEmpty
        case .expense:
            guard let v = AmountInput.parse(amountText).value, v > 0 else { return false }
            return accountID != nil && !accounts.isEmpty && pendingFlags.isEmpty
        }
    }

    private func confirmAmount() {
        confirmed.formUnion([.missingAmount, .multipleAmounts, .unconfirmedAmount])
    }

    /// Un champ modifie a la main detache l'apercu du texte.
    private func edit<T>(_ b: Binding<T>) -> Binding<T> {
        Binding(get: { b.wrappedValue }, set: { b.wrappedValue = $0; detached = true })
    }

    // MARK: Actions

    private func load() {
        guard !loaded else { return }
        loaded = true
        text = prefill
        apply(CaptureParser.parse(prefill, accounts: accounts.map(\.name)))
        if prefill.isEmpty { textFocused = true }
    }

    private func apply(_ p: CaptureProposal) {
        proposal = p
        kind = p.kind
        title = p.title
        hasDate = p.date != nil && p.kind == .task
        hasTime = p.hasTime
        date = p.date ?? Date()
        amountText = p.amount.map(Self.format) ?? ""
        category = p.category
        accountID = accounts.first(where: { $0.name == p.accountName })?.id
            ?? CaptureService.defaultAccount(accounts)?.id
        noteBody = p.kind == .note ? p.noteBody : ""
        confirmed = []
        error = nil
    }

    private func save() {
        guard canSave else { return }
        saving = true
        defer { saving = false }
        if speech.isRecording { speech.stop() }
        let draft = CaptureService.Draft(
            kind: kind,
            title: title,
            date: kind == .task ? (hasDate ? (hasTime ? date : Calendar.current.startOfDay(for: date)) : nil) : date,
            hasTime: kind == .task && hasDate && hasTime,
            amount: AmountInput.parse(amountText).value,
            category: category,
            accountID: accountID,
            noteBody: kind == .note ? noteBody : "",
            parsedTask: detached ? stripDates(proposal.task) : proposal.task,
            reminderMinutes: remindAtTime ? 0 : -1)
        do {
            let r = try CaptureService.save(draft, in: ctx)
            Haptics.success()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { receipt = r }
            startUndoCountdown()
        } catch {
            Haptics.warning()
            self.error = error.localizedDescription
        }
    }

    /// La recurrence lue reste, mais l'echeance vient des champs corriges.
    private func stripDates(_ p: ParsedTask?) -> ParsedTask? {
        guard var p else { return nil }
        p.due = nil
        return p
    }

    private func startUndoCountdown() {
        undoToken += 1
        let token = undoToken
        undoSecondsLeft = Self.undoDelay
        Task { @MainActor in
            for left in stride(from: Self.undoDelay - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard token == undoToken, receipt != nil else { return }
                undoSecondsLeft = left
            }
            if token == undoToken, receipt != nil { dismiss() }
        }
    }

    private func undo(_ r: CaptureService.Receipt) {
        undoToken += 1   // arrete la fermeture automatique
        do {
            try CaptureService.undo(r, in: ctx)
            Haptics.tap()
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { receipt = nil }
            error = nil
        } catch {
            self.error = "L'annulation n'a pas pu être enregistrée : \(error.localizedDescription)"
        }
    }

    private func startOver() {
        undoToken += 1
        withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { receipt = nil }
        detached = false
        text = ""
        apply(CaptureParser.parse("", accounts: accounts.map(\.name)))
        textFocused = true
    }

    private func close() {
        undoToken += 1
        if speech.isRecording { speech.stop() }
        dismiss()
    }

    private func toggleDictation() {
        if speech.isRecording {
            speech.stop()
            return
        }
        // La permission n'est demandee qu'ici, quand on touche le micro.
        Task { @MainActor in
            guard await speech.requestAuthorization() else { return }
            dictationBase = text.trimmingCharacters(in: .whitespacesAndNewlines)
            speech.start()
        }
    }

    static func format(_ v: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.minimumFractionDigits = v.rounded() == v ? 0 : 2
        f.maximumFractionDigits = 2
        f.usesGroupingSeparator = false
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}
