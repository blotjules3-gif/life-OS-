import SwiftUI
import UIKit
import AVFoundation

// MARK: - Convertisseur de devises (taux reels dates, voir ExchangeRates)

private struct Currency: Identifiable {
    let code: String      // ISO 4217
    let flag: String
    let name: String
    var id: String { code }
}

private let currencies: [Currency] = [
    .init(code: "EUR", flag: "🇪🇺", name: "Euro"),
    .init(code: "USD", flag: "🇺🇸", name: "Dollar US"),
    .init(code: "GBP", flag: "🇬🇧", name: "Livre sterling"),
    .init(code: "CHF", flag: "🇨🇭", name: "Franc suisse"),
    .init(code: "JPY", flag: "🇯🇵", name: "Yen"),
    .init(code: "CAD", flag: "🇨🇦", name: "Dollar canadien"),
    .init(code: "AUD", flag: "🇦🇺", name: "Dollar australien"),
    .init(code: "MAD", flag: "🇲🇦", name: "Dirham marocain"),
    .init(code: "AED", flag: "🇦🇪", name: "Dirham EAU"),
    .init(code: "THB", flag: "🇹🇭", name: "Baht thaï"),
    .init(code: "TRY", flag: "🇹🇷", name: "Livre turque"),
    .init(code: "MXN", flag: "🇲🇽", name: "Peso mexicain"),
    .init(code: "CNY", flag: "🇨🇳", name: "Yuan"),
    .init(code: "SEK", flag: "🇸🇪", name: "Couronne suédoise"),
    .init(code: "NOK", flag: "🇳🇴", name: "Couronne norvégienne"),
    .init(code: "DKK", flag: "🇩🇰", name: "Couronne danoise"),
    .init(code: "PLN", flag: "🇵🇱", name: "Zloty"),
    .init(code: "CZK", flag: "🇨🇿", name: "Couronne tchèque"),
    .init(code: "HUF", flag: "🇭🇺", name: "Forint"),
    .init(code: "BRL", flag: "🇧🇷", name: "Réal brésilien"),
    .init(code: "INR", flag: "🇮🇳", name: "Roupie indienne"),
    .init(code: "KRW", flag: "🇰🇷", name: "Won"),
    .init(code: "SGD", flag: "🇸🇬", name: "Dollar de Singapour"),
    .init(code: "HKD", flag: "🇭🇰", name: "Dollar de Hong Kong"),
    .init(code: "NZD", flag: "🇳🇿", name: "Dollar néo-zélandais"),
    .init(code: "ZAR", flag: "🇿🇦", name: "Rand"),
    .init(code: "ILS", flag: "🇮🇱", name: "Shekel"),
]

struct CurrencyConverterView: View {
    @AppStorage(AppStorageKeys.fxFrom)   private var from = "EUR"
    @AppStorage(AppStorageKeys.fxTo)     private var to   = "USD"
    @AppStorage(AppStorageKeys.fxAmount) private var amountRaw = "100"
    @State private var table = ExchangeRates.readCache() ?? ExchangeRates.builtinTable
    @State private var freshness: ExchangeRates.Freshness =
        ExchangeRates.readCache().map { .cached(age: Date().timeIntervalSince($0.fetchedAt)) } ?? .builtin
    @State private var loading = false
    @State private var problem: String?

    private func cur(_ code: String) -> Currency { currencies.first { $0.code == code } ?? currencies[0] }
    private var parsed: AmountInput.Parsed { AmountInput.parse(amountRaw, rules: .init(required: true, allowZero: true)) }
    private var converted: Double? { parsed.value.flatMap { table.convert($0, from: from, to: to) } }
    private var rate: Double? { table.convert(1, from: from, to: to) }

    var body: some View {
        ZStack {
            Theme.background
            ScrollView {
                VStack(spacing: 16) {
                    amountCard
                    resultCard
                    sourceCard
                    quickTable
                    Text("Taux de référence pour estimer. Ta banque ou le bureau de change appliquent leur propre taux et leurs frais.")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }
                .padding()
            }
            .refreshable { await refresh() }
        }
        .navigationTitle("Convertisseur").navigationBarTitleDisplayMode(.inline)
        .task { if needsRefresh { await refresh() } }
    }

    /// Les taux de la BCE changent une fois par jour ouvre: inutile de redemander
    /// plus souvent que toutes les 6 heures.
    private var needsRefresh: Bool {
        switch freshness {
        case .live: return false
        case .cached(let age): return age > 6 * 3600
        case .builtin: return true
        }
    }

    private func refresh() async {
        loading = true
        let (t, f, err) = await ExchangeRates.load(wanted: currencies.map(\.code))
        table = t; freshness = f; problem = err; loading = false
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
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(from).font(.title3.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            if !amountRaw.isEmpty, let m = parsed.message {
                Text(m).font(.caption).foregroundStyle(Theme.warning).frame(maxWidth: .infinity, alignment: .leading)
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
                .accessibilityLabel("Inverser les devises")
                currencyPicker("Vers", selection: $to)
            }
        }
        .padding()
        .raisedSurface(RoundedRectangle(cornerRadius: 18))
    }

    private func currencyPicker(_ label: String, selection: Binding<String>) -> some View {
        Menu {
            ForEach(currencies) { c in
                Button { selection.wrappedValue = c.code } label: {
                    Text("\(c.flag)  \(c.code) · \(c.name)")
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
            .raisedSurface(RoundedRectangle(cornerRadius: 12), .nested)
            .foregroundStyle(Theme.textPrimary)
        }
        .accessibilityLabel("\(label) : \(cur(selection.wrappedValue).name)")
    }

    private var resultCard: some View {
        VStack(spacing: 6) {
            if let converted {
                Text(cur(to).flag + " " + fmt(converted) + " " + to)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(.travelTint)
                    .minimumScaleFactor(0.6).lineLimit(1)
            } else {
                Text("—").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.textSecondary)
            }
            if let rate {
                Text("1 \(from) = \(rate.formatted(.number.precision(.significantDigits(5)).locale(Locale(identifier: "fr_FR")))) \(to)")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            else { Text("Pas de taux disponible pour cette paire.").font(.caption).foregroundStyle(Theme.warning) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 22)
        .raisedSurface(RoundedRectangle(cornerRadius: 18))
    }

    /// D'ou viennent les deux taux utilises, et de quand.
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(freshnessTitle).font(.subheadline.weight(.semibold))
                    .foregroundStyle(freshness == .live ? Theme.textPrimary : Theme.warning)
                Spacer()
                if loading { ProgressView() }
                else { Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Actualiser") }
            }
            ForEach(Array(Set([from, to]).subtracting(["EUR"])).sorted(), id: \.self) { code in
                if let r = table.rate(code) {
                    Text("\(code) : \(r.source.rawValue), taux du \(r.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            if let problem { Text(problem).font(.caption2).foregroundStyle(Theme.warning) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    private var freshnessTitle: String {
        switch freshness {
        case .live: return "Taux à jour"
        case .cached(let age):
            let h = Int(age / 3600)
            return h < 24 ? "Taux enregistrés il y a \(max(1, h)) h" : "Taux enregistrés il y a \(h / 24) j"
        case .builtin: return "Taux intégrés (anciens)"
        }
    }

    private var quickTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repères rapides").font(.caption).foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 8)
            ForEach([10.0, 50.0, 100.0, 500.0], id: \.self) { v in
                HStack {
                    Text("\(fmt(v)) \(from)").foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(table.convert(v, from: from, to: to).map { "\(fmt($0)) \(to)" } ?? "—")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.subheadline)
                .padding(.vertical, 9)
                if v != 500 { Divider() }
            }
        }
        .padding()
        .raisedSurface(RoundedRectangle(cornerRadius: 16))
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v >= 100 ? 0 : (v < 0.1 ? 4 : 2)
        f.groupingSeparator = " "
        f.decimalSeparator = ","
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
    @AppStorage(AppStorageKeys.phraseLang) private var langKey = "en"
    @State private var spoken: String?

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
                        .background(langKey == l.key ? Color.travelTint.opacity(0.26) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall)).raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
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
            .raisedSurface(RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
        .buttonStyle(.plain)
    }
}
