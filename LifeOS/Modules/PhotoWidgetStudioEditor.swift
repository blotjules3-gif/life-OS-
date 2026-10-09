import SwiftUI
import PhotosUI
import UIKit

/// Editeur d'une configuration de widget photo. Ouvert en feuille: il a sa propre pile.
struct PhotoWidgetEditorView: View {
    let isNew: Bool
    @ObservedObject var store: PhotoWidgetStore
    @ObservedObject var thumbs: PhotoWidgetThumbCache
    /// Appele a la fermeture: la configuration enregistree, ou nil si annule.
    let onFinish: (PhotoWidgetConfig?) -> Void

    @State private var config: PhotoWidgetConfig
    @State private var previewSize: PhotoWidgetSize = .small
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var cropping: PhotoRef?
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    /// Fichiers importes pendant cette edition (a effacer si on annule).
    @State private var importedThisSession: [String] = []
    @State private var goalCurrentText = ""
    @State private var goalTargetText = ""
    @State private var previewWidth: CGFloat = 0
    private let original: PhotoWidgetConfig

    init(draft: PhotoWidgetDraft, store: PhotoWidgetStore, thumbs: PhotoWidgetThumbCache, onFinish: @escaping (PhotoWidgetConfig?) -> Void) {
        isNew = draft.isNew
        self.store = store
        self.thumbs = thumbs
        self.onFinish = onFinish
        original = draft.config
        _config = State(initialValue: draft.config)
        _goalCurrentText = State(initialValue: draft.config.content.goalTarget > 0 || draft.config.content.goalCurrent != 0 ? PhotoWidgetGoal.format(draft.config.content.goalCurrent) : "")
        _goalTargetText = State(initialValue: draft.config.content.goalTarget > 0 ? PhotoWidgetGoal.format(draft.config.content.goalTarget) : "")
    }

    private var hasChanges: Bool { isNew || config != original }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewSection
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    identitySection
                    if config.template.usesPhotos || config.style.background == .blurredPhoto { photosSection }
                    layoutSection
                    textSection
                    colorsSection
                    actionSection
                    if !isNew { dangerSection }
                }
                .padding(Theme.pad)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(isNew ? "Nouveau widget" : "Modifier le widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { if hasChanges { confirmDiscard = true } else { cancel() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { save() } label: {
                        if saving { ProgressView() } else { Text("Enregistrer").bold() }
                    }
                    .disabled(saving || importing)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Abandonner les changements ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Abandonner", role: .destructive) { cancel() }
                Button("Continuer à modifier", role: .cancel) {}
            }
            .confirmationDialog("Supprimer ce widget ?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Supprimer « \(original.name) »", role: .destructive) { deleteConfig() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Ses photos seront effacées de l'espace des widgets. Tes photos d'origine ne sont pas touchées.")
            }
            .sheet(item: $cropping) { ref in
                PhotoWidgetCropperView(ref: ref) { newCrop in
                    if let i = config.photos.firstIndex(where: { $0.id == ref.id }) { config.photos[i].crop = newCrop }
                }
            }
            .onChange(of: pickerItems) { _, items in importPicked(items) }
        }
    }

    // MARK: Apercu

    private var availableSizes: [PhotoWidgetSize] {
        config.template.supportsLockScreen ? PhotoWidgetSize.allCases : [.small, .medium, .large]
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Taille de l'aperçu", selection: $previewSize) {
                ForEach(availableSizes) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            let scale = previewWidth > 0 ? min(1, previewWidth / previewSize.points.width) : 0.8
            PhotoWidgetPreview(config: config, size: previewSize, thumbs: thumbs, scale: scale)
                .frame(maxWidth: .infinity)
            Color.clear.frame(height: 0).frame(maxWidth: .infinity)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { previewWidth = g.size.width }
                        .onChange(of: g.size.width) { _, v in previewWidth = v }
                })
            Text("Aperçu à la taille réelle d'un iPhone 6,1 pouces. La taille exacte dépend du modèle d'iPhone.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .card()
        .onChange(of: config.template) { _, t in
            if !t.supportsLockScreen && previewSize == .rectangular { previewSize = .small }
        }
    }

    // MARK: Nom et modele

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Nom et modèle", icon: "textformat")
            TextField("Nom du widget", text: $config.name)
                .textInputAutocapitalization(.sentences)
                .padding(12)
                .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
                .accessibilityLabel("Nom du widget")
            Picker("Modèle", selection: $config.template) {
                ForEach(PhotoWidgetTemplate.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.menu)
            if let missing = config.missingContent {
                Label(missing, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warning)
            }
        }
        .card()
    }

    // MARK: Photos

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Photos", icon: "photo.on.rectangle")
            Text("Seules les photos que tu choisis sont copiées, réduites, dans l'espace des widgets.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
            PhotosPicker(selection: $pickerItems, maxSelectionCount: 12, selectionBehavior: .ordered, matching: .images) {
                HStack {
                    if importing { ProgressView() } else { Image(systemName: "plus") }
                    Text(importing ? "Ajout en cours" : "Ajouter des photos")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassControl(Capsule())
            }
            .disabled(importing)
            ForEach(Array(config.photos.enumerated()), id: \.element.id) { index, ref in
                photoRow(ref, index: index)
            }
            if config.photos.count > 1 {
                Text("Les photos marquées « en rotation » défilent selon le rythme choisi dans Disposition.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    private func photoRow(_ ref: PhotoRef, index: Int) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Theme.bg2
                if let img = thumbs.image(for: ref) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .task(id: PhotoWidgetThumbCache.key(ref)) { await thumbs.load([ref], maxPixel: 300) }
            .accessibilityLabel("Photo \(index + 1)")
            Spacer(minLength: 0)
            iconButton("chevron.up", "Monter la photo \(index + 1)", enabled: index > 0) { move(index, by: -1) }
            iconButton("chevron.down", "Descendre la photo \(index + 1)", enabled: index < config.photos.count - 1) { move(index, by: 1) }
            iconButton("crop", "Recadrer la photo \(index + 1)") { cropping = ref }
            iconButton(ref.inRotation ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle",
                       ref.inRotation ? "Retirer la photo \(index + 1) de la rotation" : "Mettre la photo \(index + 1) en rotation") {
                config.photos[index].inRotation.toggle()
            }
            iconButton("trash", "Retirer la photo \(index + 1)", tint: Theme.danger) { config.photos.remove(at: index) }
        }
    }

    private func iconButton(_ icon: String, _ label: String, enabled: Bool = true, tint: Color = Theme.textPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
        .accessibilityLabel(label)
    }

    private func move(_ index: Int, by delta: Int) {
        let target = index + delta
        guard config.photos.indices.contains(index), config.photos.indices.contains(target) else { return }
        config.photos.swapAt(index, target)
    }

    // MARK: Disposition

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Disposition", icon: "rectangle.3.group")
            if config.template == .collage {
                Picker("Photos affichées", selection: $config.style.layout) {
                    ForEach(PhotoWidgetLayout.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if config.template.usesPhotos {
                Picker("Rotation", selection: $config.rotation) {
                    ForEach(PhotoWidgetRotation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            }
            slider("Marge", value: $config.style.padding, range: 0...24, unit: "pt")
            if config.template.usesPhotos {
                slider("Coins des photos", value: $config.style.cornerRadius, range: 0...28, unit: "pt")
            }
        }
        .card()
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double = 1) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }

    // MARK: Texte

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Texte", icon: "character.cursor.ibeam")
            switch config.template {
            case .photo, .collage:
                if config.template == .photo {
                    field("Légende (facultatif)", text: $config.content.text)
                } else {
                    Text("Le collage n'affiche pas de texte.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            case .note:
                TextEditor(text: $config.content.text)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
                    .accessibilityLabel("Texte de la note")
            case .countdown:
                field("Pour quoi ? (ex. Vacances)", text: $config.content.countdownLabel)
                if let date = config.content.countdownDate {
                    DatePicker("Date", selection: Binding(get: { date }, set: { config.content.countdownDate = $0 }), displayedComponents: .date)
                } else {
                    Button {
                        config.content.countdownDate = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: Date()))
                    } label: {
                        Label("Choisir la date", systemImage: "calendar")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44).glassControl(Capsule())
                    }
                    .buttonStyle(LifeOSPressStyle())
                }
            case .goal:
                field("Objectif (ex. Lire des livres)", text: $config.content.goalTitle)
                HStack(spacing: 10) {
                    numberField("Où j'en suis", text: $goalCurrentText) { config.content.goalCurrent = $0 }
                    numberField("À atteindre", text: $goalTargetText) { config.content.goalTarget = max(0, $0) }
                }
                field("Unité (facultatif, ex. livres)", text: $config.content.goalUnit)
                Text("Tu mets ce chiffre à jour ici. Il n'est pas relié à un autre outil de LifeOS.")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if config.template != .collage {
                typographyControls
            }
        }
        .card()
    }

    private var typographyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Police", selection: $config.typography.family) {
                ForEach(PhotoWidgetFontFamily.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Graisse", selection: $config.typography.weight) {
                ForEach(PhotoWidgetFontWeight.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            slider("Taille du texte", value: $config.typography.size, range: 10...56, unit: "pt")
            Picker("Alignement", selection: $config.typography.alignment) {
                ForEach(PhotoWidgetAlignment.allCases) { Image(systemName: $0.icon).accessibilityLabel($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            swatchRow("Couleur du texte", selection: $config.typography.color)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(12)
            .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
            .accessibilityLabel(placeholder)
    }

    private func numberField(_ title: String, text: Binding<String>, apply: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .padding(12)
                .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
                .onChange(of: text.wrappedValue) { _, v in
                    if let d = PhotoWidgetEditorMath.parseNumber(v) { apply(d) } else if v.trimmingCharacters(in: .whitespaces).isEmpty { apply(0) }
                }
                .accessibilityLabel(title)
        }
    }

    // MARK: Couleurs et bordures

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Couleurs et bordures", icon: "paintpalette")
            if PhotoWidgetLayoutRules.photoIsBackdrop(config) {
                Text("La photo remplit tout le widget. Ajoute une marge ou une bordure pour voir une couleur de fond.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                if !config.photos.isEmpty {
                    Picker("Fond", selection: $config.style.background) {
                        ForEach(PhotoWidgetBackground.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                swatchRow("Couleur de fond", selection: $config.style.backgroundColor)
                let contrast = PhotoWidgetEditorMath.contrast(config.typography.color, config.style.backgroundColor)
                if config.template != .collage, config.style.background == .color, contrast < 3 {
                    Label("Texte peu lisible sur ce fond. Choisis des couleurs plus différentes.", systemImage: "eye.trianglebadge.exclamationmark")
                        .font(.caption).foregroundStyle(Theme.warning)
                }
            }
            if config.template.usesPhotos {
                slider("Épaisseur de bordure", value: $config.style.borderWidth, range: 0...10, unit: "pt")
                if config.style.borderWidth > 0.5 {
                    swatchRow("Couleur de bordure", selection: $config.style.borderColor)
                }
            }
        }
        .card()
    }

    private func swatchRow(_ title: String, selection: Binding<PhotoWidgetColor>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(Theme.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(PhotoWidgetColor.swatches, id: \.name) { sw in
                        let selected = selection.wrappedValue == sw.value
                        Button { selection.wrappedValue = sw.value } label: {
                            Circle().fill(sw.value.color)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                                .overlay(Circle().stroke(Theme.textPrimary, lineWidth: selected ? 2.5 : 0).padding(-4))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sw.name)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Action

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Quand on touche le widget", icon: "hand.tap")
            Picker("Ouvrir", selection: $config.action.kind) {
                Text("Ce widget dans le studio").tag(PhotoWidgetTapAction.Kind.studio)
                Text("L'accueil de LifeOS").tag(PhotoWidgetTapAction.Kind.home)
                Text("Un outil").tag(PhotoWidgetTapAction.Kind.tool)
            }
            .pickerStyle(.menu)
            if config.action.kind == .tool {
                Picker("Catégorie", selection: $config.action.category) {
                    Text("Choisir").tag("")
                    ForEach(AppCategory.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                .onChange(of: config.action.category) { _, _ in config.action.toolName = "" }
                if let cat = AppCategory(rawValue: config.action.category) {
                    Picker("Outil", selection: $config.action.toolName) {
                        Text("Choisir").tag("")
                        ForEach(cat.tools.map(\.defaultTitle), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                if config.action.toolName.isEmpty {
                    Text("Sans outil choisi, le widget ouvre l'accueil.").font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
    }

    private var dangerSection: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            Label("Supprimer ce widget", systemImage: "trash")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.danger)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassControl(Capsule())
        }
        .buttonStyle(LifeOSPressStyle())
        .disabled(saving)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).foregroundStyle(Theme.textPrimary)
    }

    // MARK: Actions

    private func importPicked(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !importing else { return }
        importing = true
        errorText = nil
        Task {
            var datas: [Data] = []
            var failed = 0
            for item in items {
                if let d = try? await item.loadTransferable(type: Data.self) { datas.append(d) } else { failed += 1 }
            }
            do {
                let refs = try await store.importPhotos(datas)
                importedThisSession += refs.map(\.fileName)
                config.photos += refs
                if datas.count > refs.count || failed > 0 {
                    errorText = "\(failed + datas.count - refs.count) photo(s) n'ont pas pu être lues (photo iCloud non téléchargée ?)."
                }
            } catch {
                errorText = error.localizedDescription
            }
            pickerItems = []
            importing = false
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try store.save(config)
            // Les photos retirees pendant l'edition ne sont plus referencees:
            // `save` les a effacees par le nettoyage.
            onFinish(store.config(id: config.id) ?? config)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func cancel() {
        store.discardDraftFiles(importedThisSession)
        onFinish(nil)
    }

    private func deleteConfig() {
        guard !saving else { return }
        saving = true
        defer { saving = false }
        do {
            try store.delete(original.id)
            store.discardDraftFiles(importedThisSession)
            onFinish(nil)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Petits calculs de l'editeur (purs, testes).
enum PhotoWidgetEditorMath {
    /// "12,5" ou "12.5". nil si ce n'est pas un nombre.
    static func parseNumber(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        guard let d = Double(t), d.isFinite else { return nil }
        return d
    }

    /// Rapport de contraste WCAG entre deux couleurs.
    static func contrast(_ a: PhotoWidgetColor, _ b: PhotoWidgetColor) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
