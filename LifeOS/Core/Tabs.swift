import SwiftUI

// MARK: - Photo / Scanner

struct CameraView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ToolRow(icon: "fork.knife", title: "Scanner un plat",
                            subtitle: "Estimer les calories par photo", tint: Color(hex: 0x4CC38A)) { PhotoCalorieScaffold() }
                    ToolRow(icon: "barcode.viewfinder", title: "Scanner un code-barres",
                            subtitle: "Note santé + alternative", tint: Color(hex: 0x4CC38A)) { ScanProductView() }
                    ToolRow(icon: "doc.viewfinder", title: "Scanner un document",
                            subtitle: "Coffre-fort + OCR", tint: Color(hex: 0x8A93A8)) { DocScanScaffold() }
                } header: {
                    Text("Capture")
                } footer: {
                    Text("Sur un vrai iPhone, ces outils ouvrent l'appareil photo. Sur simulateur, la caméra n'est pas disponible.")
                }
            }
            .navigationTitle("Scanner")
        }
    }
}


struct ProfileCustomizerSheet: View {
    @Binding var hiddenRaw: String
    @Environment(\.dismiss) private var dismiss

    private var hidden: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }
    private func toggle(_ id: String) {
        var s = Set(hiddenRaw.split(separator: ",").map(String.init))
        if s.contains(id) { s.remove(id) } else { s.insert(id) }
        hiddenRaw = s.joined(separator: ",")
    }
    private var visibleCount: Int { sections.count - hidden.count }

    private let sections: [(id: String, label: String, sub: String, icon: String, color: Color)] = [
        ("hero",     "Score",          "Carte principale",   "star.fill",           Color(hex: 0x00D4B4)),
        ("tasks",    "Tâches",         "Ce qu'il te reste",  "checklist",           Color.accentColor),
        ("briefing", "Briefing",       "Rappel du matin",    "sunrise.fill",        Color.orange),
        ("memories", "Mémoire",        "Ce que je retiens",  "brain",               Color.accentColor),
        ("stats",    "Stats",          "Pas · eau · kcal",   "chart.bar.fill",      Color(hex: 0xF1746C)),
        ("habits",   "Habitudes",      "Suivi & protéines",  "checkmark.seal.fill", Color.accentColor),
        ("actions",  "Actions",        "Raccourcis rapides", "bolt.fill",           Color(hex: 0x3CB2E0)),
        ("wakeup",   "Réveil",         "Alarme & briefing",  "alarm.fill",          Color(hex: 0xE07B3C)),
        ("tip",      "Citation",       "Inspiration du jour","quote.bubble.fill",   Color.accentColor),
        ("settings", "Paramètres",     "Santé · objectifs",  "slider.horizontal.3", Color(hex: 0x8A93A8)),
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Compteur
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mon profil")
                                .font(.system(size: 22, weight: .bold))
                            Text("\(visibleCount) section\(visibleCount > 1 ? "s" : "") affichée\(visibleCount > 1 ? "s" : "")")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Tout afficher") {
                            withAnimation { hiddenRaw = "" }
                            Haptics.tap()
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                    // Grille 2 colonnes
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(sections, id: \.id) { s in
                            let isVisible = !hidden.contains(s.id)
                            Button {
                                withAnimation(.spring(duration: 0.25, bounce: 0.3)) { toggle(s.id) }
                                Haptics.tap()
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: s.icon)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(isVisible ? .white : s.color.opacity(0.5))
                                            .frame(width: 34, height: 34)
                                            .background(
                                                isVisible ? s.color : s.color.opacity(0.12),
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            )
                                        Spacer()
                                        Image(systemName: isVisible ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundStyle(isVisible ? s.color : Color.secondary.opacity(0.3))
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.label)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isVisible ? .primary : .secondary)
                                        Text(s.sub)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(isVisible ? Theme.card : Color(.systemBackground).opacity(0.5))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                .stroke(isVisible ? s.color.opacity(0.25) : Color.secondary.opacity(0.1), lineWidth: 1.5)
                                        )
                                )
                                .scaleEffect(isVisible ? 1.0 : 0.97)
                                .opacity(isVisible ? 1.0 : 0.6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("Appuie sur une carte pour afficher ou masquer la section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }
}
