import SwiftUI
import SwiftData

extension ShapeStyle where Self == Color { static var adminTint: Color { AppCategory.admin.tint } }

// MARK: - Hub Admin

struct AdminHubView: View {
    var body: some View {
        HubScaffold(category: .admin) {
            ToolRow(icon: "lock.doc.fill", title: "Coffre-fort documents",
                    subtitle: "ID, contrats, garanties", tint: .adminTint) { DocVaultView() }
            ToolRow(icon: "bell.badge.fill", title: "Échéances",
                    subtitle: "Impôts, assurance, abos", tint: .adminTint) { DeadlinesView() }
            ToolRow(icon: "envelope.fill", title: "Générateur de courriers",
                    subtitle: "Résiliation, attestation…", tint: .adminTint) { LetterGeneratorView() }
            ToolRow(icon: "doc.viewfinder.fill", title: "Scan & classement",
                    subtitle: "OCR auto — à brancher", tint: .adminTint) { DocScanScaffold() }
        }
    }
}

// MARK: - Coffre-fort documents

struct DocVaultView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \DocVault.title) private var docs: [DocVault]
    @State private var showAdd = false
    private var categories: [String] { Array(Set(docs.map { $0.category })).sorted() }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    if docs.isEmpty {
                        EmptyState(icon: "lock.doc", title: "Coffre vide", message: "Photographie tes documents importants : ils restent sur ton appareil.")
                    } else {
                        ForEach(categories, id: \.self) { cat in
                            VStack(alignment: .leading, spacing: 8) {
                                SectionHeader(title: cat)
                                ForEach(docs.filter { $0.category == cat }) { d in
                                    HStack {
                                        StoredImage(filename: d.filename, placeholder: "doc.text").frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading) {
                                            Text(d.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                            if let e = d.expiry { Text("Expire le \(e, style: .date)").font(.caption).foregroundStyle(e < .now ? .red : Theme.textSecondary) }
                                        }
                                        Spacer()
                                    }.card(padding: 12)
                                        .contextMenu { Button(role: .destructive) { ImageStore.delete(d.filename); ctx.delete(d) } label: { Label("Supprimer", systemImage: "trash") } }
                                }
                            }
                        }
                    }
                    Text("🔒 Tes documents sont stockés localement sur ton iPhone (chiffré par iOS), pas sur un serveur.").font(.caption).foregroundStyle(Theme.textSecondary)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Coffre-fort").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { DocEditor() }
    }
}

struct DocEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var category = "Identité"
    @State private var hasExpiry = false; @State private var expiry = Date()
    @State private var filename: String?; @State private var note = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("Titre (ex: Passeport)", text: $title)
                Picker("Catégorie", selection: $category) { ForEach(["Identité","Contrat","Garantie","Santé","Impôts","Logement","Véhicule"], id: \.self) { Text($0) } }
                Toggle("Date d'expiration", isOn: $hasExpiry)
                if hasExpiry { DatePicker("Expire le", selection: $expiry, displayedComponents: .date) }
                Section("Photo du document") {
                    PhotoPickerButton(label: "Prendre / choisir", prefix: "doc") { filename = $0 }
                    if filename != nil { Text("Document ajouté ✓").foregroundStyle(.green).font(.caption) }
                }
            }
            .navigationTitle("Nouveau document").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(DocVault(title: title, category: category, filename: filename, expiry: hasExpiry ? expiry : nil, note: note))
                    if hasExpiry { NotificationManager.shared.schedule(id: "doc-\(title)", title: "Document expire bientôt", body: "\(title) expire le \(expiry.formatted(date: .abbreviated, time: .omitted))", at: Calendar.current.date(byAdding: .day, value: -30, to: expiry) ?? expiry) }
                    dismiss()
                }.disabled(title.isEmpty) }
            }
        }
    }
}

// MARK: - Échéances

struct DeadlinesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Deadline.date) private var deadlines: [Deadline]
    @State private var showAdd = false
    private var upcoming: [Deadline] { deadlines.filter { $0.date >= Calendar.current.startOfDay(for: .now) } }
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    if upcoming.isEmpty {
                        EmptyState(icon: "bell.badge", title: "Aucune échéance", message: "Impôts, taxe foncière, renouvellement d'assurance…")
                    } else {
                        ForEach(upcoming) { d in
                            HStack {
                                Image(systemName: iconFor(d.kind)).foregroundStyle(Color.adminTint).frame(width: 30)
                                VStack(alignment: .leading) { Text(d.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary); Text(d.kind).font(.caption).foregroundStyle(Theme.textSecondary) }
                                Spacer()
                                let days = Calendar.current.dateComponents([.day], from: .now, to: d.date).day ?? 0
                                Text(days == 0 ? "Aujourd'hui" : "J-\(days)").font(.subheadline.bold()).foregroundStyle(days <= 7 ? .orange : Theme.textSecondary)
                            }.card(padding: 12)
                                .contextMenu { Button(role: .destructive) { ctx.delete(d) } label: { Label("Supprimer", systemImage: "trash") } }
                        }
                    }
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Échéances").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showAdd = true } label: { Image(systemName: "plus") } } }
        .sheet(isPresented: $showAdd) { DeadlineEditor() }
    }
    private func iconFor(_ k: String) -> String { switch k { case "Impôts": return "eurosign.circle.fill"; case "Assurance": return "shield.fill"; case "Abonnement": return "repeat.circle.fill"; default: return "calendar" } }
}

struct DeadlineEditor: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""; @State private var kind = "Impôts"; @State private var date = Date(); @State private var remind = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("Intitulé", text: $title)
                Picker("Type", selection: $kind) { ForEach(["Impôts","Assurance","Abonnement","Autre"], id: \.self) { Text($0) } }
                DatePicker("Échéance", selection: $date, displayedComponents: .date)
                Toggle("Rappel 7 jours avant", isOn: $remind)
            }
            .navigationTitle("Nouvelle échéance").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Ajouter") {
                    ctx.insert(Deadline(title: title, date: date, kind: kind))
                    if remind { NotificationManager.shared.schedule(id: "deadline-\(title)", title: "Échéance : \(title)", body: "Dans 7 jours.", at: Calendar.current.date(byAdding: .day, value: -7, to: date) ?? date) }
                    dismiss()
                }.disabled(title.isEmpty) }
            }
        }
    }
}

// MARK: - Générateur de courriers

struct LetterGeneratorView: View {
    struct Template: Identifiable { let id = UUID(); let name: String; let icon: String; let body: String }
    private let templates: [Template] = [
        Template(name: "Résiliation d'abonnement", icon: "xmark.circle", body: """
        [Tes nom et prénom]
        [Ton adresse]

        À [Ville], le [date]

        Objet : Résiliation de mon abonnement n°[numéro de contrat]

        Madame, Monsieur,

        Par la présente, je vous informe de ma décision de résilier mon abonnement référencé ci-dessus, conformément aux conditions générales en vigueur.

        Je vous remercie de bien vouloir prendre en compte cette résiliation et de m'adresser une confirmation écrite.

        Veuillez agréer, Madame, Monsieur, mes salutations distinguées.

        [Signature]
        """),
        Template(name: "Attestation d'hébergement", icon: "house", body: """
        Je soussigné(e) [ton nom], demeurant [ton adresse],

        atteste sur l'honneur héberger à mon domicile :
        [Nom de la personne hébergée], depuis le [date].

        Fait pour servir et valoir ce que de droit.

        À [Ville], le [date]
        [Signature]
        """),
        Template(name: "Demande de congé", icon: "calendar", body: """
        [Tes nom et prénom]
        [Service / Poste]

        À l'attention de [Manager]

        Objet : Demande de congés payés

        Madame, Monsieur,

        Je souhaite poser des congés du [date début] au [date fin] inclus, soit [nombre] jours ouvrés.

        Je reste disponible pour assurer la passation nécessaire. Dans l'attente de votre validation, je vous prie d'agréer mes salutations.

        [Signature]
        """),
        Template(name: "Réclamation / remboursement", icon: "exclamationmark.bubble", body: """
        [Tes nom et prénom]
        [Ton adresse]

        À [Ville], le [date]

        Objet : Réclamation — demande de remboursement

        Madame, Monsieur,

        Le [date], j'ai [acheté/souscrit] [produit/service] pour un montant de [montant] €. Or, [décris le problème].

        Je vous demande donc le remboursement / la résolution sous 14 jours, faute de quoi je me réserve le droit de saisir le médiateur compétent.

        Veuillez agréer mes salutations distinguées.

        [Signature]
        """)
    ]
    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(templates) { t in
                        NavigationLink { LetterDetail(name: t.name, text: t.body) } label: {
                            HStack {
                                Image(systemName: t.icon).font(.title3).foregroundStyle(Color.adminTint).frame(width: 40, height: 40).background(Color.adminTint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                                Text(t.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Spacer(); Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            }.card(padding: 12)
                        }.buttonStyle(.plain)
                    }
                    Text("Remplace les champs entre [crochets], puis exporte ou copie le courrier.").font(.caption).foregroundStyle(Theme.textSecondary)
                }.padding(Theme.pad)
            }
        }
        .navigationTitle("Courriers types").navigationBarTitleDisplayMode(.inline)
    }
}

struct LetterDetail: View {
    let name: String
    @State var text: String
    var body: some View {
        ZStack {
            Theme.background
            VStack {
                TextEditor(text: $text)
                    .font(.callout).scrollContentBackground(.hidden).padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius)).foregroundStyle(Theme.textPrimary).padding()
                ShareLink(item: text) {
                    Label("Exporter / Copier", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.adminTint, in: RoundedRectangle(cornerRadius: Theme.radiusSmall)).foregroundStyle(.white)
                }.padding(.horizontal)
            }
        }
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Scan scaffold

struct DocScanScaffold: View {
    var body: some View {
        ScaffoldPage(icon: "doc.viewfinder.fill", title: "Scan & classement auto", tint: .adminTint,
            notice: "Le scan de documents avec recadrage et OCR est faisable 100% gratuitement et on-device avec VisionKit (VNDocumentCameraViewController pour scanner, VNRecognizeTextRequest pour lire le texte). Le classement auto (deviner la catégorie : facture, contrat, ID…) s'ajoute via des règles sur le texte reconnu ou un petit modèle. Tout reste sur l'appareil.",
            bullets: ["Scanner : VNDocumentCameraViewController (natif, gratuit)", "OCR : Vision VNRecognizeTextRequest (on-device)", "Classement : règles mots-clés ou modèle léger", "Stockage : déjà fait dans le coffre-fort"])
    }
}
