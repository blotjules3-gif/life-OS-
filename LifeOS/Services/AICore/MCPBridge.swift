import Foundation

/// Fondations du bridge MCP (Model Context Protocol) pour LifeOS.
///
/// ═══════════════════════════════════════════════════════════════════
/// VISION
/// ═══════════════════════════════════════════════════════════════════
///
/// MCP est un protocole ouvert (Anthropic, novembre 2024) qui standardise
/// la façon dont un LLM externe se branche sur des sources de données ou
/// des outils. Un serveur MCP expose des "resources" (données lisibles) et
/// des "tools" (actions exécutables). Un client MCP (Claude Desktop, Cursor,
/// autres) peut s'y connecter et utiliser ces resources/tools au fil des
/// conversations.
///
/// À terme, LifeOS peut jouer deux rôles :
///
///   1. SERVEUR MCP — LifeOS expose les données de l'user (habitudes,
///      objectifs, sommeil, nutrition, historique coach) et des tools
///      (créer une habitude, planifier un rappel, marquer un objectif).
///      Claude Desktop peut alors dire : "regarde mes habitudes de la
///      semaine et propose-moi un ajustement".
///
///   2. CLIENT MCP — le coach LifeOS peut se connecter à des serveurs MCP
///      externes que l'user autorise (calendrier, mails, code, docs
///      pro). Il gagne alors du contexte au-delà de ce que LifeOS stocke.
///
/// ═══════════════════════════════════════════════════════════════════
/// STATUT ACTUEL (Loop 27)
/// ═══════════════════════════════════════════════════════════════════
///
/// Ce fichier pose UNIQUEMENT les fondations conceptuelles et le protocol
/// Swift. Aucune implémentation MCP fonctionnelle n'est encore présente :
///
///   - Pas de serveur JSON-RPC 2.0
///   - Pas de client MCP
///   - Pas d'auth OAuth / device flow
///   - Pas d'exposition réelle des données
///
/// L'objectif de ce round : figer l'architecture cible pour qu'un futur
/// volet 4 puisse la brancher sans casser l'existant.
///
/// ═══════════════════════════════════════════════════════════════════
/// SÉCURITÉ (règles absolues)
/// ═══════════════════════════════════════════════════════════════════
///
///   - Aucune donnée user ne sort de LifeOS sans consentement EXPLICITE
///     (opt-in par resource, jamais bulk)
///   - Allowlist stricte des tools exposés (jamais writeArbitraryFile)
///   - Tokens externes (Claude Desktop, autres clients MCP) stockés dans
///     le Keychain via `AIProviderCredentials.Slot.custom` étendu
///   - Log toutes les requêtes entrantes/sortantes dans AIActivityLogger
///   - Rate limit local (max 60 req/min par client MCP autorisé)
///   - Révocation possible à tout moment depuis un écran dédié
///
/// ═══════════════════════════════════════════════════════════════════
/// ROADMAP (indicative)
/// ═══════════════════════════════════════════════════════════════════
///
///   Phase 1 (ce fichier) — fondations protocol + doc vision
///   Phase 2 — serveur MCP read-only sur localhost (test Claude Desktop)
///   Phase 3 — auth + consentement par resource
///   Phase 4 — tools écriture (créer habitude, planifier rappel)
///   Phase 5 — client MCP pour brancher serveurs externes (Calendrier,
///             Mails, GitHub) au coach LifeOS
///
/// Voir : `docs/mcp/README.md` pour la vision détaillée et la roadmap.
protocol MCPServerBridge: Sendable {

    /// Identifiant unique du serveur MCP (ex: "lifeos.mcp.v1").
    var id: String { get }

    /// Nom humain affiché à l'user dans les logs de consentement.
    var displayName: String { get }

    /// Resources exposées par ce serveur. L'user doit consentir individuellement.
    /// Ex: `habitsRead`, `sleepRead`, `goalsRead`.
    var availableResources: [MCPResource] { get }

    /// Tools exécutables. Chaque tool a un schéma JSON + une allowlist.
    /// Ex: `createHabit`, `scheduleReminder`.
    var availableTools: [MCPTool] { get }

    /// Vrai si le serveur est actif (activé par l'user + tokens valides).
    @MainActor
    var isActive: Bool { get }
}

/// Une resource MCP = une donnée lisible que l'user peut choisir d'exposer.
///
/// Chaque resource est identifiée par un URI stable de type `lifeos://<domain>/<query>`.
/// L'user consent resource par resource (jamais bulk).
struct MCPResource: Sendable, Identifiable, Hashable {
    let id: String            // ex: "lifeos.habits.read"
    let uri: String           // ex: "lifeos://habits/last7days"
    let displayName: String   // ex: "Mes habitudes (7 derniers jours)"
    let description: String   // ex: "Liste des habitudes avec streak et dernière complétion"
    let dataCategory: MCPDataCategory
}

/// Classification des resources — sert à afficher un pictogramme et à
/// grouper les consentements dans l'UI.
enum MCPDataCategory: String, Sendable, CaseIterable {
    case habits, goals, sleep, nutrition, fitness, mood, coachHistory, profile

    var displayName: String {
        switch self {
        case .habits:       return "Habitudes"
        case .goals:        return "Objectifs"
        case .sleep:        return "Sommeil"
        case .nutrition:    return "Nutrition"
        case .fitness:      return "Sport"
        case .mood:         return "Humeur"
        case .coachHistory: return "Historique coach"
        case .profile:      return "Profil"
        }
    }
}

/// Un tool MCP = une action que l'user peut autoriser à un client externe.
///
/// Chaque tool a un schéma JSON strict. L'exécution passe par le
/// `ToolRegistry` existant de LifeOS (allowlist + validation).
struct MCPTool: Sendable, Identifiable, Hashable {
    let id: String                 // ex: "lifeos.tools.createHabit"
    let name: String               // ex: "createHabit"
    let displayName: String        // ex: "Créer une habitude"
    let description: String        // description user-friendly du tool
    let parametersSchema: String   // JSON schema serialized
    let requiresWriteConsent: Bool // true = écrit dans LifeOS ; consentement renforcé
}

/// Payload de consentement — persisté par resource/tool, révocable.
///
/// Stockage prévu : SwiftData (nouveau `@Model MCPConsent`), pas UserDefaults
/// (les consentements sont des données de conformité, pas de préférence).
struct MCPConsent: Sendable, Codable, Hashable {
    let resourceOrToolID: String
    let clientID: String            // identifiant du client MCP (ex: "claude.desktop")
    let grantedAt: Date
    let expiresAt: Date?            // nil = jusqu'à révocation
    let scope: MCPConsentScope

    enum MCPConsentScope: String, Codable, Sendable {
        case readOnce           // usage unique, ré-invite à la prochaine demande
        case readForSession     // ok pendant la session client courante
        case readAlways         // ok jusqu'à révocation manuelle
    }
}

/// Bridge par défaut, non fonctionnel — placeholder qui expose les resources
/// et tools que LifeOS *pourra* proposer une fois l'implémentation MCP faite.
///
/// Sert de documentation vivante : la liste ci-dessous est le contrat que
/// le futur serveur MCP devra satisfaire.
struct DefaultLifeOSMCPBridge: MCPServerBridge {

    let id = "lifeos.mcp.v1"
    let displayName = "LifeOS"

    var availableResources: [MCPResource] {
        [
            MCPResource(
                id: "lifeos.habits.read.week",
                uri: "lifeos://habits/last7days",
                displayName: "Habitudes (7 derniers jours)",
                description: "Liste des habitudes avec streak et dernière complétion",
                dataCategory: .habits
            ),
            MCPResource(
                id: "lifeos.goals.read.active",
                uri: "lifeos://goals/active",
                displayName: "Objectifs actifs",
                description: "Objectifs en cours avec échéance et progression",
                dataCategory: .goals
            ),
            MCPResource(
                id: "lifeos.sleep.read.week",
                uri: "lifeos://sleep/last7days",
                displayName: "Sommeil (7 derniers jours)",
                description: "Durée et qualité de sommeil par nuit",
                dataCategory: .sleep
            ),
            MCPResource(
                id: "lifeos.coach.read.recent",
                uri: "lifeos://coach/last30days",
                displayName: "Historique coach (30 derniers jours)",
                description: "Messages échangés avec le coach — read only",
                dataCategory: .coachHistory
            ),
        ]
    }

    var availableTools: [MCPTool] {
        [
            MCPTool(
                id: "lifeos.tools.createHabit",
                name: "createHabit",
                displayName: "Créer une habitude",
                description: "Ajoute une habitude au tracker de l'user",
                parametersSchema: #"{"type":"object","properties":{"name":{"type":"string"},"frequency":{"type":"string","enum":["daily","weekly"]}}}"#,
                requiresWriteConsent: true
            ),
            MCPTool(
                id: "lifeos.tools.scheduleReminder",
                name: "scheduleReminder",
                displayName: "Planifier un rappel",
                description: "Programme une notification locale à une date/heure",
                parametersSchema: #"{"type":"object","properties":{"title":{"type":"string"},"body":{"type":"string"},"delaySeconds":{"type":"number"}}}"#,
                requiresWriteConsent: true
            ),
        ]
    }

    @MainActor
    var isActive: Bool {
        // Volontairement `false` tant qu'aucune implémentation serveur n'est faite.
        // Un futur flag `@AppStorage(AppStorageKeys.mcpServerEnabled)` viendra
        // gérer l'activation par l'user une fois la phase 2 livrée.
        false
    }
}
