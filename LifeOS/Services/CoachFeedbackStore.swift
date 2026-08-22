import Foundation

/// Boucle de feedback locale sur les réponses du coach.
///
/// Chaque 👍/👎 est stocké dans un JSONL du sandbox app avec un extrait de la
/// réponse. Le service en dérive une consigne courte injectée dans le prompt
/// système à chaque nouveau tour — le coach apprend petit à petit ce qui plaît
/// ou pas, sans jamais quitter l'iPhone.
///
/// Volume limité : on garde les 30 derniers feedbacks. Au-delà, rotation FIFO.
@MainActor
enum CoachFeedbackStore {

    enum Kind: String, Codable {
        case like
        case dislike
    }

    /// Raison qualitative optionnelle d'un dislike (après tap 👎 → chip).
    enum DislikeReason: String, Codable, CaseIterable {
        case tooLong = "trop long"
        case notConcrete = "pas assez concret"
        case offTopic = "hors sujet"
        case wrong = "faux"
        case tone = "mauvais ton"

        var label: String { rawValue }
    }

    struct Entry: Codable {
        let kind: Kind
        let snippet: String   // 200 premiers chars de la réponse coach
        let at: Date
        /// Raison du dislike, si l'user a précisé via chip. `nil` si pas de raison donnée.
        let dislikeReason: DislikeReason?

        init(kind: Kind, snippet: String, at: Date = .now, dislikeReason: DislikeReason? = nil) {
            self.kind = kind
            self.snippet = snippet
            self.at = at
            self.dislikeReason = dislikeReason
        }
    }

    private static let filename = "coach_feedback.jsonl"
    private static let maxEntries = 30
    private static let summarySnippetChars = 80

    // MARK: - Écriture

    /// Enregistre un feedback pour la réponse coach donnée.
    /// Pour un dislike, `reason` optionnel permet de catégoriser (trop long, hors sujet…).
    static func record(_ kind: Kind, response: String, reason: DislikeReason? = nil) {
        let entry = Entry(
            kind: kind,
            snippet: String(response.prefix(200)),
            dislikeReason: reason
        )
        var all = load()
        all.append(entry)
        // Rotation FIFO simple, on garde les 30 plus récents.
        if all.count > maxEntries {
            all = Array(all.suffix(maxEntries))
        }
        write(all)
        Haptics.tap()
    }

    // MARK: - Lecture (détection frustration)

    /// Retourne le nombre de dislikes dans les `within` dernières secondes.
    /// Utilisé par `CoachUpgradeSuggestion` pour détecter la frustration user
    /// et proposer un upgrade cloud.
    static func recentDislikeCount(within: TimeInterval) -> Int {
        let cutoff = Date().addingTimeInterval(-within)
        return load().filter { $0.kind == .dislike && $0.at >= cutoff }.count
    }

    // MARK: - Lecture (injection prompt)

    /// Résume le feedback récent pour injection dans le prompt système.
    /// Retourne "" si aucun feedback enregistré (n'ajoute rien au prompt).
    ///
    /// Approche v2 : catégorise les dislikes par raison au lieu d'injecter des
    /// snippets bruts. Le LLM comprend mieux "3 dislikes trop long" que 3 extraits.
    static func summary() -> String {
        let all = load()
        guard !all.isEmpty else { return "" }
        let recent = Array(all.suffix(20))
        var lines: [String] = []

        // Ratio positif/négatif
        let likes = recent.filter { $0.kind == .like }.count
        let dislikes = recent.filter { $0.kind == .dislike }.count
        if likes + dislikes > 0 {
            lines.append("Ratio feedback récent : \(likes) 👍 / \(dislikes) 👎.")
        }

        // Agrégation dislikes par raison
        let dislikeEntries = recent.filter { $0.kind == .dislike }
        let byReason = Dictionary(grouping: dislikeEntries, by: { $0.dislikeReason })
        var reasonLines: [String] = []
        for (reason, entries) in byReason {
            guard let reason else { continue }
            reasonLines.append("- \(entries.count)× \(reason.label)")
        }
        if !reasonLines.isEmpty {
            lines.append("À CORRIGER pour l'utilisateur (raisons de dislikes) :")
            lines.append(contentsOf: reasonLines)
        }

        // Extraits (fallback)
        let unnamedDislikes = dislikeEntries.filter { $0.dislikeReason == nil }.suffix(3)
        if !unnamedDislikes.isEmpty {
            lines.append("Réponses désapprouvées (sans raison précise) :")
            for d in unnamedDislikes {
                lines.append("  - \(d.snippet.prefix(summarySnippetChars))…")
            }
        }
        let recentLikes = recent.filter { $0.kind == .like }.suffix(3)
        if !recentLikes.isEmpty {
            lines.append("Réponses appréciées (à reproduire) :")
            for l in recentLikes {
                lines.append("  + \(l.snippet.prefix(summarySnippetChars))…")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Efface tout l'historique feedback (bouton "Réinitialiser" dans les prefs).
    static func reset() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Persistance JSONL

    private static func fileURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent(filename)
    }

    private static func load() -> [Entry] {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // JSONL — une entrée par ligne.
        return data.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(Entry.self, from: Data(line))
        }
    }

    private static func write(_ entries: [Entry]) {
        guard let url = fileURL() else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var out = Data()
        for e in entries {
            if let line = try? encoder.encode(e) {
                out.append(line)
                out.append(0x0A)
            }
        }
        try? out.write(to: url, options: .atomic)
    }
}
