import Foundation

// MARK: - Trilingo : cours construits depuis Tatoeba
//
// Chaque cours est une paire langue source -> langue cible, construite hors de
// l'app par `tools/trilingo/build_courses.py`: phrases courtes et leur traduction
// HUMAINE (Tatoeba, licence CC BY 2.0 FR), classees par difficulte, coupees en
// jours de 12 phrases et unites de 10 jours. Aucune phrase n'est generee par un
// modele. Un cours n'est "complet" qu'a partir de 180 jours.

struct TrilingoItem: Codable, Hashable, Identifiable {
    /// Identifiants Tatoeba (attribution).
    let sid: Int
    let tid: Int
    /// Phrase dans la langue source, et sa traduction dans la langue cible.
    let s: String
    let t: String
    /// Enregistrement humain disponible sur Tatoeba pour la phrase cible.
    let audio: Bool?
    /// Transliteration: pinyin (chinois), lecture en kana (japonais).
    var tr: String? = nil
    var id: Int { tid }
}

struct TrilingoDay: Codable, Hashable {
    let day: Int
    let unit: Int
    let level: String
    let items: [TrilingoItem]
    let words: [String]
    /// Mots deja vus a la fin de ce jour (progression du vocabulaire).
    let known: Int?
}

struct TrilingoCourse: Codable {
    let source: String
    let target: String
    let version: String
    let status: String
    let days: [TrilingoDay]
    let license: String
    let noSpaces: Bool?

    static let fullDays = 180
    var isComplete: Bool { status == "complet" && days.count >= Self.fullDays }
    var allItems: [TrilingoItem] { days.flatMap(\.items) }
    var unitCount: Int { days.last?.unit ?? 0 }

    func day(containing index: Int) -> TrilingoDay? {
        let perDay = days.first?.items.count ?? 12
        let d = index / max(perDay, 1)
        return d < days.count ? days[d] : nil
    }
}

struct TrilingoManifest: Codable {
    struct Entry: Codable {
        let target: String
        let status: String
        let days: Int
        let pairs: Int
        let withAudio: Int?
    }
    let source: String
    let courses: [String: Entry]
    let builtAt: String?
}

enum TrilingoLibrary {
    private static var cache: [String: TrilingoCourse] = [:]
    private static let lock = NSLock()

    private static func url(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json")
            ?? Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "Trilingo")
    }

    static func manifest() -> TrilingoManifest? {
        guard let u = url("trilingo_manifest"), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(TrilingoManifest.self, from: d)
    }

    static func course(source: String, target: String) -> TrilingoCourse? {
        let key = "\(source)-\(target)"
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        guard let u = url("trilingo_\(key)"), let d = try? Data(contentsOf: u),
              let c = try? JSONDecoder().decode(TrilingoCourse.self, from: d) else { return nil }
        lock.lock(); cache[key] = c; lock.unlock()
        return c
    }
}

// MARK: - Catalogue des langues

struct TrilingoLanguage: Identifiable, Hashable {
    /// Code Tatoeba (ISO 639-3).
    let code: String
    /// Code des voix et de la reconnaissance vocale d'Apple.
    let bcp47: String
    let name: String
    let native: String
    let rtl: Bool
    let script: String
    var id: String { code }
}

enum TrilingoLanguages {
    static let all: [TrilingoLanguage] = [
        .init(code: "eng", bcp47: "en-US", name: "Anglais", native: "English", rtl: false, script: "latin"),
        .init(code: "spa", bcp47: "es-ES", name: "Espagnol", native: "Español", rtl: false, script: "latin"),
        .init(code: "deu", bcp47: "de-DE", name: "Allemand", native: "Deutsch", rtl: false, script: "latin"),
        .init(code: "ita", bcp47: "it-IT", name: "Italien", native: "Italiano", rtl: false, script: "latin"),
        .init(code: "por", bcp47: "pt-PT", name: "Portugais", native: "Português", rtl: false, script: "latin"),
        .init(code: "nld", bcp47: "nl-NL", name: "Néerlandais", native: "Nederlands", rtl: false, script: "latin"),
        .init(code: "rus", bcp47: "ru-RU", name: "Russe", native: "Русский", rtl: false, script: "cyrillique"),
        .init(code: "ukr", bcp47: "uk-UA", name: "Ukrainien", native: "Українська", rtl: false, script: "cyrillique"),
        .init(code: "pol", bcp47: "pl-PL", name: "Polonais", native: "Polski", rtl: false, script: "latin"),
        .init(code: "tur", bcp47: "tr-TR", name: "Turc", native: "Türkçe", rtl: false, script: "latin"),
        .init(code: "jpn", bcp47: "ja-JP", name: "Japonais", native: "日本語", rtl: false, script: "kana et kanji"),
        .init(code: "cmn", bcp47: "zh-CN", name: "Chinois mandarin", native: "中文", rtl: false, script: "sinogrammes"),
        .init(code: "kor", bcp47: "ko-KR", name: "Coréen", native: "한국어", rtl: false, script: "hangeul"),
        .init(code: "ara", bcp47: "ar-SA", name: "Arabe", native: "العربية", rtl: true, script: "arabe"),
        .init(code: "heb", bcp47: "he-IL", name: "Hébreu", native: "עברית", rtl: true, script: "hébreu"),
        .init(code: "swe", bcp47: "sv-SE", name: "Suédois", native: "Svenska", rtl: false, script: "latin"),
        .init(code: "dan", bcp47: "da-DK", name: "Danois", native: "Dansk", rtl: false, script: "latin"),
        .init(code: "nob", bcp47: "nb-NO", name: "Norvégien", native: "Norsk bokmål", rtl: false, script: "latin"),
        .init(code: "fin", bcp47: "fi-FI", name: "Finnois", native: "Suomi", rtl: false, script: "latin"),
        .init(code: "ell", bcp47: "el-GR", name: "Grec", native: "Ελληνικά", rtl: false, script: "grec"),
        .init(code: "ces", bcp47: "cs-CZ", name: "Tchèque", native: "Čeština", rtl: false, script: "latin"),
        .init(code: "hun", bcp47: "hu-HU", name: "Hongrois", native: "Magyar", rtl: false, script: "latin"),
        .init(code: "ron", bcp47: "ro-RO", name: "Roumain", native: "Română", rtl: false, script: "latin"),
        .init(code: "bul", bcp47: "bg-BG", name: "Bulgare", native: "Български", rtl: false, script: "cyrillique"),
        .init(code: "vie", bcp47: "vi-VN", name: "Vietnamien", native: "Tiếng Việt", rtl: false, script: "latin"),
        .init(code: "tha", bcp47: "th-TH", name: "Thaï", native: "ไทย", rtl: false, script: "thaï"),
        .init(code: "hin", bcp47: "hi-IN", name: "Hindi", native: "हिन्दी", rtl: false, script: "devanagari"),
        .init(code: "ind", bcp47: "id-ID", name: "Indonésien", native: "Bahasa Indonesia", rtl: false, script: "latin"),
        .init(code: "fra", bcp47: "fr-FR", name: "Français", native: "Français", rtl: false, script: "latin"),
        .init(code: "cat", bcp47: "ca-ES", name: "Catalan", native: "Català", rtl: false, script: "latin"),
        .init(code: "epo", bcp47: "eo", name: "Espéranto", native: "Esperanto", rtl: false, script: "latin"),
        .init(code: "lit", bcp47: "lt-LT", name: "Lituanien", native: "Lietuvių", rtl: false, script: "latin"),
        .init(code: "pes", bcp47: "fa-IR", name: "Persan", native: "فارسی", rtl: true, script: "arabe"),
        .init(code: "srp", bcp47: "sr-RS", name: "Serbe", native: "Српски", rtl: false, script: "cyrillique"),
        .init(code: "hrv", bcp47: "hr-HR", name: "Croate", native: "Hrvatski", rtl: false, script: "latin"),
        .init(code: "slk", bcp47: "sk-SK", name: "Slovaque", native: "Slovenčina", rtl: false, script: "latin"),
        .init(code: "ber", bcp47: "zgh", name: "Berbère", native: "Tamaziɣt", rtl: false, script: "latin et tifinagh"),
        .init(code: "kab", bcp47: "kab", name: "Kabyle", native: "Taqbaylit", rtl: false, script: "latin"),
        .init(code: "tgl", bcp47: "fil-PH", name: "Tagalog", native: "Tagalog", rtl: false, script: "latin"),
        .init(code: "swh", bcp47: "sw-KE", name: "Swahili", native: "Kiswahili", rtl: false, script: "latin"),
    ]

    static func named(_ code: String) -> TrilingoLanguage? { all.first { $0.code == code } }
}
