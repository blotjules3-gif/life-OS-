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
    init(title: String = "", notes: String = "", due: Date? = nil, done: Bool = false,
         priority: Int = 0, project: String = "Perso", blockStart: Date? = nil, blockEnd: Date? = nil) {
        self.title = title; self.notes = notes; self.due = due; self.done = done
        self.priority = priority; self.project = project; self.blockStart = blockStart; self.blockEnd = blockEnd
    }
}

@Model final class Habit {
    var name: String
    var icon: String
    var colorHex: Int
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var completions: [HabitCompletion]
    init(name: String = "", icon: String = "checkmark", colorHex: Int = 0x4CC38A, createdAt: Date = .now) {
        self.name = name; self.icon = icon; self.colorHex = colorHex; self.createdAt = createdAt
        self.completions = []
    }
}

@Model final class HabitCompletion {
    var date: Date
    init(date: Date = .now) { self.date = date }
}

@Model final class Note {
    var title: String
    var body: String
    var tags: String
    var created: Date
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

    init(content: String, category: String = "fait", source: String = "chat", created: Date = .now, isPinned: Bool = false) {
        self.content = content
        self.category = category
        self.source = source
        self.created = created
        self.isPinned = isPinned
    }

    var categoryIcon: String {
        switch category {
        case "objectif":    return "target"
        case "préférence":  return "heart.fill"
        case "habitude":    return "arrow.clockwise"
        case "santé":       return "cross.fill"
        default:            return "brain"
        }
    }
    var categoryColor: Color {
        switch category {
        case "objectif":    return Color(hex: 0x00D4B4)
        case "préférence":  return Color(hex: 0xF1746C)
        case "habitude":    return Color(hex: 0x9B6CF1)
        case "santé":       return Color(hex: 0x4CC38A)
        default:            return Color(hex: 0x3CB2E0)
        }
    }
}

// MARK: - Finances

@Model final class Account {
    var name: String
    var kind: String         // Courant / Épargne / Cash
    var balance: Double
    init(name: String = "", kind: String = "Courant", balance: Double = 0) {
        self.name = name; self.kind = kind; self.balance = balance
    }
}

@Model final class Txn {
    var date: Date
    var amount: Double       // négatif = dépense
    var category: String
    var account: String
    var note: String
    init(date: Date = .now, amount: Double = 0, category: String = "Divers", account: String = "Courant", note: String = "") {
        self.date = date; self.amount = amount; self.category = category; self.account = account; self.note = note
    }
}

@Model final class Envelope {
    var name: String
    var monthlyBudget: Double
    var spent: Double
    var colorHex: Int
    init(name: String = "", monthlyBudget: Double = 0, spent: Double = 0, colorHex: Int = 0x618EF1) {
        self.name = name; self.monthlyBudget = monthlyBudget; self.spent = spent; self.colorHex = colorHex
    }
    var remaining: Double { monthlyBudget - spent }
    var progress: Double { monthlyBudget == 0 ? 0 : min(1, spent / monthlyBudget) }
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
