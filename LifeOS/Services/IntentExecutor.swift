import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Détecte et exécute les actions demandées par l'utilisateur en langage naturel.
///
/// Exemples de messages qui déclenchent une exécution :
/// - « ajoute méditation à mes habitudes »
/// - « traque ma prise de BPC-157 tous les jours »
/// - « rappelle-moi de payer le loyer le 5 »
/// - « note-moi : appeler dentiste »
///
/// Chaque exécution retourne un `ExecutedIntent` décrivant ce qui a été fait,
/// exposé au coach pour qu'il puisse le confirmer dans sa réponse.
///
/// Approche : LLM Apple Intelligence pour extraire un tableau JSON strict
/// d'intents, puis exécution locale via SwiftData. Fallback regex FR simple.
@MainActor
enum IntentExecutor {

    /// Types d'intents supportés côté iOS on-device.
    enum IntentType: String, Codable {
        case createHabit
        case createTodo
        case createReminder
    }

    /// Représentation typée d'une action extraite.
    struct DetectedIntent: Codable {
        let type: IntentType
        let title: String
        /// Catégorie associée si détectable (module tag pour habitude).
        let module: String?
        /// Fréquence pour les habitudes : "daily", "weekly"
        let frequency: String?
        /// Delay en secondes pour les rappels
        let delaySeconds: Int?
    }

    /// Résultat d'une exécution.
    struct ExecutedIntent {
        let type: IntentType
        let title: String
        let userFacingSummary: String  // "Habitude créée : méditation" — pour le coach
    }

    /// Détecte + exécute + retourne ce qui a été fait.
    /// Idempotent : n'exécute rien si un intent similaire vient d'être créé
    /// (dédup naïf par title).
    @discardableResult
    static func detectAndExecute(from message: String, context: ModelContext?) async -> [ExecutedIntent] {
        guard let context else { return [] }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 5 else { return [] }

        var detected: [DetectedIntent] = []

        // 1) Regex FR rapides
        detected.append(contentsOf: regexPass(trimmed))

        // 2) LLM AGRESSIF si Apple Intelligence dispo — c'est le vrai extracteur
        //    d'intents pour les phrases complexes ("je veux que tu crées des rappels
        //    quotidiens pour ma séance, mes peptides, mes protéines").
        //    Déclenché dès que le message contient une intention plausible (verbes clés)
        //    OU s'il fait plus de 30 chars.
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable,
           shouldRunLLMPass(trimmed) {
            let llm = await llmPass(trimmed)
            let known = Set(detected.map { "\($0.type.rawValue):\($0.title.lowercased())" })
            detected.append(contentsOf: llm.filter { !known.contains("\($0.type.rawValue):\($0.title.lowercased())") })
        }
        #endif

        // 3) Exécuter
        var results: [ExecutedIntent] = []
        for intent in detected {
            if let done = execute(intent, context: context) {
                results.append(done)
            }
        }
        return results
    }

    // MARK: - Regex pass

    private static func regexPass(_ message: String) -> [DetectedIntent] {
        let m = message.lowercased()
        var out: [DetectedIntent] = []

        // "ajoute X à mes habitudes", "ajoute une habitude X", "traque X"
        for pattern in [
            #"(?:ajoute|rajoute|crée|creer|traque|tracke|track)\s+(?:une\s+)?(?:habitude|habit)?\s*[:\-]?\s*(?:de\s+|pour\s+)?([a-zA-ZÀ-ÿ0-9\-_ ]{3,40})(?=\s+(?:tous\s+les\s+jours|quotidien|chaque\s+jour|à\s+mes\s+habitudes)|$|\.|,)"#,
            #"(?:ajoute|rajoute|crée|creer)\s+(?:l'|la\s+|une\s+)?habitude\s+(?:de\s+|pour\s+)?([a-zA-ZÀ-ÿ0-9\-_ ]{3,40})"#,
        ] {
            let matches = allMatches(pattern: pattern, in: m)
            for match in matches {
                if let title = cleanTitle(groupValue(match, group: 1, in: m)) {
                    out.append(DetectedIntent(type: .createHabit, title: title, module: nil, frequency: "daily", delaySeconds: nil))
                }
            }
        }

        // "note-moi X", "rappelle-moi X", "n'oublie pas X" → todo
        for pattern in [
            #"(?:note[\-\s]moi|note\-toi|ajoute\s+une\s+tâche|ajoute\s+une\s+tache|crée\s+une\s+tâche|n'oublie\s+pas\s+de|rappelle[\-\s]moi\s+de)\s+(?:que\s+je\s+dois\s+)?([a-zA-ZÀ-ÿ0-9\-_' ]{3,60})(?=$|\.|,)"#,
        ] {
            let matches = allMatches(pattern: pattern, in: m)
            for match in matches {
                if let title = cleanTitle(groupValue(match, group: 1, in: m)) {
                    out.append(DetectedIntent(type: .createTodo, title: title, module: nil, frequency: nil, delaySeconds: nil))
                }
            }
        }

        return out
    }

    /// Vrai si le message contient des verbes/keywords qui laissent penser
    /// qu'il y a des intents à exécuter — même si la regex n'a rien trouvé.
    private static func shouldRunLLMPass(_ message: String) -> Bool {
        let m = message.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        // Cheap check : verbe d'action ou message long
        let actionVerbs = [
            "ajoute", "rajoute", "cree", "creer", "crée", "faire", "note",
            "rappelle", "rappel", "traque", "tracke", "programme", "planifie",
            "mets", "met", "j'aimerais", "je veux", "il faut", "il me faut",
            "n'oublie", "prends", "prend", "quotidien", "chaque jour",
            "tous les jours", "habitude"
        ]
        if actionVerbs.contains(where: { m.contains($0) }) { return true }
        return message.count > 60
    }

    private static func cleanTitle(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), s.count >= 3 else { return nil }
        // Nettoyer les fins parasites courantes
        let stopwords = [" à mes habitudes", " dans mes habitudes", " tous les jours", " chaque jour", " au quotidien"]
        for stop in stopwords {
            if let range = s.range(of: stop) {
                s = String(s[..<range.lowerBound])
            }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " :,.;-"))
        guard s.count >= 3 else { return nil }
        return s
    }

    private static func allMatches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range)
    }

    private static func groupValue(_ match: NSTextCheckingResult, group: Int, in text: String) -> String? {
        guard group < match.numberOfRanges else { return nil }
        let r = match.range(at: group)
        guard r.location != NSNotFound, let swiftRange = Range(r, in: text) else { return nil }
        return String(text[swiftRange])
    }

    // MARK: - LLM pass (multi-intent extraction)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func llmPass(_ message: String) async -> [DetectedIntent] {
        let instructions = """
        Tu extrais TOUTES les actions à exécuter suite à un message utilisateur.
        L'utilisateur parle en langage naturel — décompose CHAQUE action mentionnée en un intent séparé.

        Types possibles :
        - createHabit : habitude quotidienne récurrente ("traque ma prise de créatine", "ajoute méditation à mes habitudes", "je veux un rappel quotidien pour prendre mes peptides")
        - createTodo : tâche/action one-shot ("note-moi appeler le dentiste", "rajoute payer le loyer")
        - createReminder : rappel unique avec délai ("rappelle-moi dans 2h de boire")

        EXEMPLE CRITIQUE :
        Message : "je veux que tu rentres tout ça dans mes habitudes, j'aimerais un rappel quotidien fais ta séance de sport prends tes peptides prends tes protéines et prends tout ce genre de choses"
        Extraction attendue :
        [
          {"type":"createHabit","title":"Faire ma séance de sport","module":"fitness","frequency":"daily","delaySeconds":null},
          {"type":"createHabit","title":"Prendre mes peptides","module":"medical","frequency":"daily","delaySeconds":null},
          {"type":"createHabit","title":"Prendre mes protéines","module":"nutrition","frequency":"daily","delaySeconds":null}
        ]

        Retourne un JSON STRICT tableau, uniquement le JSON :
        [{"type":"createHabit","title":"...","module":"...","frequency":"daily","delaySeconds":null}]

        Règles :
        - DÉCOMPOSE une phrase "tout ça, X, Y et Z" en 3 intents distincts.
        - title : impératif court "Faire X" / "Prendre Y" (3-40 chars), sans "je veux", sans "il faut".
        - module : parmi fitness, nutrition, sleep, mind, productivity, medical, looks, learning, finance, home.
        - Ne pas extraire pour de simples infos ("je pèse 74 kg" → PAS un intent, c'est un ProfileField).
        - Si rien à faire : []
        """

        let session = LanguageModelSession(instructions: instructions)
        let raw = await RetryHelper.withBackoffOrNil(
            attempts: 1,
            delays: [],
            operation: "IntentExecutor.llmPass"
        ) {
            let response = try await session.respond(to: message)
            return response.content
        }
        guard let raw else { return [] }
        return parseLLMResponse(raw)
    }
    #endif

    private static func parseLLMResponse(_ raw: String) -> [DetectedIntent] {
        guard let start = raw.firstIndex(of: "["),
              let end = raw.lastIndex(of: "]") else { return [] }
        let json = String(raw[start...end])
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DetectedIntent].self, from: data)) ?? []
    }

    // MARK: - Exécution

    private static func execute(_ intent: DetectedIntent, context: ModelContext) -> ExecutedIntent? {
        switch intent.type {
        case .createHabit:
            let d = HabitDefaults.iconAndColor(for: intent.module ?? "")
            let habit = Habit(
                name: intent.title,
                icon: d.icon,
                colorHex: d.colorHex,
                isPending: false,
                moduleTag: intent.module ?? ""
            )
            context.insert(habit)
            LifeOSTry(try context.save(), context: "IntentExecutor createHabit", category: AppLog.data)
            return ExecutedIntent(
                type: .createHabit,
                title: intent.title,
                userFacingSummary: "Habitude créée : \(intent.title)"
            )

        case .createTodo:
            let todo = TodoItem(title: intent.title, priority: 1)
            context.insert(todo)
            LifeOSTry(try context.save(), context: "IntentExecutor createTodo", category: AppLog.data)
            return ExecutedIntent(
                type: .createTodo,
                title: intent.title,
                userFacingSummary: "Tâche ajoutée : \(intent.title)"
            )

        case .createReminder:
            let content = UNMutableNotificationContent()
            content.title = "LifeOS"
            content.body = intent.title
            content.sound = .default
            let delay = TimeInterval(intent.delaySeconds ?? 3600)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
            return ExecutedIntent(
                type: .createReminder,
                title: intent.title,
                userFacingSummary: "Rappel programmé : \(intent.title)"
            )
        }
    }
}

import UserNotifications
