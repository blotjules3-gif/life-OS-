import SwiftUI
import Translation

// MARK: - Traduction on-device (framework Apple Translation, gratuit, hors-ligne)

private struct TransLang: Identifiable, Hashable {
    let code: String
    let flag: String
    let name: String
    var id: String { code }
    var language: Locale.Language { Locale.Language(identifier: code) }
}

private let transLangs: [TransLang] = [
    .init(code: "fr", flag: "🇫🇷", name: "Français"),
    .init(code: "en", flag: "🇬🇧", name: "Anglais"),
    .init(code: "es", flag: "🇪🇸", name: "Espagnol"),
    .init(code: "de", flag: "🇩🇪", name: "Allemand"),
    .init(code: "it", flag: "🇮🇹", name: "Italien"),
    .init(code: "pt", flag: "🇵🇹", name: "Portugais"),
    .init(code: "nl", flag: "🇳🇱", name: "Néerlandais"),
    .init(code: "ru", flag: "🇷🇺", name: "Russe"),
    .init(code: "zh", flag: "🇨🇳", name: "Chinois"),
    .init(code: "ja", flag: "🇯🇵", name: "Japonais"),
    .init(code: "ko", flag: "🇰🇷", name: "Coréen"),
    .init(code: "ar", flag: "🇸🇦", name: "Arabe"),
]

struct TranslationView: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            TranslatorScreen()
        } else {
            ZStack {
                Theme.background
                VStack(spacing: 12) {
                    Image(systemName: "character.bubble").font(.system(size: 48)).foregroundStyle(.travelTint)
                    Text("Traduction").font(.title3.bold())
                    Text("La traduction hors-ligne nécessite iOS 18 ou plus récent.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }.padding()
            }
            .navigationTitle("Traduction").navigationBarTitleDisplayMode(.inline)
        }
    }
}

@available(iOS 18.0, *)
private struct TranslatorScreen: View {
    @State private var source = "fr"
    @State private var target = "en"
    @State private var input = ""
    @State private var output = ""
    @State private var config: TranslationSession.Configuration?
    @State private var busy = false
    @State private var errorMsg: String?
    @FocusState private var focused: Bool

    private func lang(_ c: String) -> TransLang { transLangs.first { $0.code == c } ?? transLangs[0] }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    langBar
                    inputCard
                    translateButton
                    if busy { ProgressView("Traduction…").padding(.top, 4) }
                    if let errorMsg {
                        Label(errorMsg, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline).foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !output.isEmpty { outputCard }
                    Text("100% sur l'appareil. Télécharge une langue pour l'utiliser hors connexion.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("Traduction").navigationBarTitleDisplayMode(.inline)
        .translationTask(config) { session in
            do {
                busy = true; errorMsg = nil
                try await session.prepareTranslation()
                let response = try await session.translate(input)
                output = response.targetText
            } catch {
                errorMsg = "Langue indisponible. Touche « Télécharger » puis réessaie."
            }
            busy = false
        }
    }

    private var langBar: some View {
        HStack(spacing: 10) {
            langMenu(selection: $source)
            Button {
                let t = source; source = target; target = t
                if !output.isEmpty { input = output; output = "" }
                Haptics.soft()
            } label: {
                Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2).foregroundStyle(.travelTint)
            }
            langMenu(selection: $target)
        }
    }
    private func langMenu(selection: Binding<String>) -> some View {
        Menu {
            ForEach(transLangs) { l in
                Button { selection.wrappedValue = l.code } label: { Text("\(l.flag)  \(l.name)") }
            }
        } label: {
            HStack(spacing: 6) {
                Text(lang(selection.wrappedValue).flag)
                Text(lang(selection.wrappedValue).name).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(Theme.textPrimary)
        }
    }

    private var inputCard: some View {
        ZStack(alignment: .topLeading) {
            if input.isEmpty {
                Text("Écris ou colle ton texte…").foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
            TextEditor(text: $input).focused($focused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10).padding(.vertical, 6).frame(minHeight: 120)
        }
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    private var translateButton: some View {
        Button {
            focused = false
            errorMsg = nil; output = ""
            // (re)crée la configuration → déclenche translationTask
            config = .init(source: lang(source).language, target: lang(target).language)
        } label: {
            Label("Traduire", systemImage: "globe").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.travelTint.gradient, in: RoundedRectangle(cornerRadius: Theme.radiusSmall)).foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
    }

    private var outputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(lang(target).flag) \(lang(target).name)").font(.caption.weight(.semibold)).foregroundStyle(.travelTint)
                Spacer()
                Button { UIPasteboard.general.string = output; Haptics.tap() } label: {
                    Image(systemName: "doc.on.doc").font(.subheadline).foregroundStyle(.travelTint)
                }
            }
            Text(output).font(.title3.weight(.medium)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
