import Foundation

// Decisions de la frise du widget photo, sans WidgetKit: partagees pour etre testees.

/// Decisions de la frise, sans WidgetKit (lisibles et testables a part).
enum PhotoWidgetTimeline {
    static func state(selectedID: UUID?, configs: [PhotoWidgetConfig]) -> PhotoWidgetDisplayState {
        guard let selectedID else {
            // Pas encore choisi: on prend la plus recente, comme `defaultResult`.
            if let latest = configs.max(by: { $0.updatedAt < $1.updatedAt }) { return .config(latest, photoOffset: 0) }
            return .notChosen(hasConfigs: false)
        }
        guard let c = configs.first(where: { $0.id == selectedID }) else { return .deleted }
        return .config(c, photoOffset: 0)
    }

    static func plan(for c: PhotoWidgetConfig, now: Date, calendar: Calendar = .current) -> (dates: [(date: Date, offset: Int)], reloadAtEnd: Bool) {
        switch c.template {
        case .photo, .collage:
            let slots = PhotoWidgetSchedule.slots(photoCount: c.rotatingPhotos.count, rotation: c.rotation, now: now, calendar: calendar)
            return (slots.map { ($0.date, $0.photoOffset) }, slots.count > 1)
        case .countdown:
            // Le chiffre change a minuit: une entree par jour sur une semaine.
            var dates: [(Date, Int)] = [(now, 0)]
            var next = now
            for _ in 0..<7 {
                next = PhotoWidgetCountdown.nextChange(after: next, calendar: calendar)
                dates.append((next, 0))
            }
            return (dates, true)
        case .note, .goal:
            return ([(now, 0)], false)
        }
    }
}
