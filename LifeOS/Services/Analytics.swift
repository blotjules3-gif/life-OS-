import Foundation

/// Analytics 100 % local — logue les events clés dans un fichier JSONL du
/// sandbox app, jamais transmis. Sert au reporting Station F (activation,
/// retention, first-tap timing) et à te faire des dashboards perso.
///
/// L'utilisateur peut exporter le fichier via `DataExporter` ou le regarder
/// depuis Xcode Console (via `printSummary()` en debug).
///
/// Vocabulaire des events canoniques :
/// - `app.first_launch` — 1ère ouverture après install
/// - `onboarding.started` / `onboarding.completed` / `quickstart.completed`
/// - `habit.created` / `habit.toggled` / `streak.milestone` (7/14/30/100)
/// - `mood.logged` / `sleep.logged` / `water.logged` / `food.logged`
/// - `coach.opened` / `coach.replied`
/// - `notif.smart.pushed` / `notif.smart.tapped`
/// - `widget.installed` (inféré via App Group ping) / `widget.tap`
@MainActor
enum Analytics {

    struct Event: Codable {
        let ts: Double
        let name: String
        let props: [String: String]
    }

    /// Logue un event. Écriture asynchrone, jamais bloquante.
    static func log(_ name: String, _ props: [String: String] = [:]) {
        let event = Event(ts: Date().timeIntervalSince1970, name: name, props: props)
        Task.detached(priority: .background) {
            await append(event)
        }
        // Marquer first_launch une seule fois
        if !UserDefaults.standard.bool(forKey: "analytics.firstLaunchLogged") && name == "app.launch" {
            UserDefaults.standard.set(true, forKey: "analytics.firstLaunchLogged")
            let firstEvent = Event(ts: Date().timeIntervalSince1970, name: "app.first_launch", props: [:])
            Task.detached(priority: .background) { await append(firstEvent) }
        }
    }

    /// Metrics dérivées utilisables dans un rapport Station F.
    static func summary() -> Summary {
        let events = readAll()
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        // Jours actifs distincts sur les 30 derniers jours
        let cutoff30 = today.addingTimeInterval(-30 * 86400)
        let activeDays = Set(events
            .filter { Date(timeIntervalSince1970: $0.ts) > cutoff30 }
            .map { cal.startOfDay(for: Date(timeIntervalSince1970: $0.ts)) })

        // D1 retention proxy : jour 1 après first_launch a-t-il un launch ?
        let firstLaunch = events.first(where: { $0.name == "app.first_launch" })
        let d1 = firstLaunch.flatMap { first -> Bool in
            let day1 = cal.startOfDay(for: Date(timeIntervalSince1970: first.ts).addingTimeInterval(86400))
            return events.contains(where: {
                $0.name == "app.launch" && cal.isDate(Date(timeIntervalSince1970: $0.ts), inSameDayAs: day1)
            })
        } ?? false

        let byName = Dictionary(grouping: events, by: { $0.name }).mapValues { $0.count }

        return Summary(
            totalEvents: events.count,
            activeDays30d: activeDays.count,
            d1RetentionHit: d1,
            firstLaunchAt: firstLaunch.map { Date(timeIntervalSince1970: $0.ts) },
            eventCounts: byName
        )
    }

    struct Summary {
        let totalEvents: Int
        let activeDays30d: Int
        let d1RetentionHit: Bool
        let firstLaunchAt: Date?
        let eventCounts: [String: Int]
    }

    #if DEBUG
    /// Debug — affiche un résumé formaté dans la console Xcode.
    static func printSummary() {
        let s = summary()
        print("═══ Analytics LifeOS ═══")
        print("Events totaux         : \(s.totalEvents)")
        print("Jours actifs (30j)    : \(s.activeDays30d)")
        print("D1 retention          : \(s.d1RetentionHit ? "OUI" : "non")")
        print("1er launch            : \(s.firstLaunchAt.map { ISO8601DateFormatter().string(from: $0) } ?? "—")")
        print("─── Top events ───")
        for (name, count) in s.eventCounts.sorted(by: { $0.value > $1.value }).prefix(15) {
            print("  \(count.description.padding(toLength: 6, withPad: " ", startingAt: 0)) \(name)")
        }
        print("═══════════════════════")
    }
    #endif

    // MARK: - Storage

    private static var fileURL: URL? {
        try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("analytics.jsonl")
    }

    private static func append(_ event: Event) async {
        guard let url = fileURL else { return }
        do {
            let data = try JSONEncoder().encode(event)
            var line = data
            line.append(0x0A) // newline
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            } else {
                try? line.write(to: url, options: .atomic)
            }
        } catch {
            // Silencieux — jamais bloquer sur analytics.
        }
    }

    private static func readAll() -> [Event] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: 0x0A).compactMap {
            try? decoder.decode(Event.self, from: Data($0))
        }
    }
}
