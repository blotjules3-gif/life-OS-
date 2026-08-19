import SwiftUI
import SwiftData

/// Vue d'audit du profil utilisateur — liste tous les `ProfileField` extraits
/// et permet à l'utilisateur de :
/// - voir la valeur, la confiance, la source
/// - corriger manuellement (upsert source=.manual = protégé du LLM)
/// - consulter l'historique de révisions
/// - supprimer un field
///
/// Accessible depuis le menu ellipsis du chat ("Voir mon profil").
struct ProfileFieldsView: View {

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProfileField.updatedAt, order: .reverse) private var fields: [ProfileField]

    @State private var editingField: ProfileField?
    @State private var showingHistoryFor: ProfileField?

    private var grouped: [(category: String, items: [ProfileField])] {
        let dict = Dictionary(grouping: fields, by: { $0.category })
        return dict
            .map { (category: $0.key, items: $0.value.sorted { $0.updatedAt > $1.updatedAt }) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        NavigationStack {
            Group {
                if fields.isEmpty { emptyState } else { list }
            }
            .navigationTitle("Ton profil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(item: $editingField) { field in
                EditProfileFieldSheet(field: field)
            }
            .sheet(item: $showingHistoryFor) { field in
                ProfileFieldHistorySheet(field: field)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Ton profil est vide")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Parle au coach ou utilise le raccourci « Ajouter au profil » pour remplir automatiquement.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(grouped, id: \.category) { group in
                Section(header: Text(categoryLabel(group.category).uppercased()).font(.caption)) {
                    ForEach(group.items) { field in
                        row(field)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ field: ProfileField) -> some View {
        let spec = ProfileFieldCatalog.all[field.fieldID]
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(spec?.displayName ?? field.fieldID)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(field.valueString)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                    if let unit = spec?.unit {
                        Text(unit).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    sourceBadge(field.source)
                    confidenceBadge(field.confidence)
                    if !field.history.isEmpty {
                        Text("· \(field.history.count) révisions")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                editingField = field
            } label: {
                Label("Corriger", systemImage: "pencil")
            }
            if !field.history.isEmpty {
                Button {
                    showingHistoryFor = field
                } label: {
                    Label("Historique (\(field.history.count))", systemImage: "clock.arrow.circlepath")
                }
            }
            Divider()
            Button(role: .destructive) {
                delete(field)
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }

    private func sourceBadge(_ source: String) -> some View {
        let (label, icon): (String, String) = {
            switch source {
            case "chat":      return ("chat", "bubble.left.fill")
            case "voice":     return ("voix", "waveform")
            case "quiz":      return ("quiz", "questionmark.circle.fill")
            case "shortcut":  return ("raccourci", "sparkle.magnifyingglass")
            case "manual":    return ("manuel", "pencil.circle.fill")
            case "migration": return ("migré", "arrow.triangle.2.circlepath")
            default:          return (source, "info.circle")
            }
        }()
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9))
            Text(label).font(.caption2)
        }
        .foregroundStyle(.secondary)
    }

    private func confidenceBadge(_ confidence: Double) -> some View {
        let pct = Int(confidence * 100)
        let color: Color = confidence >= 0.9 ? .green : (confidence >= 0.7 ? .orange : .red)
        return Text("\(pct)%")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(color)
    }

    private func categoryLabel(_ raw: String) -> String {
        AppCategory(rawValue: raw)?.title ?? raw.capitalized
    }

    private func delete(_ field: ProfileField) {
        guard let ctx = field.modelContext else { return }
        ctx.delete(field)
        LifeOSTry(try ctx.save(), context: "ProfileFieldsView delete \(field.fieldID)", category: AppLog.data)
    }
}

// MARK: - Edit sheet

private struct EditProfileFieldSheet: View {
    let field: ProfileField
    @Environment(\.dismiss) private var dismiss
    @State private var newValue: String

    init(field: ProfileField) {
        self.field = field
        _newValue = State(initialValue: field.valueString)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let spec = ProfileFieldCatalog.all[field.fieldID] {
                        LabeledContent("Champ", value: spec.displayName)
                        if let unit = spec.unit {
                            LabeledContent("Unité", value: unit)
                        }
                    }
                    TextField("Nouvelle valeur", text: $newValue)
                        .autocorrectionDisabled()
                }
                Section(footer: Text("Une correction manuelle protège la valeur : le coach ne pourra pas l'écraser sans ton accord.")) {
                    Button("Enregistrer") { save(); dismiss() }
                        .disabled(newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Corriger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let spec = ProfileFieldCatalog.all[field.fieldID] else { return }
        let typed: Any = {
            switch spec.valueType {
            case .int:    return Int(newValue) ?? 0
            case .double: return Double(newValue.replacingOccurrences(of: ",", with: ".")) ?? 0.0
            case .bool:   return newValue.lowercased() == "true" || newValue == "1"
            default:      return newValue
            }
        }()
        _ = ProfileStore.shared.upsert(
            field.fieldID,
            value: typed,
            source: .manual,
            confidence: 1.0,
            reason: "user_manual_correction",
            allowOverwriteManual: true
        )
        UserContextBuilder.shared.invalidateCache()
    }
}

// MARK: - History sheet

private struct ProfileFieldHistorySheet: View {
    let field: ProfileField
    @Environment(\.dismiss) private var dismiss

    private var sortedRevisions: [ProfileFieldRevision] {
        field.history.sorted { $0.changedAt > $1.changedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Valeur actuelle")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.valueString).font(.headline)
                        Text("\(field.source) · \(Int(field.confidence * 100))% · \(field.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section(header: Text("Révisions précédentes")) {
                    if sortedRevisions.isEmpty {
                        Text("Aucune").font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(sortedRevisions) { rev in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rev.previousValueString).font(.subheadline)
                                Text("\(rev.previousSource) · \(rev.changedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if let reason = rev.reason {
                                    Text(reason).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(ProfileFieldCatalog.all[field.fieldID]?.displayName ?? field.fieldID)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
