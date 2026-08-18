import SwiftUI

/// Écran de personnalisation du coach : ton, longueur, niveau technique,
/// sujets à éviter, lecture vocale. Toutes les prefs sont chargées à chaque
/// send() via `CoachPreferences.current()`.
struct CoachPreferencesView: View {

    @AppStorage(AppStorageKeys.coachTone) private var toneRaw = CoachPreferences.Tone.empathique.rawValue
    @AppStorage(AppStorageKeys.coachLength) private var lengthRaw = CoachPreferences.Length.normal.rawValue
    @AppStorage(AppStorageKeys.coachExpertiseLevel) private var expertiseRaw = CoachPreferences.ExpertiseLevel.intermediaire.rawValue
    @AppStorage(AppStorageKeys.coachAvoidTopics) private var avoidTopics = ""
    @AppStorage(AppStorageKeys.coachTTSEnabled) private var ttsEnabled = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                toneSection
                lengthSection
                expertiseSection
                avoidSection
                voiceSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Ton coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var toneSection: some View {
        Section {
            ForEach(CoachPreferences.Tone.allCases) { tone in
                pickerRow(
                    label: tone.label,
                    subtitle: shortDescription(for: tone),
                    isSelected: tone.rawValue == toneRaw
                ) { toneRaw = tone.rawValue; Haptics.tap() }
            }
        } header: {
            Text("Ton du coach")
        } footer: {
            Text("Choisis l'attitude que tu préfères. Tu peux la changer à tout moment.")
        }
    }

    private var lengthSection: some View {
        Section {
            ForEach(CoachPreferences.Length.allCases) { length in
                pickerRow(
                    label: length.label,
                    subtitle: nil,
                    isSelected: length.rawValue == lengthRaw
                ) { lengthRaw = length.rawValue; Haptics.tap() }
            }
        } header: {
            Text("Longueur des réponses")
        }
    }

    private var expertiseSection: some View {
        Section {
            ForEach(CoachPreferences.ExpertiseLevel.allCases) { level in
                pickerRow(
                    label: level.label,
                    subtitle: shortDescription(for: level),
                    isSelected: level.rawValue == expertiseRaw
                ) { expertiseRaw = level.rawValue; Haptics.tap() }
            }
        } header: {
            Text("Niveau technique")
        }
    }

    private var avoidSection: some View {
        Section {
            TextField("Ex: crypto, régime, politique…", text: $avoidTopics, axis: .vertical)
                .lineLimit(2...4)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        } header: {
            Text("Sujets à éviter")
        } footer: {
            Text("Sépare par des virgules. Le coach évitera ces sujets ou les redirigera vers un pro.")
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle(isOn: $ttsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lecture vocale")
                    Text("Ajoute un bouton pour écouter chaque réponse à haute voix")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Voix")
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color(hex: 0x4CC38A))
                VStack(alignment: .leading, spacing: 2) {
                    Text("100 % local").font(.subheadline.weight(.semibold))
                    Text("Tes messages et tes préférences ne quittent jamais ton iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pickerRow(label: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private func shortDescription(for tone: CoachPreferences.Tone) -> String {
        switch tone {
        case .pose: return "Calme et mesuré"
        case .motivant: return "Énergique, coach sportif"
        case .cash: return "Direct, sans détour"
        case .empathique: return "Doux, à l'écoute"
        }
    }

    private func shortDescription(for level: CoachPreferences.ExpertiseLevel) -> String {
        switch level {
        case .vulgarise: return "Mots simples, analogies"
        case .intermediaire: return "Technique quand ça compte"
        case .expert: return "Chiffres, ratios, mécanismes"
        }
    }
}

#Preview {
    CoachPreferencesView()
}
