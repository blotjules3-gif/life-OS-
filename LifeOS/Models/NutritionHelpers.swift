import Foundation

// Helpers partagés pour éviter la duplication de logique nutrition dans les vues.

extension Array where Element == FoodEntry {
    var caloriesToday: Int {
        filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.calories }
    }

    var proteinToday: Double {
        filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.protein }
    }
}

extension Array where Element == WaterEntry {
    var mlToday: Int {
        filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amountML }
    }
}
