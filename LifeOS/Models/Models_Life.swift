import Foundation
import SwiftData
import SwiftUI

// MARK: - Looksmaxx

@Model final class ProgressPhoto {
    var date: Date
    var filename: String
    var category: String     // Visage / Peau / Corps
    var note: String
    init(date: Date = .now, filename: String = "", category: String = "Visage", note: String = "") {
        self.date = date; self.filename = filename; self.category = category; self.note = note
    }
}

@Model final class WardrobeItem {
    var name: String
    var category: String     // Haut / Bas / Chaussures / Veste / Accessoire
    var colorName: String
    var warmth: Int          // 1 (léger) ... 3 (chaud)
    var filename: String?
    init(name: String = "", category: String = "Haut", colorName: String = "Noir", warmth: Int = 2, filename: String? = nil) {
        self.name = name; self.category = category; self.colorName = colorName; self.warmth = warmth; self.filename = filename
    }
}

// MARK: - Mental

@Model final class MoodEntry {
    var date: Date
    var score: Int           // 1...5
    var note: String
    var gratitude: String
    init(date: Date = .now, score: Int = 3, note: String = "", gratitude: String = "") {
        self.date = date; self.score = score; self.note = note; self.gratitude = gratitude
    }
}

// MARK: - Productivité

@Model final class TodoItem {
    var title: String
    var notes: String
    var due: Date?
    var done: Bool
    var priority: Int        // 0 normal, 1 important, 2 urgent
    var project: String
    var blockStart: Date?
    var blockEnd: Date?
    var recurringDaysRaw: String = ""
    // Lot 7 (Todoo / Structurd). Tous additifs avec valeur par defaut: les
    // anciennes taches s'ouvrent telles quelles.
    /// Identifiant stable des rappels et du planning. Vide sur les anciennes
    /// taches: `TodoIDs.ensure` le remplit (jamais de valeur par defaut partagee).
    var uid: String = ""
    var section: String = ""
    /// Etiquettes separees par des virgules.
    var tagsRaw: String = ""
    /// Sous-taches, une par ligne: « [ ] texte » ou « [x] texte ».
    var checklistRaw: String = ""
    /// "" = recurrence par jours de semaine (recurringDaysRaw), "monthly" = chaque mois.
    var recurrenceRule: String = ""
    /// -1 aucun rappel, 0 a l'heure, sinon minutes avant l'echeance.
    var reminderMinutes: Int = -1
    /// Duree estimee en minutes, 0 = 60 min (ancien comportement du planning).
    var estimateMinutes: Int = 0
    /// Creneau pose a la main: le planning automatique ne le deplace jamais.
    var blockLocked: Bool = false
    var completedAt: Date?

    init(title: String = "", notes: String = "", due: Date? = nil, done: Bool = false,
         priority: Int = 0, project: String = "Perso", blockStart: Date? = nil, blockEnd: Date? = nil,
         recurringDaysRaw: String = "") {
        self.title = title; self.notes = notes; self.due = due; self.done = done
        self.priority = priority; self.project = project; self.blockStart = blockStart; self.blockEnd = blockEnd
        self.recurringDaysRaw = recurringDaysRaw
    }

    var isOverdue: Bool {
        guard let due, !done else { return false }
        return due < Date.now
    }

    /// Jours de la semaine de récurrence (1=Dim, 2=Lun, 3=Mar, 4=Mer, 5=Jeu, 6=Ven, 7=Sam)
    var recurringDays: Set<Int> {
        get { Set(recurringDaysRaw.split(separator: ",").compactMap { Int($0) }) }
        set { recurringDaysRaw = newValue.sorted().map(String.init).joined(separator: ",") }
    }

    func applies(to date: Date) -> Bool {
        if recurringDays.isEmpty {
            guard let due else { return true }
            return Calendar.current.isDate(due, inSameDayAs: date) || (due < date && !done)
        } else {
            let weekday = Calendar.current.component(.weekday, from: date)
            return recurringDays.contains(weekday)
        }
    }
}

@Model final class Habit {
    var name: String
    var icon: String
    var colorHex: Int
    var createdAt: Date
    var isPending: Bool
    var isArchived: Bool
    var moduleTag: String
    var scheduledHour: Int
    var scheduledMinute: Int
    /// Loop 25 audit — UUID du `UserGoal` qui a créé cette habitude (via
    /// GoalPlanExecutor). Vide = habitude créée manuellement.
    /// Permet de propager archive/delete du goal aux habits associées.
    var sourceGoalID: String = ""
    /// Jours actifs (1=Dim, 2=Lun, 3=Mar, 4=Mer, 5=Jeu, 6=Ven, 7=Sam).
    var activeDaysRaw: String = "1,2,3,4,5,6,7"
    /// Identifiant stable, utilise par les widgets et les notifications (jamais le
    /// nom, que deux habitudes peuvent partager). Vide sur les anciennes fiches:
    /// `HabitSync.ensureIDs` le remplit au lancement.
    var uid: String = ""
    // Lot 7 (Habitly). Additifs avec valeur par defaut.
    /// 0 simple (fait / pas fait), 1 quantite, 2 duree en minutes.
    var targetKind: Int = 0
    var targetValue: Double = 0
    var targetUnit: String = ""
    /// 0 = suit les jours actifs; sinon « x fois par semaine ».
    var weeklyTarget: Int = 0
    /// Jours sautes ou en pause, « aaaa-mm-jj » separes par des virgules.
    var skippedDaysRaw: String = ""
    /// Dernier jour de pause (inclus), nil = pas en pause.
    var pausedUntil: Date?
    /// Progression du jour pour une habitude a objectif (jour « aaaa-mm-jj »).
    var progressDay: String = ""
    var progressValue: Double = 0
    @Relationship(deleteRule: .cascade) var completions: [HabitCompletion]
    init(name: String = "", icon: String = "checkmark", colorHex: Int = 0x4CC38A, createdAt: Date = .now, isPending: Bool = false, isArchived: Bool = false, moduleTag: String = "", scheduledHour: Int = 9, scheduledMinute: Int = 0, sourceGoalID: String = "", activeDaysRaw: String = "1,2,3,4,5,6,7") {
        self.name = name; self.icon = icon; self.colorHex = colorHex; self.createdAt = createdAt
        self.isPending = isPending; self.isArchived = isArchived; self.moduleTag = moduleTag
        self.scheduledHour = scheduledHour; self.scheduledMinute = scheduledMinute
        self.sourceGoalID = sourceGoalID
        self.activeDaysRaw = activeDaysRaw
        self.uid = UUID().uuidString
        self.completions = []
    }

    /// Jours de la semaine actifs (1=Dim, 2=Lun, 3=Mar, 4=Mer, 5=Jeu, 6=Ven, 7=Sam)
    var activeDays: Set<Int> {
        get {
            let set = Set(activeDaysRaw.split(separator: ",").compactMap { Int($0) })
            return set.isEmpty ? Set(1...7) : set
        }
        set {
            activeDaysRaw = newValue.sorted().map(String.init).joined(separator: ",")
        }
    }

    func isActive(on date: Date = .now) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return activeDays.contains(weekday)
    }
}

@Model final class HabitCompletion {
    var date: Date
    /// Valeur atteinte (quantite ou minutes) pour une habitude a objectif, 0 sinon.
    var value: Double = 0
    init(date: Date = .now) { self.date = date }
}

@Model final class Note {
    var title: String
    var body: String
    var tags: String
    var created: Date
    // Lot 7 (Notio). Additifs avec valeur par defaut.
    /// Dossier, chemin imbrique avec « / » (ex: « Travail/Clients »). Vide = racine.
    var folder: String = ""
    var modified: Date?
    /// Versions precedentes (JSON, NoteHistory), les plus recentes a la fin.
    var historyRaw: String = ""
    init(title: String = "", body: String = "", tags: String = "", created: Date = .now) {
        self.title = title; self.body = body; self.tags = tags; self.created = created
    }
}

// MARK: - Mémoire LifeOS

@Model final class MemoryEntry {
    var content: String        // "J'aime courir le matin", "Objectif : perdre 5kg"
    var category: String       // "préférence", "objectif", "habitude", "fait"
    var source: String         // "chat", "profil", "auto"
    var created: Date
    var isPinned: Bool
    /// Type de rétention — session (transitoire), short (< 30j), long (durable),
    /// episodic (événement ponctuel avec date). Défaut `long`.
    var retentionType: String = "long"
    /// Nombre de fois où l'info a été re-mentionnée / confirmée. Boost au score.
    var confirmationCount: Int = 0
    /// Dernière fois qu'elle a été utilisée dans un prompt coach (retrieval).
    var lastAccessedAt: Date = Date.distantPast

    init(content: String, category: String = "fait", source: String = "chat",
         created: Date = .now, isPinned: Bool = false, retentionType: String = "long") {
        self.content = content
        self.category = category
        self.source = source
        self.created = created
        self.isPinned = isPinned
        self.retentionType = retentionType
        self.confirmationCount = 0
        self.lastAccessedAt = .distantPast
    }
}

/// Types de rétention pour MemoryEntry — utilisé par MemoryRetrieval pour scorer.
enum MemoryRetention: String {
    case session    // vie limitée à la conversation courante
    case short      // < 30 jours utile
    case long       // durable (défaut)
    case episodic   // événement daté (ex: "j'ai été malade la semaine du 5 août")

    /// Poids multiplicatif dans le score de retrieval — long > episodic > short > session.
    var weight: Double {
        switch self {
        case .long: return 1.0
        case .episodic: return 0.8
        case .short: return 0.6
        case .session: return 0.3
        }
    }
}

// MARK: - Finances

@Model final class Account {
    /// Identite STABLE. Les operations se rattachaient au NOM du compte : renommer un
    /// compte orphelinait tout son historique. Le nom reste pour l'affichage seulement.
    var id: UUID = UUID()
    var name: String
    var kind: String         // Courant / Épargne / Cash

    /// Solde d'OUVERTURE, figé. Ce n'est pas le solde courant.
    var openingBalance: Double = 0
    /// Stored with the account, so restoring or switching stores cannot skip migration.
    var openingBalanceMigrationVersion: Int = 0

    /// Solde courant, CALCULE puis mis en cache par `LedgerService`, jamais modifie a la
    /// main. Avant, chaque ecran ajoutait/retirait lui meme : un ajout l'augmentait, une
    /// suppression ne le remettait pas, une modification comptait deux fois. Le solde
    /// derivait donc silencieusement des vraies operations.
    var balance: Double

    init(name: String = "", kind: String = "Courant", balance: Double = 0) {
        self.name = name; self.kind = kind
        self.openingBalance = balance
        self.openingBalanceMigrationVersion = 1
        self.balance = balance
    }
}

@Model final class Txn {
    var id: UUID = UUID()
    var date: Date
    /// Montant en CENTIMES, entier. Un Double accumule des erreurs de virgule flottante
    /// sur une somme d'operations, et un solde bancaire faux d'un centime est un bug.
    /// `amount` reste exposé en euros pour les appelants existants.
    var amountCents: Int = 0
    var category: String
    /// Rattachement STABLE au compte. `account` (le nom) ne sert plus qu'a la reprise des
    /// anciennes donnees et a l'affichage.
    var accountID: UUID?
    var account: String
    var note: String

    /// ANCIENNE colonne, conservee VOLONTAIREMENT.
    ///
    /// Elle avait ete remplacee par une propriete calculee. Consequence que je n'avais
    /// pas vue : SwiftData supprime alors la colonne, et toutes les operations deja
    /// enregistrees repartaient a 0. C'est une perte de donnees a la mise a jour, sur de
    /// l'argent. La colonne reste donc stockee, `amountCents` fait autorite, et
    /// `setAmount` garde les deux d'accord. Elle ne pourra etre retiree que par une
    /// migration versionnee, apres conversion.
    var amount: Double = 0

    /// Montant en euros, lu depuis l'autorite (les centimes).
    var amountValue: Double { Double(amountCents) / 100.0 }

    /// SEUL point d'ecriture du montant : il maintient les deux colonnes ensemble.
    func setAmount(_ euros: Double) {
        amountCents = Int((euros * 100).rounded())
        amount = Double(amountCents) / 100.0
    }

    init(date: Date = .now, amount: Double = 0, category: String = "Divers", account: String = "Courant", note: String = "", accountID: UUID? = nil) {
        self.date = date; self.category = category; self.account = account; self.note = note
        self.accountID = accountID
        self.amountCents = Int((amount * 100).rounded())
        self.amount = Double(self.amountCents) / 100.0
    }
}

@Model final class Envelope {
    var name: String
    var monthlyBudget: Double
    /// ANCIENNE colonne : un montant saisi a la main (+10 / -10), remis a zero chaque mois,
    /// donc sans historique. Conservee pour la migration (`EnvelopeMigration`), qui la
    /// convertit une fois en `EnvelopeEntry`. Plus lue par les ecrans.
    var spent: Double
    var colorHex: Int
    /// Ancien marqueur de mois de `spent`. Sert seulement a dater l'ecriture de reprise.
    var periodStart: Date = Date.distantPast
    /// Identifiant stable, pose a la migration (nil pour les enveloppes d'avant : une
    /// valeur par defaut serait LA MEME pour toutes les lignes existantes).
    var uid: UUID?
    /// Categorie des operations bancaires (Bankino) comptees dans l'enveloppe. Vide = le nom.
    var linkedCategory: String = ""
    /// Le reste (ou le depassement) d'un mois passe au suivant, comme YNAB.
    var carryOver: Bool = false
    /// Premier mois de l'enveloppe (point de depart du report).
    var createdAt: Date = Date.distantPast
    /// L'ancien `spent` a deja ete converti en ecriture.
    var migratedSpent: Bool = false

    init(name: String = "", monthlyBudget: Double = 0, spent: Double = 0,
         colorHex: Int = 0x618EF1, periodStart: Date = .now) {
        self.name = name; self.monthlyBudget = monthlyBudget; self.spent = spent
        self.colorHex = colorHex; self.periodStart = periodStart
        self.uid = UUID(); self.createdAt = periodStart
        // Une enveloppe neuve n'a pas d'ancien montant a convertir... sauf celles creees
        // avec un `spent` (donnees de demonstration) : la migration s'en charge.
        self.migratedSpent = spent == 0
    }

    /// Categorie comptee : la categorie liee, sinon le nom de l'enveloppe.
    var countedCategory: String { linkedCategory.isEmpty ? name : linkedCategory }
}

/// Une depense rangee dans une enveloppe, datee. Remplace les boutons +10 / -10 :
/// chaque mois garde ses depenses, et une correction se fait sur l'ecriture elle-meme.
@Model final class EnvelopeEntry {
    var envelopeUID: UUID
    var date: Date
    var amountCents: Int
    var note: String
    init(envelopeUID: UUID, date: Date = .now, amountCents: Int, note: String = "") {
        self.envelopeUID = envelopeUID; self.date = date; self.amountCents = amountCents; self.note = note
    }
    var amount: Double { Double(amountCents) / 100 }
}

@Model final class Subscription {
    var name: String
    var amount: Double
    var cycle: String        // Mensuel / Annuel
    var nextDate: Date
    var active: Bool
    init(name: String = "", amount: Double = 0, cycle: String = "Mensuel", nextDate: Date = .now, active: Bool = true) {
        self.name = name; self.amount = amount; self.cycle = cycle; self.nextDate = nextDate; self.active = active
    }
    var monthlyCost: Double { cycle == "Annuel" ? amount / 12 : amount }
}

@Model final class SavingsGoal {
    var name: String
    var target: Double
    var current: Double
    var monthly: Double
    init(name: String = "", target: Double = 0, current: Double = 0, monthly: Double = 0) {
        self.name = name; self.target = target; self.current = current; self.monthly = monthly
    }
    var progress: Double { target == 0 ? 0 : min(1, current / target) }
    var monthsLeft: Int { monthly <= 0 ? 0 : Int(ceil(max(0, target - current) / monthly)) }
}

@Model final class SplitExpense {
    var group: String
    var payer: String
    var amount: Double
    var desc: String
    var date: Date
    var participants: String   // CSV de noms
    init(group: String = "Coloc", payer: String = "Moi", amount: Double = 0, desc: String = "", date: Date = .now, participants: String = "") {
        self.group = group; self.payer = payer; self.amount = amount; self.desc = desc; self.date = date; self.participants = participants
    }
}
