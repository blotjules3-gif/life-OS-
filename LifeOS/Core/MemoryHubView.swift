import SwiftUI
import SwiftData

/// Écran "Mémoire du coach" — liste éditable de ce que le coach sait de toi.
///
/// - Ajoutée automatiquement quand tu parles au coach (via `MemoryExtractor`)
/// - Éditable manuellement (pin/unpin, delete, ajout)
/// - Priorité : pinnées d'abord, puis récentes
/// - Toute suppression est immédiate (pas de corbeille)
struct MemoryHubView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \MemoryEntry.created, order: .reverse) private var all: [MemoryEntry]
    @State private var showAdd = false
    @State private var newContent = ""
    @State private var newCategory = "fait"

    private var pinned: [MemoryEntry] { all.filter { $0.isPinned } }
    private var unpinned: [MemoryEntry] { all.filter { !$0.isPinned } }
    private let categories = ["objectif", "habitude", "préférence", "fait", "contrainte"]

    var body: some View {
        List {
            Section {
                Text("Ce que ton coach sait de toi. Chaque fois que tu lui parles, il capture les faits durables (objectifs, préférences, habitudes) pour te donner des conseils cohérents dans le temps.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            if !pinned.isEmpty {
                Section("Épinglées") {
                    ForEach(pinned) { row($0) }
                }
            }

            if !unpinned.isEmpty {
                Section("Récentes") {
                    ForEach(unpinned) { row($0) }
                }
            }

            if all.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Aucune mémoire pour l'instant.")
                            .font(.subheadline)
                        Text("Parle à ton coach — il va commencer à retenir ce qui compte pour toi.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Mémoire du coach")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une mémoire")
            }
        }
        .sheet(isPresented: $showAdd) { addSheet }
    }

    private func row(_ m: MemoryEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(m.content)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: 6) {
                    Text(m.category)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                    Text(m.created, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                ctx.delete(m)
                do { try ctx.save() } catch { AppLog.data.error("delete memory failed: \(error.localizedDescription, privacy: .public)") }
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                m.isPinned.toggle()
                do { try ctx.save() } catch { AppLog.data.error("pin memory failed: \(error.localizedDescription, privacy: .public)") }
            } label: {
                Label(m.isPinned ? "Détacher" : "Épingler",
                      systemImage: m.isPinned ? "pin.slash" : "pin")
            }
            .tint(Theme.accent)
        }
    }

    @ViewBuilder private var addSheet: some View {
        NavigationStack {
            Form {
                Section("Nouveau souvenir") {
                    TextField("Ex : je veux courir 3× par semaine", text: $newContent, axis: .vertical)
                        .lineLimit(2...5)
                    Picker("Catégorie", selection: $newCategory) {
                        ForEach(categories, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
            }
            .navigationTitle("Ajouter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { resetAdd() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.count >= 3 else { return }
                        ctx.insert(MemoryEntry(
                            content: trimmed,
                            category: newCategory,
                            source: "profil",
                            created: .now,
                            isPinned: false
                        ))
                        do { try ctx.save() } catch { AppLog.data.error("insert memory failed: \(error.localizedDescription, privacy: .public)") }
                        resetAdd()
                    }
                    .disabled(newContent.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
        }
    }

    private func resetAdd() {
        newContent = ""
        newCategory = "fait"
        showAdd = false
    }
}
