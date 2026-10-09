import SwiftUI
import UIKit

// Studio photo: cree, previsualise, enregistre, duplique, modifie et supprime les
// configurations du widget photo. Chaque widget pose sur l'ecran d'accueil en
// choisit une (touche longue, Modifier).
//
// Ecran pousse dans la pile du parent (Profil, lien profond): il ne possede pas de
// NavigationStack. L'editeur s'ouvre en feuille, qui a la sienne.

struct PhotoWidgetStudioView: View {
    /// Configuration a ouvrir directement (lien `lifeos://photo-widget?id=`).
    let configID: UUID?

    init(configID: UUID? = nil) { self.configID = configID }

    @ObservedObject private var store = PhotoWidgetStore.shared
    @StateObject private var thumbs = PhotoWidgetThumbCache()
    @State private var editing: PhotoWidgetDraft?
    @State private var confirmDelete: PhotoWidgetConfig?
    @State private var banner: String?
    @State private var errorText: String?
    @State private var busy = false
    @State private var handledInitialID = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if let banner { notice(banner, icon: "checkmark.circle.fill", tint: Theme.success) }
                    if let errorText { notice(errorText, icon: "exclamationmark.triangle.fill", tint: Theme.warning) }
                    templatesSection
                    myWidgetsSection
                    PhotoWidgetLimitsFootnote(usedBytes: store.usedBytes)
                }
                .padding(Theme.pad)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Widgets photo")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { draft in
            PhotoWidgetEditorView(draft: draft, store: store, thumbs: thumbs) { saved in
                editing = nil
                if let saved {
                    show(banner: "« \(saved.name) » est enregistré. Pour l'afficher : touche longuement l'écran d'accueil, puis +, cherche LifeOS et choisis Widget photo. Touche ensuite le widget pour choisir « \(saved.name) ».")
                }
            }
        }
        .confirmationDialog("Supprimer ce widget ?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
                            titleVisibility: .visible, presenting: confirmDelete) { c in
            Button("Supprimer « \(c.name) »", role: .destructive) { delete(c) }
            Button("Annuler", role: .cancel) {}
        } message: { _ in
            Text("Ses photos seront effacées de l'espace des widgets. Les widgets posés qui l'affichaient te demanderont d'en choisir un autre. Tes photos d'origine ne sont pas touchées.")
        }
        .onAppear {
            store.reload()
            store.cleanup()
            openInitialIfNeeded()
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Widgets photo").font(Theme.fontTitle).foregroundStyle(Theme.textPrimary)
            Text("Tes photos, une note, un compte à rebours ou un objectif sur l'écran d'accueil. Chaque widget posé affiche le modèle que tu choisis ici.")
                .font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Nouveau", subtitle: "Choisis un modèle")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(PhotoWidgetTemplate.allCases) { t in
                    Button { editing = PhotoWidgetDraft(config: .makeDefault(t), isNew: true) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: t.icon).font(.title3.weight(.semibold))
                                .foregroundStyle(AppCategory.productivity.tint)
                            Text(t.title).font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(t.subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .padding(14)
                        .glassControl(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                    }
                    .buttonStyle(LifeOSPressStyle())
                    .accessibilityLabel("Nouveau widget \(t.title)")
                    .accessibilityHint(t.subtitle)
                }
            }
        }
    }

    @ViewBuilder
    private var myWidgetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Mes widgets", subtitle: store.configs.isEmpty ? nil : "\(store.configs.count) enregistré\(store.configs.count > 1 ? "s" : "")")
            if store.configs.isEmpty {
                EmptyState(icon: "photo.on.rectangle.angled", title: "Aucun widget photo",
                           message: "Choisis un modèle ci-dessus, ajoute tes photos ou ton texte, puis enregistre. Il apparaîtra ici et dans la liste des widgets de LifeOS.")
                    .card()
            } else {
                ForEach(store.configs.sorted { $0.updatedAt > $1.updatedAt }) { c in
                    configCard(c)
                }
            }
        }
    }

    private func configCard(_ c: PhotoWidgetConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label(c.name, systemImage: c.template.icon)
                    .font(.headline).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Text(c.template.title).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    PhotoWidgetPreview(config: c, size: .small, thumbs: thumbs, scale: 0.7)
                    PhotoWidgetPreview(config: c, size: .medium, thumbs: thumbs, scale: 0.7)
                }
            }
            if let missing = c.missingContent {
                Label(missing, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warning)
            }
            HStack(spacing: 10) {
                actionButton("Modifier", icon: "pencil") { editing = PhotoWidgetDraft(config: c, isNew: false) }
                actionButton("Dupliquer", icon: "plus.square.on.square") { duplicate(c) }
                actionButton("Supprimer", icon: "trash", role: .destructive) { confirmDelete = c }
            }
        }
        .card()
        .contextMenu {
            Button { editing = PhotoWidgetDraft(config: c, isNew: false) } label: { Label("Modifier", systemImage: "pencil") }
            Button { duplicate(c) } label: { Label("Dupliquer", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { confirmDelete = c } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func actionButton(_ title: String, icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(role == .destructive ? Theme.danger : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassControl(Capsule())
        }
        .buttonStyle(LifeOSPressStyle())
        .disabled(busy)
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint).accessibilityHidden(true)
            Text(text).font(.footnote).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { banner = nil; errorText = nil } label: {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Fermer")
            .foregroundStyle(Theme.textSecondary)
        }
        .padding(.leading, 12)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
    }

    // MARK: Actions

    private func show(banner text: String) {
        errorText = nil
        if reduceMotion { banner = text } else { withAnimation(.easeOut(duration: 0.2)) { banner = text } }
    }

    private func duplicate(_ c: PhotoWidgetConfig) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let copy = try store.duplicate(c.id)
            show(banner: "Copie créée : « \(copy.name) ».")
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ c: PhotoWidgetConfig) {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try store.delete(c.id)
            show(banner: "« \(c.name) » est supprimé.")
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openInitialIfNeeded() {
        guard !handledInitialID else { return }
        handledInitialID = true
        if let configID {
            if let c = store.config(id: configID) {
                editing = PhotoWidgetDraft(config: c, isNew: false)
            } else {
                errorText = "Ce widget a été supprimé. Choisis-en un autre ci-dessous, ou crée-en un nouveau."
            }
            return
        }
        #if DEBUG
        if let raw = DebugLaunchFlags.value("-photoStudioNew"), let t = PhotoWidgetTemplate(rawValue: raw) {
            editing = PhotoWidgetDraft(config: .makeDefault(t), isNew: true)
        } else if DebugLaunchFlags.has("-photoStudioEdit"), let c = store.configs.first {
            editing = PhotoWidgetDraft(config: c, isNew: false)
        }
        #endif
    }
}

/// Brouillon ouvert dans l'editeur.
struct PhotoWidgetDraft: Identifiable {
    var id: UUID { config.id }
    var config: PhotoWidgetConfig
    var isNew: Bool
}

// MARK: - Apercu a la taille reelle

/// Le widget tel qu'il s'affichera, dessine par le MEME code que l'extension.
struct PhotoWidgetPreview: View {
    let config: PhotoWidgetConfig
    let size: PhotoWidgetSize
    @ObservedObject var thumbs: PhotoWidgetThumbCache
    /// 1 = taille reelle en points.
    var scale: CGFloat = 1
    var now: Date = Date()

    private var refs: [PhotoRef] {
        let count = config.template == .collage ? config.style.layout.slots : 1
        return PhotoWidgetSchedule.photos(config.rotatingPhotos, offset: 0, count: count)
    }

    var body: some View {
        let images = refs.compactMap { thumbs.image(for: $0) }
        let pts = size.points
        let shape = RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
        ZStack {
            if size == .rectangular {
                // Ecran verrouille: iOS impose une seule teinte claire sur fond sombre.
                Color.black.opacity(0.55)
                PhotoWidgetContentView(state: .config(config, photoOffset: 0), images: [], size: size, now: now)
                    .foregroundStyle(.white)
                    .padding(8)
                    .environment(\.colorScheme, .dark)
            } else {
                PhotoWidgetBackdrop(config: config, firstImage: images.first)
                PhotoWidgetContentView(state: .config(config, photoOffset: 0), images: images, size: size, now: now)
            }
        }
        .frame(width: pts.width, height: pts.height)
        .clipShape(shape)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: pts.width * scale, height: pts.height * scale, alignment: .topLeading)
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .task(id: refs.map { "\($0.fileName)|\($0.crop)" }.joined(separator: ",")) {
            await thumbs.load(refs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Aperçu \(size.title.lowercased()) de \(config.name)")
    }
}

/// Petites images deja recadrees pour les apercus. Lues reduites, hors du fil principal.
@MainActor
final class PhotoWidgetThumbCache: ObservableObject {
    @Published private var images: [String: UIImage] = [:]

    nonisolated static func key(_ ref: PhotoRef) -> String { "\(ref.fileName)|\(ref.crop.x),\(ref.crop.y),\(ref.crop.width),\(ref.crop.height)" }

    func image(for ref: PhotoRef) -> UIImage? { images[Self.key(ref)] }

    func load(_ refs: [PhotoRef], maxPixel: CGFloat = 900) async {
        let missing = refs.filter { images[Self.key($0)] == nil }
        guard !missing.isEmpty else { return }
        let loaded: [(String, UIImage)] = await Task.detached(priority: .userInitiated) {
            missing.compactMap { ref in PhotoWidgetImage.load(ref, maxPixel: maxPixel).map { (Self.key(ref), $0) } }
        }.value
        // Borne simple: on repart de zero au-dela de 40 images en memoire.
        if images.count > 40 { images.removeAll() }
        for (k, img) in loaded { images[k] = img }
    }

    /// Image entiere (non recadree), pour le recadrage.
    nonisolated static func loadFull(_ fileName: String, maxPixel: CGFloat = 1000) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            PhotoWidgetImage.load(PhotoRef(fileName: fileName), maxPixel: maxPixel)
        }.value
    }
}

// MARK: - Limites du systeme, dites franchement

struct PhotoWidgetLimitsFootnote: View {
    let usedBytes: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ce que iOS permet", systemImage: "info.circle")
                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Group {
                Text("Tailles : petit, moyen et grand sur l'écran d'accueil. Sur l'écran verrouillé, seulement les modèles Note, Compte à rebours et Objectif, en une seule teinte.")
                Text("Mises à jour : iOS décide du moment exact. La rotation des photos se fait au mieux toutes les heures, souvent un peu plus tard. Le compte à rebours change à minuit.")
                Text("Pas d'animation ni de bouton dans ce widget : un appui ouvre LifeOS sur l'action choisie. En mode teinté ou en veille (StandBy), iOS peut retirer le fond et passer les photos en une seule teinte.")
                Text("Les photos sont réduites (1000 pixels au plus) et gardées sur ton iPhone, sans réseau. Espace utilisé : \(ByteCountFormatter.string(fromByteCount: usedBytes, countStyle: .file)) sur 60 Mo.")
            }
            .font(.caption).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous), .nested)
    }
}
