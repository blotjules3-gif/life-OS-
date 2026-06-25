import ActivityKit
import CoreLocation
import Foundation
import WeatherKit

@available(iOS 16.1, *)
@MainActor
final class AlarmLiveActivityManager {
    static let shared = AlarmLiveActivityManager()

    private var activity: Activity<AlarmAttributes>?
    private var cachedTemperature: Double?
    private var cachedWeatherSymbol: String?

    private init() {}

    /// Démarre le widget Lock Screen dès que l'alarme est programmée.
    /// Récupère la météo en amont pour l'afficher dans la vue "Programmé".
    func startScheduled(alarmTimeString: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        end()

        (cachedTemperature, cachedWeatherSymbol) = await fetchWeather()

        let attrs = AlarmAttributes(startTime: .now)
        let state = AlarmAttributes.ContentState(
            phase: .scheduled,
            timeString: alarmTimeString,
            message: "Écoute ce que tu as de prévu et déverouille pour suivre le reste.",
            temperature: cachedTemperature,
            weatherSymbol: cachedWeatherSymbol
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(8 * 3600))
        activity = try? Activity.request(attributes: attrs, content: content)
    }

    func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        guard activity == nil else {
            update(phase: .ringing, message: "Réveil en cours…")
            return
        }
        let attrs = AlarmAttributes(startTime: .now)
        let state = AlarmAttributes.ContentState(
            phase: .ringing,
            timeString: currentTimeString(),
            message: "Réveil en cours…",
            temperature: cachedTemperature,
            weatherSymbol: cachedWeatherSymbol
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(120))
        activity = try? Activity.request(attributes: attrs, content: content)
    }

    func update(phase: AlarmAttributes.ContentState.Phase, message: String = "") {
        guard let activity else { return }
        let state = AlarmAttributes.ContentState(
            phase: phase,
            timeString: currentTimeString(),
            message: message,
            temperature: cachedTemperature,
            weatherSymbol: cachedWeatherSymbol
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(60))
        Task { await activity.update(content) }
    }

    func end() {
        guard let act = activity else { return }
        activity = nil
        let state = AlarmAttributes.ContentState(
            phase: .dismissed,
            timeString: currentTimeString(),
            message: "Bonne journée !"
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await act.end(content, dismissalPolicy: .after(.now.addingTimeInterval(30 * 60))) }
    }

    // MARK: - Météo

    private func fetchWeather() async -> (Double?, String?) {
        guard let location = CLLocationManager().location else { return (nil, nil) }
        do {
            let weather = try await WeatherService.shared.weather(for: location)
            let temp = weather.currentWeather.temperature.converted(to: .celsius).value
            let symbol = weather.currentWeather.symbolName
            return (temp, symbol)
        } catch {
            return (nil, nil)
        }
    }

    // MARK: - Helpers

    private func currentTimeString() -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: .now)
    }
}
