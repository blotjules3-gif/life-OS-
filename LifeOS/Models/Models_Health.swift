import Foundation
import SwiftData

// MARK: - Sommeil

@Model final class DreamEntry {
    var date: Date
    var title: String
    var text: String
    var mood: Int          // 1...5
    var audioFilename: String?
    init(date: Date = .now, title: String = "", text: String = "", mood: Int = 3, audioFilename: String? = nil) {
        self.date = date; self.title = title; self.text = text; self.mood = mood; self.audioFilename = audioFilename
    }
}

// MARK: - Nutrition

@Model final class FoodEntry {
    var date: Date
    var name: String
    var calories: Int
    var protein: Double
    var carbs: Double
    var fat: Double
    var meal: String       // Petit-déj / Déjeuner / Dîner / Collation
    init(date: Date = .now, name: String = "", calories: Int = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0, meal: String = "Déjeuner") {
        self.date = date; self.name = name; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat; self.meal = meal
    }
}

@Model final class FastingSession {
    var start: Date
    var end: Date?
    var targetHours: Int
    init(start: Date = .now, end: Date? = nil, targetHours: Int = 16) {
        self.start = start; self.end = end; self.targetHours = targetHours
    }
    var isActive: Bool { end == nil }
    var elapsed: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

@Model final class WaterEntry {
    var date: Date
    var amountML: Int
    init(date: Date = .now, amountML: Int = 0) { self.date = date; self.amountML = amountML }
}

@Model final class Supplement {
    var name: String
    var hour: Int
    var minute: Int
    var active: Bool
    init(name: String = "", hour: Int = 8, minute: Int = 0, active: Bool = true) {
        self.name = name; self.hour = hour; self.minute = minute; self.active = active
    }
}

/// Item de stock — sert au frigo (Nutrition) ET à l'anti-gaspi/péremption (Maison).
@Model final class PantryItem {
    var name: String
    var quantity: String
    var category: String     // Légume, Protéine, Laitier, Épicerie...
    var location: String     // Frigo / Placard / Congélateur
    var expiry: Date?
    init(name: String = "", quantity: String = "1", category: String = "Épicerie", location: String = "Frigo", expiry: Date? = nil) {
        self.name = name; self.quantity = quantity; self.category = category
        self.location = location; self.expiry = expiry
    }
}

@Model final class ShoppingItem {
    var name: String
    var quantity: String
    var aisle: String
    var checked: Bool
    init(name: String = "", quantity: String = "1", aisle: String = "Divers", checked: Bool = false) {
        self.name = name; self.quantity = quantity; self.aisle = aisle; self.checked = checked
    }
}

// MARK: - Fitness

@Model final class WorkoutSet {
    var date: Date
    var exercise: String
    var weightKg: Double
    var reps: Int
    var rpe: Double
    init(date: Date = .now, exercise: String = "", weightKg: Double = 0, reps: Int = 0, rpe: Double = 8) {
        self.date = date; self.exercise = exercise; self.weightKg = weightKg; self.reps = reps; self.rpe = rpe
    }
    var volume: Double { weightKg * Double(reps) }
    /// Charge 1RM estimée (formule d'Epley).
    var estimated1RM: Double { reps <= 1 ? weightKg : weightKg * (1 + Double(reps) / 30.0) }
}

@Model final class StepEntry {
    var day: Date
    var steps: Int
    init(day: Date = .now, steps: Int = 0) { self.day = day; self.steps = steps }
}
