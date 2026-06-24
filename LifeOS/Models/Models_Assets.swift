import Foundation
import SwiftData

// MARK: - Investissement & patrimoine

@Model final class Holding {
    var symbol: String
    var kind: String          // Action / Crypto / ETF
    var quantity: Double
    var buyPrice: Double
    var currentPrice: Double
    init(symbol: String = "", kind: String = "Action", quantity: Double = 0, buyPrice: Double = 0, currentPrice: Double = 0) {
        self.symbol = symbol; self.kind = kind; self.quantity = quantity; self.buyPrice = buyPrice; self.currentPrice = currentPrice
    }
    var value: Double { quantity * currentPrice }
    var cost: Double { quantity * buyPrice }
    var pnl: Double { value - cost }
    var pnlPct: Double { cost == 0 ? 0 : pnl / cost * 100 }
}

@Model final class NetWorthItem {
    var name: String
    var kind: String          // Actif / Passif
    var value: Double
    init(name: String = "", kind: String = "Actif", value: Double = 0) {
        self.name = name; self.kind = kind; self.value = value
    }
}

@Model final class Property {
    var name: String
    var value: Double
    var monthlyRent: Double
    var monthlyCharges: Double
    var loanRemaining: Double
    var loanPayment: Double
    init(name: String = "", value: Double = 0, monthlyRent: Double = 0, monthlyCharges: Double = 0, loanRemaining: Double = 0, loanPayment: Double = 0) {
        self.name = name; self.value = value; self.monthlyRent = monthlyRent
        self.monthlyCharges = monthlyCharges; self.loanRemaining = loanRemaining; self.loanPayment = loanPayment
    }
    var monthlyCashflow: Double { monthlyRent - monthlyCharges - loanPayment }
    var netEquity: Double { value - loanRemaining }
}

// MARK: - Carrière

@Model final class JobApplication {
    var company: String
    var role: String
    var status: String        // Repéré / Postulé / Entretien / Offre / Refusé
    var date: Date
    var url: String
    var notes: String
    init(company: String = "", role: String = "", status: String = "Repéré", date: Date = .now, url: String = "", notes: String = "") {
        self.company = company; self.role = role; self.status = status; self.date = date; self.url = url; self.notes = notes
    }
}

@Model final class SkillGap {
    var targetRole: String
    var skill: String
    var acquired: Bool
    var plan: String
    init(targetRole: String = "", skill: String = "", acquired: Bool = false, plan: String = "") {
        self.targetRole = targetRole; self.skill = skill; self.acquired = acquired; self.plan = plan
    }
}

// MARK: - Apprentissage

@Model final class Flashcard {
    var front: String
    var back: String
    var deck: String
    var ease: Double          // facteur SM-2
    var intervalDays: Int
    var due: Date
    var reps: Int
    var createdAt: Date
    init(front: String = "", back: String = "", deck: String = "Général", ease: Double = 2.5, intervalDays: Int = 0, due: Date = .now, reps: Int = 0, createdAt: Date = .now) {
        self.front = front; self.back = back; self.deck = deck; self.ease = ease
        self.intervalDays = intervalDays; self.due = due; self.reps = reps; self.createdAt = createdAt
    }
}

@Model final class BookSummary {
    var title: String
    var author: String
    var keyIdeas: String
    var rating: Int
    var date: Date
    init(title: String = "", author: String = "", keyIdeas: String = "", rating: Int = 4, date: Date = .now) {
        self.title = title; self.author = author; self.keyIdeas = keyIdeas; self.rating = rating; self.date = date
    }
}

// MARK: - Maison

@Model final class Chore {
    var name: String
    var assignee: String
    var frequencyDays: Int
    var lastDone: Date?
    init(name: String = "", assignee: String = "Moi", frequencyDays: Int = 7, lastDone: Date? = nil) {
        self.name = name; self.assignee = assignee; self.frequencyDays = frequencyDays; self.lastDone = lastDone
    }
    var nextDue: Date? { lastDone.map { Calendar.current.date(byAdding: .day, value: frequencyDays, to: $0) ?? $0 } }
}

@Model final class Pet {
    var name: String
    var species: String
    @Relationship(deleteRule: .cascade) var events: [PetCare]
    init(name: String = "", species: String = "Chat") {
        self.name = name; self.species = species; self.events = []
    }
}

@Model final class PetCare {
    var type: String          // Gamelle / Vétérinaire / Vaccin / Anti-puces
    var date: Date
    var note: String
    var recurringDays: Int     // 0 = ponctuel
    init(type: String = "Gamelle", date: Date = .now, note: String = "", recurringDays: Int = 0) {
        self.type = type; self.date = date; self.note = note; self.recurringDays = recurringDays
    }
}

@Model final class Maintenance {
    var name: String
    var lastDone: Date?
    var intervalDays: Int
    var note: String
    init(name: String = "", lastDone: Date? = nil, intervalDays: Int = 90, note: String = "") {
        self.name = name; self.lastDone = lastDone; self.intervalDays = intervalDays; self.note = note
    }
    var nextDue: Date? { lastDone.map { Calendar.current.date(byAdding: .day, value: intervalDays, to: $0) ?? $0 } }
}

// MARK: - Mobilité

@Model final class Vehicle {
    var name: String
    var insuranceRenewal: Date?
    var nextService: Date?
    var note: String
    @Relationship(deleteRule: .cascade) var fuelLogs: [FuelLog]
    init(name: String = "", insuranceRenewal: Date? = nil, nextService: Date? = nil, note: String = "") {
        self.name = name; self.insuranceRenewal = insuranceRenewal; self.nextService = nextService; self.note = note
        self.fuelLogs = []
    }
}

@Model final class FuelLog {
    var date: Date
    var liters: Double
    var pricePerL: Double
    var odometer: Int
    init(date: Date = .now, liters: Double = 0, pricePerL: Double = 0, odometer: Int = 0) {
        self.date = date; self.liters = liters; self.pricePerL = pricePerL; self.odometer = odometer
    }
    var total: Double { liters * pricePerL }
}

// MARK: - Social

@Model final class Contact {
    var name: String
    var lastSeen: Date?
    var cadenceDays: Int
    var birthday: Date?
    var giftIdeas: String
    var notes: String
    init(name: String = "", lastSeen: Date? = nil, cadenceDays: Int = 30, birthday: Date? = nil, giftIdeas: String = "", notes: String = "") {
        self.name = name; self.lastSeen = lastSeen; self.cadenceDays = cadenceDays
        self.birthday = birthday; self.giftIdeas = giftIdeas; self.notes = notes
    }
    var isOverdue: Bool {
        guard let lastSeen else { return true }
        let next = Calendar.current.date(byAdding: .day, value: cadenceDays, to: lastSeen) ?? lastSeen
        return next < Date()
    }
}

@Model final class SocialEvent {
    var title: String
    var date: Date
    var location: String
    var note: String
    init(title: String = "", date: Date = .now, location: String = "", note: String = "") {
        self.title = title; self.date = date; self.location = location; self.note = note
    }
}

// MARK: - Admin

@Model final class DocVault {
    var title: String
    var category: String      // Identité / Contrat / Garantie / Santé / Impôts
    var filename: String?
    var expiry: Date?
    var note: String
    init(title: String = "", category: String = "Identité", filename: String? = nil, expiry: Date? = nil, note: String = "") {
        self.title = title; self.category = category; self.filename = filename; self.expiry = expiry; self.note = note
    }
}

@Model final class Deadline {
    var title: String
    var date: Date
    var kind: String          // Impôts / Assurance / Abonnement / Autre
    var note: String
    init(title: String = "", date: Date = .now, kind: String = "Autre", note: String = "") {
        self.title = title; self.date = date; self.kind = kind; self.note = note
    }
}

// MARK: - Voyage

@Model final class Trip {
    var name: String
    var destination: String
    var start: Date
    var end: Date
    var budget: Double
    var notes: String
    @Relationship(deleteRule: .cascade) var packing: [PackingItem]
    init(name: String = "", destination: String = "", start: Date = .now, end: Date = .now, budget: Double = 0, notes: String = "") {
        self.name = name; self.destination = destination; self.start = start; self.end = end
        self.budget = budget; self.notes = notes; self.packing = []
    }
}

@Model final class PackingItem {
    var name: String
    var packed: Bool
    var category: String
    init(name: String = "", packed: Bool = false, category: String = "Vêtements") {
        self.name = name; self.packed = packed; self.category = category
    }
}
