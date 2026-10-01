import Foundation
import SwiftData

// MARK: - Sommeil, modeles ajoutes (lot 7)
//
// DreamEntry et SleepNight vivent dans Models_Health.swift et ne doivent pas
// changer de schema ici. Les infos en plus (tags, transcription, delai
// d'endormissement, source Sante) passent par des modeles compagnons relies
// par une relation a sens unique: rien ne bouge dans les tables existantes.

/// Une sieste Pzazz: ce qui etait prevu et ce qui s'est passe.
@Model final class NapSession {
    var start: Date = Date()
    var plannedMinutes: Int = 20
    /// nil tant que la sieste tourne.
    var end: Date?
    /// Vrai si la sieste est allee au bout, faux si arretee avant.
    var completed: Bool = false
    /// Paysage sonore joue pendant la sieste ("" = aucun).
    var soundscape: String = ""

    init(start: Date = .now, plannedMinutes: Int, soundscape: String = "") {
        self.start = start
        self.plannedMinutes = plannedMinutes
        self.soundscape = soundscape
    }

    var plannedEnd: Date { start.addingTimeInterval(TimeInterval(plannedMinutes * 60)) }
    /// Duree reelle en minutes, nil si la sieste n'est pas finie.
    var actualMinutes: Double? { end.map { max(0, $0.timeIntervalSince(start)) / 60 } }
}

/// Element de la checklist du soir (Rize), ecrit par l'utilisateur.
@Model final class EveningChecklistItem {
    var title: String = ""
    var detail: String = ""
    var order: Int = 0
    var createdAt: Date = Date()

    init(title: String, detail: String = "", order: Int = 0) {
        self.title = title
        self.detail = detail
        self.order = order
    }
}

/// Ce qui a ete coche un soir donne (historique de la routine).
@Model final class EveningChecklistDay {
    /// Debut du jour du soir (voir EveningRoutine.eveningDay).
    var day: Date = Date()
    var doneTitles: [String] = []
    /// Nombre d'elements dans la checklist ce soir-la, pour afficher "3 / 5".
    var totalItems: Int = 0

    init(day: Date, doneTitles: [String] = [], totalItems: Int = 0) {
        self.day = day
        self.doneTitles = doneTitles
        self.totalItems = totalItems
    }
}

/// Tags et transcription d'un reve (Awaken).
@Model final class DreamDetails {
    @Relationship(deleteRule: .nullify) var dream: DreamEntry?
    var tags: [String] = []
    var transcript: String = ""
    var transcribedAt: Date?

    init(dream: DreamEntry, tags: [String] = [], transcript: String = "") {
        self.dream = dream
        self.tags = tags
        self.transcript = transcript
    }
}

/// Infos d'une nuit qui ne tiennent pas dans SleepNight (Sleep Circle).
@Model final class SleepNightDetails {
    @Relationship(deleteRule: .nullify) var night: SleepNight?
    /// Minutes entre le coucher et l'endormissement.
    var latencyMinutes: Int = 15
    /// "manuel" ou "sante".
    var source: String = "manuel"
    /// Eveils pendant la nuit (connus seulement depuis Sante).
    var awakeMinutes: Int = 0

    init(night: SleepNight, latencyMinutes: Int, source: String = "manuel", awakeMinutes: Int = 0) {
        self.night = night
        self.latencyMinutes = latencyMinutes
        self.source = source
        self.awakeMinutes = awakeMinutes
    }
}

/// Mesure Sante DATEE gardee sur l'appareil (Whoosh): sert a la ligne de base
/// personnelle. Une mesure sans date n'entre jamais ici.
@Model final class RecoveryReading {
    /// "hrv" (ms) ou "rhr" (bpm).
    var kind: String = ""
    var value: Double = 0
    var measuredAt: Date = Date()

    init(kind: String, value: Double, measuredAt: Date) {
        self.kind = kind
        self.value = value
        self.measuredAt = measuredAt
    }
}
