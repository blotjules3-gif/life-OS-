import Foundation
import SwiftData

/// Extrait les faits durables des messages user pour les stocker en `MemoryEntry`.
///
/// **Pourquoi** : sans mémoire, le coach oublie tout à chaque conversation. Avec :
/// il peut dire "tu m'as dit que tu voulais courir 3× par semaine, tu en as fait 2"
/// une semaine plus tard.
///
/// **Approche** : heuristiques Regex FR sur les patterns récurrents.
/// Volontairement conservateur — mieux vaut manquer une mémoire que d'en créer
/// des fausses (bruit dans le contexte coach).
///
/// **Anti-doublon** : avant d'insérer, cherche une entrée existante avec un
/// contenu similaire (préfixe 20 chars). Si trouvée, met à jour la date.
///
/// **Confidentialité** : rien n'est envoyé au serveur. Les MemoryEntry sont
/// stockées en SwiftData local, exportables/effaçables via DataEraser.
enum MemoryExtractor {

    /// Regex + catégorie associée. L'ordre compte : premier match gagne.
    private static let patterns: [(pattern: String, category: String)] = [
        // Objectifs — "je veux X", "mon objectif est X", "je vise X"
        (#"(?i)(?:je\s+veux|mon\s+objectif|je\s+vise|j'aimerais|j'?aimerai)\s+(.{5,80})"#, "objectif"),
        // Habitudes — "je fais X tous les X", "je X chaque X"
        (#"(?i)(?:je\s+fais|je\s+cours|je\s+médite|je\s+bosse|je\s+travaille|je\s+m'?entraîne)\s+(.{5,80})"#, "habitude"),
        // Préférences — "j'aime X", "je préfère X", "je déteste X"
        (#"(?i)(?:j'aime|je\s+préfère|je\s+déteste|j'adore|je\s+kiffe)\s+(.{5,80})"#, "préférence"),
        // Faits perso — "j'habite X", "je bosse chez X", "j'ai X ans"
        (#"(?i)(?:j'habite|je\s+vis|je\s+bosse\s+chez|je\s+travaille\s+chez|j'ai\s+\d+\s+ans)\s?(.{0,80})"#, "fait"),
        // Contraintes — "je peux pas X", "je suis allergique à X"
        (#"(?i)(?:je\s+peux\s+pas|je\s+suis\s+allergique|je\s+ne\s+supporte\s+pas)\s+(.{5,80})"#, "contrainte")
    ]

    /// Analyse un message et insère les mémoires détectées dans le contexte.
    /// Retourne le nombre de mémoires créées ou mises à jour.
    @MainActor
    @discardableResult
    static func extract(from message: String, context: ModelContext) -> Int {
        let cleaned = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 10 else { return 0 }

        var created = 0
        for (patternStr, category) in patterns {
            guard let regex = try? NSRegularExpression(pattern: patternStr, options: []) else { continue }
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            let matches = regex.matches(in: cleaned, options: [], range: range)
            for match in matches {
                guard match.numberOfRanges >= 1 else { continue }
                let matchRange = match.range(at: 0)
                guard let swiftRange = Range(matchRange, in: cleaned) else { continue }
                let raw = String(cleaned[swiftRange])
                let content = normalize(raw)
                guard content.count >= 8, content.count <= 120 else { continue }

                if !upsert(content: content, category: category, context: context) { continue }
                created += 1
            }
        }
        if created > 0 {
            do { try context.save() } catch {
                AppLog.data.error("MemoryExtractor save failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return created
    }

    /// Insert ou met à jour une mémoire. Retourne true si insertion, false si doublon.
    @MainActor
    private static func upsert(content: String, category: String, context: ModelContext) -> Bool {
        let prefix = String(content.prefix(20)).lowercased()
        let descriptor = FetchDescriptor<MemoryEntry>()
        let existing = (try? context.fetch(descriptor)) ?? []
        if let match = existing.first(where: { $0.content.lowercased().hasPrefix(prefix) }) {
            match.created = .now
            return false
        }
        context.insert(MemoryEntry(
            content: content,
            category: category,
            source: "chat",
            created: .now,
            isPinned: false
        ))
        return true
    }

    /// Nettoie un fragment extrait : capitalise, supprime les traînes courantes.
    private static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cut à la première ponctuation forte (fin de phrase)
        if let dot = s.firstIndex(where: { ".!?".contains($0) }) {
            s = String(s[..<dot])
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }

    /// Récupère les mémoires les plus pertinentes à injecter dans le contexte coach.
    /// - Priorité : pinnées d'abord, puis les 10 plus récentes.
    @MainActor
    static func topMemories(context: ModelContext, limit: Int = 10) -> [MemoryEntry] {
        let descriptor = FetchDescriptor<MemoryEntry>(sortBy: [SortDescriptor(\.created, order: .reverse)])
        guard let all = try? context.fetch(descriptor) else { return [] }
        let pinned = all.filter { $0.isPinned }
        let unpinned = all.filter { !$0.isPinned }
        var out = pinned
        out.append(contentsOf: unpinned)
        return Array(out.prefix(limit))
    }
}
