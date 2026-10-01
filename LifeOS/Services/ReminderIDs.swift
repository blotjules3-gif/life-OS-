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
/// son identifiant, donc l'ancien rappel survit. Le seul ecran qui modifie
/// une ligne (questionnaire Mobilite, renomme le vehicule) annule donc les
/// rappels avec l'ANCIEN nom et l'ancienne date avant de reposer les
/// nouveaux. Le jour ou d'autres modifications apparaissent, il faudra un
/// `stableID` persiste, comme pour les medicaments et les complements.
enum ReminderIDs {

    static func appointment(_ date: Date) -> String {
        "appt-\(Int(date.timeIntervalSince1970))"
    }

    static func vaccination(name: String, nextDate: Date) -> String {
        "vacc-\(name)-\(Int(nextDate.timeIntervalSince1970))"
    }

    // Document, echeance, vehicule: le titre seul ne suffisait pas. Deux
    // documents "Assurance" partageaient un rappel: le second ecrasait le
    // premier, et supprimer l'un faisait taire l'autre. La date entre donc
    // dans l'identifiant. Les formes sans date restent, SEULEMENT pour
    // annuler les rappels poses avant ce correctif.

    static func document(title: String, expiry: Date) -> String {
        "doc-\(title)-\(Int(expiry.timeIntervalSince1970))"
    }
    /// Ancienne forme (titre seul). Annulation des rappels deja poses.
    static func document(title: String) -> String { "doc-\(title)" }

    static func deadline(title: String, date: Date) -> String {
        "deadline-\(title)-\(Int(date.timeIntervalSince1970))"
    }
    /// Ancienne forme (titre seul). Annulation des rappels deja poses.
    static func deadline(title: String) -> String { "deadline-\(title)" }

    static func socialEvent(title: String, date: Date) -> String {
        "event-\(title)-\(Int(date.timeIntervalSince1970))"
    }

    static func vehicleInsurance(name: String, date: Date) -> String {
        "ins-\(name)-\(Int(date.timeIntervalSince1970))"
    }
    static func vehicleService(name: String, date: Date) -> String {
        "serv-\(name)-\(Int(date.timeIntervalSince1970))"
    }
    /// Anciennes formes (nom seul). Annulation des rappels deja poses.
    static func vehicleInsurance(name: String) -> String { "ins-\(name)" }
    static func vehicleService(name: String) -> String { "serv-\(name)" }

    /// Rappel annuel d'anniversaire. Meme forme qu'avant (sortie de la vue
    /// Anniversaires) pour retrouver les rappels deja poses: la suppression
    /// d'un contact doit pouvoir l'annuler, sinon il sonne chaque annee.
    static func birthday(name: String, birthday: Date?) -> String {
        let stamp = Int(birthday?.timeIntervalSince1970 ?? 0)
        return "bday.\(name.replacingOccurrences(of: " ", with: "_")).\(stamp)"
    }

    static func petCare(pet: String, type: String, date: Date) -> String {
        "pet-\(pet)-\(type)-\(Int(date.timeIntervalSince1970))"
    }

    // Tous les identifiants qu'une ligne a pu poser, ancienne forme comprise.
    // La suppression passe par la, et `cancellable` ecarte ceux qu'une autre
    // ligne utilise encore.

    static func documentIDs(title: String, expiry: Date?) -> [String] {
        guard let expiry else { return [] }   // sans expiration, jamais de rappel
        return [document(title: title, expiry: expiry), document(title: title)]
    }

    static func deadlineIDs(title: String, date: Date) -> [String] {
        [deadline(title: title, date: date), deadline(title: title)]
    }

    static func vehicleIDs(name: String, insurance: Date?, service: Date?) -> [String] {
        var ids: [String] = []
        if let insurance { ids.append(vehicleInsurance(name: name, date: insurance)) }
        if let service { ids.append(vehicleService(name: name, date: service)) }
        return ids + [vehicleInsurance(name: name), vehicleService(name: name)]
    }

    /// Identifiants a annuler quand une ligne est supprimee: ceux qu'aucune
    /// ligne restante n'utilise encore. Sans ce filtre, supprimer un doublon
    /// (meme titre, meme date, ou ancienne forme sans date) faisait taire le
    /// rappel de l'autre ligne.
    static func cancellable(_ ids: [String], stillUsedBy remaining: [[String]]) -> [String] {
        let used = Set(remaining.flatMap { $0 })
        var seen = Set<String>()
        return ids.filter { !used.contains($0) && seen.insert($0).inserted }
    }
}
