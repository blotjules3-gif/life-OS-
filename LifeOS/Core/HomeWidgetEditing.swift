import SwiftUI
import UniformTypeIdentifiers

// Reordonner l'accueil comme l'ecran d'accueil iOS: appui long, les blocs
// tremblent, on les glisse, un "−" les retire, "+" les remet, "OK" termine.

// MARK: - Habillage d'un bloc en mode edition

struct HomeWidgetChrome: ViewModifier {
    let widget: HomeWidget
    let editing: Bool
    let isDragged: Bool
    let onRemove: () -> Void
    let onShift: (Int) -> Void
    let onDragStart: () -> Void

    @State private var wobble = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Chaque bloc tremble avec un leger decalage, comme sur iOS: tous en
    /// phase, ca ressemble a un bug d'affichage, pas a un mode edition.
    private var tilt: Double {
        guard editing, !reduceMotion else { return 0 }
        let base = 0.7 + Double((HomeWidget.allCases.firstIndex(of: widget) ?? 0) % 3) * 0.15
        return wobble ? base : -base
    }

    func body(content: Content) -> some View {
        content
            // En edition, un calque transparent recouvre le bloc: il prend le
            // glisser, et les boutons du bloc ne partent plus par accident.
            // Le calque n'existe QUE en edition, donc les appuis longs des
            // lignes de taches gardent leur menu le reste du temps.
            .overlay {
                if editing {
                    Color.white.opacity(0.001)
                        .contentShape(Rectangle())
                        .onDrag {
                            onDragStart()
                            return NSItemProvider(object: widget.rawValue as NSString)
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                if editing {
                    Button(action: onRemove) {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.gray)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    }
                    .offset(x: -8, y: -8)
                    .accessibilityLabel("Retirer \(widget.label)")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .rotationEffect(.degrees(tilt))
            .scaleEffect(isDragged ? 0.96 : 1)
            .opacity(isDragged ? 0.45 : 1)
            .animation(editing && !reduceMotion
                       ? .easeInOut(duration: 0.14).repeatForever(autoreverses: true)
                       : .easeOut(duration: 0.2), value: wobble)
            .animation(.spring(duration: 0.3), value: isDragged)
            .onChange(of: editing, initial: true) { _, on in wobble = on ? !wobble : false }
            .accessibilityActions {
                if editing {
                    Button("Monter") { onShift(-1) }
                    Button("Descendre") { onShift(1) }
                    Button("Retirer") { onRemove() }
                }
            }
    }
}

// MARK: - Glisser pour reordonner

/// Le bloc glisse change de place des qu'il survole un autre bloc, pas au
/// lacher: c'est ce qui donne l'effet iOS ou les autres s'ecartent.
struct HomeDropDelegate: DropDelegate {
    let target: HomeWidget
    @Binding var raw: String
    @Binding var dragged: HomeWidget?

    func dropEntered(info: DropInfo) {
        guard let d = dragged, d != target else { return }
        var layout = HomeLayout.parse(raw)
        layout.move(d, to: target)
        withAnimation(.spring(duration: 0.3)) { raw = layout.raw }
        Haptics.soft()
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

/// Lache hors d'un bloc: sans ce filet, le bloc glisse resterait
/// semi-transparent jusqu'a la fin du mode edition.
struct HomeDropCleanup: DropDelegate {
    @Binding var dragged: HomeWidget?
    func performDrop(info: DropInfo) -> Bool { dragged = nil; return true }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}

// MARK: - Barre du mode edition

struct HomeEditBar: View {
    let hiddenCount: Int
    let onAdd: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack {
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(.thinMaterial, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if hiddenCount > 0 {
                            Text("\(hiddenCount)")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .padding(4).background(Color.red, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
            }
            .accessibilityLabel("Ajouter un bloc")
            Spacer()
            Button("OK", action: onDone)
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(.thinMaterial, in: Capsule())
        }
        .foregroundStyle(Theme.textPrimary)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Galerie: remettre un bloc retire

struct HomeWidgetGallery: View {
    @Binding var raw: String
    @Environment(\.dismiss) private var dismiss

    private var layout: HomeLayout { HomeLayout.parse(raw) }

    var body: some View {
        NavigationStack {
            List {
                if layout.hidden.isEmpty {
                    Text("Tous les blocs sont déjà sur l'accueil.")
                        .foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(layout.hidden) { w in
                            Button {
                                var l = layout; l.show(w)
                                withAnimation(.spring(duration: 0.3)) { raw = l.raw }
                                Haptics.tap()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: w.icon)
                                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Theme.accent.gradient,
                                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    Text(w.label).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(.green)
                                }
                            }
                        }
                    } header: {
                        Text("Blocs retirés")
                    } footer: {
                        Text("Un bloc ajouté arrive en bas de l'accueil. Déplace-le ensuite où tu veux.")
                    }
                }
                Section {
                    Button("Revenir à l'ordre d'origine", role: .destructive) {
                        withAnimation(.spring(duration: 0.3)) { raw = "" }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Ajouter un bloc").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Bloc vide en mode edition

/// Certains blocs n'affichent rien quand ils n'ont rien a montrer (pas de
/// raccourci, pas d'habitude). En edition ils doivent rester visibles, sinon
/// impossible de les deplacer ou de les retirer.
struct HomeWidgetPlaceholder: View {
    let widget: HomeWidget
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: widget.icon)
            Text(widget.label).font(.subheadline.weight(.semibold))
            Spacer()
            Text("vide pour l'instant").font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}
