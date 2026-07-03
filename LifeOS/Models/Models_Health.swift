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

/// Une nuit de sommeil enregistrée (coucher → lever) avec sa qualité ressentie.
@Model final class SleepNight {
    var date: Date         // jour de réveil (rattachement)
    var bedtime: Date      // heure de coucher (souvent la veille au soir)
    var wake: Date         // heure de réveil
    var quality: Int       // 1...5
    var note: String
    init(date: Date = .now, bedtime: Date = .now, wake: Date = .now, quality: Int = 3, note: String = "") {
        self.date = date; self.bedtime = bedtime; self.wake = wake; self.quality = quality; self.note = note
    }
    /// Durée de sommeil en heures (gère le passage minuit).
    var hours: Double {
        var secs = wake.timeIntervalSince(bedtime)
        if secs < 0 { secs += 86_400 }
        return max(0, secs / 3600)
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
    var name: String = ""
    var hour: Int = 8
    var minute: Int = 0
    var active: Bool = true
    // Recommandation de prise (calculée par SupplementAdvisor, ajustable par l'utilisateur)
    var moment: String = "matin"      // matin | midi | soir
    var withFood: Bool = true         // avec un repas / à jeun
    var advice: String = ""           // courte explication
    var confirm: Bool = true          // envoyer une notif de confirmation ~1h30 après
    init(name: String = "", hour: Int = 8, minute: Int = 0, active: Bool = true,
         moment: String = "matin", withFood: Bool = true, advice: String = "", confirm: Bool = true) {
        self.name = name; self.hour = hour; self.minute = minute; self.active = active
        self.moment = moment; self.withFood = withFood; self.advice = advice; self.confirm = confirm
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

// MARK: - Santé médicale

@Model final class Medication {
    var name: String
    var dosage: String         // ex: "500mg"
    var frequency: String      // ex: "2x/jour"
    var hourMorning: Int?
    var hourEvening: Int?
    var notes: String
    var startDate: Date
    var endDate: Date?
    var active: Bool
    init(name: String = "", dosage: String = "", frequency: String = "1x/jour",
         hourMorning: Int? = 8, hourEvening: Int? = nil, notes: String = "",
         startDate: Date = .now, endDate: Date? = nil, active: Bool = true) {
        self.name = name; self.dosage = dosage; self.frequency = frequency
        self.hourMorning = hourMorning; self.hourEvening = hourEvening
        self.notes = notes; self.startDate = startDate; self.endDate = endDate; self.active = active
    }
}

@Model final class MedicalAppointment {
    var date: Date
    var specialty: String      // Généraliste, Dentiste, Cardiologue…
    var doctorName: String
    var location: String
    var notes: String
    var nextDate: Date?
    init(date: Date = .now, specialty: String = "", doctorName: String = "",
         location: String = "", notes: String = "", nextDate: Date? = nil) {
        self.date = date; self.specialty = specialty; self.doctorName = doctorName
        self.location = location; self.notes = notes; self.nextDate = nextDate
    }
}

@Model final class VitalRecord {
    var date: Date
    var type: String           // "poids", "tension", "glycémie", "fréquence cardiaque", "autre"
    var value: Double          // valeur principale (kg, mmHg systolique, g/L…)
    var value2: Double?        // diastolique pour tension
    var unit: String
    var notes: String
    init(date: Date = .now, type: String = "poids", value: Double = 0,
         value2: Double? = nil, unit: String = "kg", notes: String = "") {
        self.date = date; self.type = type; self.value = value
        self.value2 = value2; self.unit = unit; self.notes = notes
    }
}

@Model final class Vaccination {
    var name: String           // ex: "Grippe", "COVID-19", "Tétanos"
    var date: Date
    var nextDueDate: Date?
    var lot: String
    var notes: String
    init(name: String = "", date: Date = .now, nextDueDate: Date? = nil, lot: String = "", notes: String = "") {
        self.name = name; self.date = date; self.nextDueDate = nextDueDate; self.lot = lot; self.notes = notes
    }
    var isDue: Bool {
        guard let next = nextDueDate else { return false }
        return next <= Calendar.current.date(byAdding: .day, value: 30, to: .now)!
    }
}
