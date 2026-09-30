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
    // Le framework Translation existe aussi sur Mac (Catalyst 26+). Avant, la
    // branche Mac etait exclue par un #if et affichait "iOS 18 requis" sur un
    // Mac a jour: un traducteur absent, avec un faux motif.
    var body: some View {
        if #available(iOS 18.0, macCatalyst 26.0, *) {
            TranslatorScreen()
        } else {
            fallbackView
        }
    }

    #if targetEnvironment(macCatalyst)
    private static let requirement = "La traduction hors ligne d'Apple demande macOS 26 ou plus récent sur Mac."
    #else
    private static let requirement = "La traduction hors ligne d'Apple demande iOS 18 ou plus récent."
    #endif

    private var fallbackView: some View {
        ZStack {
            Theme.background
            VStack(spacing: 12) {
                Image(systemName: "character.bubble").font(.system(size: 48)).foregroundStyle(.travelTint)
                Text("Traduction").font(.title3.bold())
                Text(Self.requirement)
                    .font(.subheadline).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            }.padding()
        }
        .navigationTitle("Traduction").navigationBarTitleDisplayMode(.inline)
    }
}

@available(iOS 18.0, macCatalyst 26.0, *)
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
                            .font(.subheadline).foregroundStyle(Theme.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12).background(Theme.warning.opacity(0.20), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if !output.isEmpty { outputCard }
                    Text("Traduction faite sur l'appareil par Apple. La première fois, le système peut demander de télécharger la langue.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
        .navigationTitle("Traduction").navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .onAppear {
            if let text = DebugLaunchFlags.value("-translateProbe") {
                input = text
                config = .init(source: lang("fr").language, target: lang("en").language)
            }
        }
        #endif
        .translationTask(config) { session in
            do {
                busy = true; errorMsg = nil
                try await session.prepareTranslation()
                let response = try await session.translate(input)
                output = response.targetText
                #if DEBUG
                Self.writeProbe("OK \(input) -> \(output)")
                #endif
            } catch {
                #if DEBUG
                Self.writeProbe("ERREUR \(error)")
                #endif
                // Il n'y a pas de bouton "Telecharger" dans cet ecran: le systeme
                // propose lui meme le telechargement au premier essai.
                errorMsg = "Traduction impossible pour cette paire de langues. Si le système a proposé de télécharger la langue, accepte puis réessaie. (\(error.localizedDescription))"
            }
            busy = false
        }
    }

    #if DEBUG
    /// `-translateProbe "<texte>"`: traduit fr -> en au lancement et ecrit le
    /// resultat dans Documents/translateprobe.txt. Sert a PROUVER la traduction
    /// sur Mac, ou la capture d'ecran est bloquee sur ce poste.
    static func writeProbe(_ line: String) {
        guard DebugLaunchFlags.value("-translateProbe") != nil else { return }
        try? line.write(to: AppPaths.documents.appendingPathComponent("translateprobe.txt"), atomically: true, encoding: .utf8)
    }
    #endif

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
            .raisedSurface(RoundedRectangle(cornerRadius: 12), .nested).foregroundStyle(Theme.textPrimary)
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
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
        .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
}
