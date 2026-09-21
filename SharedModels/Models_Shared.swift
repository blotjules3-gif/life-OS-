import Foundation
import SwiftData

// Deux modeles sortis des ecrans ou ils etaient declares (cycle, coach),
// pour que l'app Apple Watch puisse compiler TOUS les modeles sans embarquer
// ces ecrans iPhone. Deplacer une classe de fichier ne change rien a la base.

// MARK: - Modèle cycle

@Model
final class CycleEntry {
    var date: Date = .now
    var flow: Int = 0  // 0 = aucun, 1 = léger, 2 = moyen, 3 = abondant
    var symptoms: [String] = []
    var mood: Int = 0  // 0 = non renseigné, 1–5
    var note: String = ""

    init(date: Date = .now, flow: Int = 1, symptoms: [String] = [], mood: Int = 0, note: String = "") {
        self.date = date
        self.flow = flow
        self.symptoms = symptoms
        self.mood = mood
        self.note = note
    }
}

// MARK: - Persistent message model

@Model
final class AIMessage {
    var id: UUID = UUID()
    var role: String = ""  // "user" | "assistant"
    var text: String = ""
    var date: Date = .now
    var actions: Data?  // JSON-encoded [AIAction]

    init(role: String, text: String, date: Date = .now, actions: Data? = nil) {
        self.id = UUID()
        self.role = role
        self.text = text
        self.date = date
        self.actions = actions
    }
}
