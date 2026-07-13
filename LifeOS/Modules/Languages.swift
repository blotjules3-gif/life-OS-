import SwiftUI

// MARK: - Langues : vocabulaire en répétition espacée (Leitner), 100% local

struct LangPack: Identifiable {
    let id: String        // code langue
    let flag: String
    let name: String
    let words: [(String, String)]   // (français, langue cible)
}

private let langPacks: [LangPack] = [
    LangPack(id: "en", flag: "🇬🇧", name: "Anglais", words: [
        ("Bonjour", "Hello"), ("Merci", "Thank you"), ("S'il te plaît", "Please"),
        ("Oui", "Yes"), ("Non", "No"), ("Au revoir", "Goodbye"), ("Comment ça va ?", "How are you?"),
        ("Je voudrais", "I would like"), ("L'addition", "The bill"), ("Où est… ?", "Where is…?"),
        ("À gauche", "Left"), ("À droite", "Right"), ("Aujourd'hui", "Today"),
        ("Demain", "Tomorrow"), ("De l'eau", "Water"), ("Combien ça coûte ?", "How much is it?"),
    ]),
    LangPack(id: "es", flag: "🇪🇸", name: "Espagnol", words: [
        ("Bonjour", "Hola"), ("Merci", "Gracias"), ("S'il te plaît", "Por favor"),
        ("Oui", "Sí"), ("Non", "No"), ("Au revoir", "Adiós"), ("Comment ça va ?", "¿Qué tal?"),
        ("Je voudrais", "Quisiera"), ("L'addition", "La cuenta"), ("Où est… ?", "¿Dónde está…?"),
        ("À gauche", "A la izquierda"), ("À droite", "A la derecha"), ("Aujourd'hui", "Hoy"),
        ("Demain", "Mañana"), ("De l'eau", "Agua"), ("Combien ça coûte ?", "¿Cuánto cuesta?"),
    ]),
    LangPack(id: "de", flag: "🇩🇪", name: "Allemand", words: [
        ("Bonjour", "Hallo"), ("Merci", "Danke"), ("S'il te plaît", "Bitte"),
        ("Oui", "Ja"), ("Non", "Nein"), ("Au revoir", "Tschüss"), ("Comment ça va ?", "Wie geht's?"),
        ("Je voudrais", "Ich möchte"), ("L'addition", "Die Rechnung"), ("Où est… ?", "Wo ist…?"),
        ("À gauche", "Links"), ("À droite", "Rechts"), ("Aujourd'hui", "Heute"),
        ("Demain", "Morgen"), ("De l'eau", "Wasser"), ("Combien ça coûte ?", "Was kostet das?"),
    ]),
    LangPack(id: "it", flag: "🇮🇹", name: "Italien", words: [
        ("Bonjour", "Ciao"), ("Merci", "Grazie"), ("S'il te plaît", "Per favore"),
        ("Oui", "Sì"), ("Non", "No"), ("Au revoir", "Arrivederci"), ("Comment ça va ?", "Come stai?"),
        ("Je voudrais", "Vorrei"), ("L'addition", "Il conto"), ("Où est… ?", "Dov'è…?"),
        ("À gauche", "A sinistra"), ("À droite", "A destra"), ("Aujourd'hui", "Oggi"),
        ("Demain", "Domani"), ("De l'eau", "Acqua"), ("Combien ça coûte ?", "Quanto costa?"),
    ]),
]

private struct VocabItem: Codable { var box: Int; var due: Double }
private let leitnerDays: [Double] = [0, 1, 3, 7, 16, 35]   // intervalle par boîte

struct LanguagesView: View {
    @AppStorage("langCurrent") private var lang = "en"
    @AppStorage("vocabState")  private var stateRaw = ""
    @AppStorage("vocabStreakLast") private var streakLast = ""
    @AppStorage("vocabStreak") private var streak = 0

    @State private var revealed = false
    @State private var current: (String, String)?

    private var pack: LangPack { langPacks.first { $0.id == lang } ?? langPacks[0] }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 18) {
                    languagePicker
                    statsRow
                    if let c = current {
                        practiceCard(c)
                    } else {
                        doneCard
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Langues").navigationBarTitleDisplayMode(.inline)
        .onAppear { pickNext() }
        .onChange(of: lang) { _, _ in revealed = false; pickNext() }
    }

    private var languagePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(langPacks) { p in
                    Button { lang = p.id } label: {
                        VStack(spacing: 4) {
                            Text(p.flag).font(.title2)
                            Text(p.name).font(.caption2.weight(.medium))
                        }
                        .frame(width: 72, height: 60)
                        .background(lang == p.id ? Color.learnTint.opacity(0.18) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(lang == p.id ? Color.learnTint : .clear, lineWidth: 2))
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private var statsRow: some View {
        HStack {
            stat("\(learnedCount)/\(pack.words.count)", "appris")
            Divider().frame(height: 30)
            stat("\(dueCount)", "à revoir")
            Divider().frame(height: 30)
            stat("🔥 \(streak)", "jours")
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 2) {
            Text(v).font(.headline)
            Text(l).font(.caption2).foregroundStyle(Theme.textSecondary)
        }.frame(maxWidth: .infinity)
    }

    private func practiceCard(_ c: (String, String)) -> some View {
        VStack(spacing: 18) {
            Text(pack.flag).font(.largeTitle)
            Text(c.0).font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Divider()
            if revealed {
                Text(c.1).font(.title.weight(.heavy)).foregroundStyle(.learnTint)
                    .multilineTextAlignment(.center)
                HStack(spacing: 12) {
                    Button { grade(c, knew: false) } label: {
                        Label("À revoir", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(.orange)
                    Button { grade(c, knew: true) } label: {
                        Label("Je savais", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(.learnTint)
                }
            } else {
                Button { withAnimation { revealed = true } } label: {
                    Text("Révéler").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.learnTint)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20))
    }

    private var doneCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.learnTint)
            Text("Bravo, rien à revoir !").font(.headline)
            Text("Reviens plus tard : la répétition espacée te représentera les mots au bon moment.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(28).frame(maxWidth: .infinity)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: état (Leitner) encodé en JSON dans @AppStorage

    private func state() -> [String: VocabItem] {
        guard let data = stateRaw.data(using: .utf8),
              let m = try? JSONDecoder().decode([String: VocabItem].self, from: data) else { return [:] }
        return m
    }
    private func writeState(_ m: [String: VocabItem]) {
        if let data = try? JSONEncoder().encode(m), let s = String(data: data, encoding: .utf8) { stateRaw = s }
    }
    private func key(_ front: String) -> String { "\(lang)|\(front)" }

    private var learnedCount: Int {
        let m = state()
        return pack.words.filter { (m[key($0.0)]?.box ?? 0) >= 3 }.count
    }
    private var dueCount: Int {
        let m = state(); let now = Date().timeIntervalSince1970
        return pack.words.filter { (m[key($0.0)]?.due ?? 0) <= now }.count
    }

    private func pickNext() {
        let m = state(); let now = Date().timeIntervalSince1970
        let due = pack.words.filter { (m[key($0.0)]?.due ?? 0) <= now }
        revealed = false
        current = due.min { (m[key($0.0)]?.due ?? 0) < (m[key($1.0)]?.due ?? 0) }
    }

    private func grade(_ c: (String, String), knew: Bool) {
        var m = state()
        var item = m[key(c.0)] ?? VocabItem(box: 0, due: 0)
        if knew { item.box = min(item.box + 1, leitnerDays.count - 1) }
        else { item.box = 0 }
        let days = knew ? leitnerDays[item.box] : (10.0 / (24 * 60))   // pas su → 10 min
        item.due = Date().timeIntervalSince1970 + days * 86400
        m[key(c.0)] = item
        writeState(m)
        bumpStreak()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation { pickNext() }
    }

    private func bumpStreak() {
        let fmt = ISO8601DateFormatter()
        let today = fmt.string(from: Calendar.current.startOfDay(for: Date()))
        guard streakLast != today else { return }
        let yesterday = fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date()))!)
        streak = (streakLast == yesterday) ? streak + 1 : 1
        streakLast = today
    }
}
