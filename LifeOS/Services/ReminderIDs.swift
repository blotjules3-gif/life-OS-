import Foundation

/// Identifiants des rappels ponctuels, en un seul endroit.
///
/// Le defaut corrige: chaque ecran fabriquait son identifiant a la main, au
/// moment de poser la notification, et NULLE PART au moment de supprimer la
/// ligne. Resultat, supprimer un rendez vous medical, un document, une
/// echeance, un evenement, un vehicule ou un animal laissait son rappel en
/// place. On recevait "RDV Généraliste demain" pour un rendez vous annule il
/// y a trois semaines, sans aucun moyen de le faire taire.
///
/// La regle: une notification posee doit pouvoir etre retrouvee. L'identifiant
/// est donc derive du contenu, ici, et les deux cotes appellent la meme
/// fonction. Une copie de la formule dans la vue redeviendrait fausse au
/// premier changement.
///
/// Note sur les identifiants derives du contenu: renommer une ligne change
/// son identifiant, donc l'ancien rappel survit. Aucun de ces ecrans ne
/// permet de modifier une ligne, seulement de la creer ou de la supprimer,
/// donc le cas ne se pose pas. Le jour ou une modification apparait, il
/// faudra un `stableID` persiste, comme pour les medicaments et les
/// complements.
enum ReminderIDs {

    static func appointment(_ date: Date) -> String {
        "appt-\(Int(date.timeIntervalSince1970))"
    }

    static func vaccination(name: String, nextDate: Date) -> String {
        "vacc-\(name)-\(Int(nextDate.timeIntervalSince1970))"
    }

    static func document(title: String) -> String { "doc-\(title)" }

    static func deadline(title: String) -> String { "deadline-\(title)" }

    static func socialEvent(title: String, date: Date) -> String {
        "event-\(title)-\(Int(date.timeIntervalSince1970))"
    }

    static func vehicleInsurance(name: String) -> String { "ins-\(name)" }
    static func vehicleService(name: String) -> String { "serv-\(name)" }

    static func petCare(pet: String, type: String, date: Date) -> String {
        "pet-\(pet)-\(type)-\(Int(date.timeIntervalSince1970))"
    }
}
