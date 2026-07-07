import SwiftUI
import UIKit
import AVFoundation

// MARK: - Convertisseur de devises (hors-ligne, taux indicatifs)

private struct Currency: Identifiable {
    let code: String      // ISO 4217
    let flag: String
    let name: String
    let perEUR: Double    // combien d'unités pour 1 €
    var id: String { code }
}

// Taux indicatifs (base €). Hors-ligne : pour une estimation, pas une opération bancaire.
private let currencies: [Currency] = [
    .init(code: "EUR", flag: "🇪🇺", name: "Euro",            perEUR: 1.00),
    .init(code: "USD", flag: "🇺🇸", name: "Dollar US",       perEUR: 1.08),
    .init(code: "GBP", flag: "🇬🇧", name: "Livre sterling",  perEUR: 0.85),
    .init(code: "CHF", flag: "🇨🇭", name: "Franc suisse",    perEUR: 0.95),
    .init(code: "JPY", flag: "🇯🇵", name: "Yen",             perEUR: 168.0),
    .init(code: "CAD", flag: "🇨🇦", name: "Dollar canadien", perEUR: 1.47),
    .init(code: "AUD", flag: "🇦🇺", name: "Dollar australien", perEUR: 1.63),
    .init(code: "MAD", flag: "🇲🇦", name: "Dirham marocain", perEUR: 10.8),
    .init(code: "AED", flag: "🇦🇪", name: "Dirham EAU",      perEUR: 3.97),
    .init(code: "THB", flag: "🇹🇭", name: "Baht thaï",       perEUR: 39.0),
    .init(code: "TRY", flag: "🇹🇷", name: "Livre turque",    perEUR: 38.0),
    .init(code: "MXN", flag: "🇲🇽", name: "Peso mexicain",   perEUR: 19.8),
]

struct CurrencyConverterView: View {
    @AppStorage("fxFrom")   private var from = "EUR"
    @AppStorage("fxTo")     private var to   = "USD"
    @AppStorage("fxAmount") private var amountRaw = "100"

    private func cur(_ code: String) -> Currency { currencies.first { $0.code == code } ?? currencies[0] }
    private var amount: Double { Double(amountRaw.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    private var converted: Double {
        let inEUR = amount / cur(from).perEUR
        return inEUR * cur(to).perEUR
    }
    private var rate: Double { cur(to).perEUR / cur(from).perEUR }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    amountCard
                    resultCard
                    quickTable
                    Text("Taux indicatifs, mis à jour manuellement. Pour une estimation de voyage, pas une transaction.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Convertisseur").navigationBarTitleDisplayMode(.inline)
    }

    private var amountCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Montant").font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            HStack {
                TextField("0", text: $amountRaw)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(from).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 10) {
                currencyPicker("De", selection: $from)
                Button {
                    let t = from; from = to; to = t
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                } label: {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.title2).foregroundStyle(.travelTint)
                }
                currencyPicker("Vers", selection: $to)
            }
        }
        .padding()
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18))
    }

    private func currencyPicker(_ label: String, selection: Binding<String>) -> some View {
        Menu {
            ForEach(currencies) { c in
                Button { selection.wrappedValue = c.code } label: {
                    Text("\(c.flag)  \(c.code) — \(c.name)")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(cur(selection.wrappedValue).flag)
                Text(selection.wrappedValue).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.bg2, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.textPrimary)
        }
    }

    private var resultCard: some View {
        VStack(spacing: 6) {
            Text(cur(to).flag + " " + fmt(converted) + " " + to)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(.travelTint)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text("1 \(from) = \(fmt(rate)) \(to)")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 18))
    }

    private var quickTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repères rapides").font(.caption).foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)
            ForEach([10.0, 50.0, 100.0, 500.0], id: \.self) { v in
                HStack {
                    Text("\(fmt(v)) \(from)").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(fmt(v / cur(from).perEUR * cur(to).perEUR)) \(to)")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                .padding(.vertical, 9)
                if v != 500 { Divider() }
            }
        }
        .padding()
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 16))
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v >= 100 ? 0 : 2
        f.groupingSeparator = " "
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }
}

// MARK: - Phrases de voyage (hors-ligne, prononcées à voix haute)

private struct Phrase: Identifiable {
    let fr: String
    let translations: [String: String]   // code langue → traduction
    var id: String { fr }
}

private struct TravelLang: Identifiable {
    let code: String       // code voix AVSpeech (ex: "en-US")
    let key: String        // clé dans translations
    let flag: String
    let name: String
    var id: String { key }
}

private let phraseLangs: [TravelLang] = [
    .init(code: "en-US", key: "en", flag: "🇬🇧", name: "Anglais"),
    .init(code: "es-ES", key: "es", flag: "🇪🇸", name: "Espagnol"),
    .init(code: "de-DE", key: "de", flag: "🇩🇪", name: "Allemand"),
    .init(code: "it-IT", key: "it", flag: "🇮🇹", name: "Italien"),
    .init(code: "pt-PT", key: "pt", flag: "🇵🇹", name: "Portugais"),
]

private let travelPhrases: [Phrase] = [
    .init(fr: "Bonjour", translations: ["en":"Hello","es":"Hola","de":"Hallo","it":"Ciao","pt":"Olá"]),
    .init(fr: "Merci beaucoup", translations: ["en":"Thank you very much","es":"Muchas gracias","de":"Vielen Dank","it":"Grazie mille","pt":"Muito obrigado"]),
    .init(fr: "Parlez-vous anglais ?", translations: ["en":"Do you speak English?","es":"¿Habla inglés?","de":"Sprechen Sie Englisch?","it":"Parla inglese?","pt":"Fala inglês?"]),
    .init(fr: "Je ne comprends pas", translations: ["en":"I don't understand","es":"No entiendo","de":"Ich verstehe nicht","it":"Non capisco","pt":"Não entendo"]),
    .init(fr: "Où sont les toilettes ?", translations: ["en":"Where is the toilet?","es":"¿Dónde está el baño?","de":"Wo ist die Toilette?","it":"Dov'è il bagno?","pt":"Onde é a casa de banho?"]),
    .init(fr: "Combien ça coûte ?", translations: ["en":"How much is it?","es":"¿Cuánto cuesta?","de":"Was kostet das?","it":"Quanto costa?","pt":"Quanto custa?"]),
    .init(fr: "L'addition, s'il vous plaît", translations: ["en":"The bill, please","es":"La cuenta, por favor","de":"Die Rechnung, bitte","it":"Il conto, per favore","pt":"A conta, por favor"]),
    .init(fr: "Pouvez-vous m'aider ?", translations: ["en":"Can you help me?","es":"¿Puede ayudarme?","de":"Können Sie mir helfen?","it":"Può aiutarmi?","pt":"Pode ajudar-me?"]),
    .init(fr: "Je voudrais un café", translations: ["en":"I would like a coffee","es":"Quisiera un café","de":"Ich möchte einen Kaffee","it":"Vorrei un caffè","pt":"Queria um café"]),
    .init(fr: "Où est la gare ?", translations: ["en":"Where is the station?","es":"¿Dónde está la estación?","de":"Wo ist der Bahnhof?","it":"Dov'è la stazione?","pt":"Onde é a estação?"]),
    .init(fr: "À gauche / à droite", translations: ["en":"Left / right","es":"Izquierda / derecha","de":"Links / rechts","it":"Sinistra / destra","pt":"Esquerda / direita"]),
    .init(fr: "Au secours !", translations: ["en":"Help!","es":"¡Socorro!","de":"Hilfe!","it":"Aiuto!","pt":"Socorro!"]),
]

final class PhraseSpeaker {
    static let shared = PhraseSpeaker()
    private let synth = AVSpeechSynthesizer()
    func speak(_ text: String, voice code: String) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: code)
        u.rate = 0.42
        synth.speak(u)
    }
}

struct PhrasebookView: View {
    @AppStorage("phraseLang") private var langKey = "en"
    @State private var spoken: String? = nil

    private var lang: TravelLang { phraseLangs.first { $0.key == langKey } ?? phraseLangs[0] }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 14) {
                    langPicker
                    ForEach(travelPhrases) { p in phraseRow(p) }
                    Text("Touche une phrase pour l'entendre prononcée.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary).padding(.top, 4)
                }
                .padding()
            }
        }
        .navigationTitle("Phrases de voyage").navigationBarTitleDisplayMode(.inline)
    }

    private var langPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(phraseLangs) { l in
                    Button { langKey = l.key } label: {
                        VStack(spacing: 4) {
                            Text(l.flag).font(.title2)
                            Text(l.name).font(.caption2.weight(.medium))
                        }
                        .frame(width: 74, height: 60)
                        .background(langKey == l.key ? Color.travelTint.opacity(0.18) : Theme.card,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                            .stroke(langKey == l.key ? Color.travelTint : .clear, lineWidth: 2))
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
        }
    }

    private func phraseRow(_ p: Phrase) -> some View {
        let target = p.translations[lang.key] ?? ""
        return Button {
            PhraseSpeaker.shared.speak(target, voice: lang.code)
            withAnimation(.easeOut(duration: 0.15)) { spoken = p.id }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if spoken == p.id { withAnimation { spoken = nil } }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.fr).font(.caption).foregroundStyle(Theme.textSecondary)
                    Text(target).font(.headline).foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: spoken == p.id ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.title3)
                    .foregroundStyle(spoken == p.id ? Color.travelTint : Theme.textSecondary)
                    .scaleEffect(spoken == p.id ? 1.15 : 1)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}
