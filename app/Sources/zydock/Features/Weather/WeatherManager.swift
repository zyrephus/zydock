import Foundation
import CoreLocation
import AppKit
import Combine
import SwiftUI

enum TemperatureUnit: String, CaseIterable, Identifiable {
    case fahrenheit = "F"
    case celsius = "C"
    var id: String { rawValue }
    var label: String { self == .fahrenheit ? "°F" : "°C" }
}

struct WeatherBadge: View {
    @ObservedObject var weather: WeatherManager
    @AppStorage("weatherUnit") private var unitRaw: String = TemperatureUnit.fahrenheit.rawValue

    private var unit: TemperatureUnit {
        TemperatureUnit(rawValue: unitRaw) ?? .fahrenheit
    }

    private func display(_ celsius: Double) -> Int {
        switch unit {
        case .celsius: return Int(celsius.rounded())
        case .fahrenheit: return Int((celsius * 9.0 / 5.0 + 32.0).rounded())
        }
    }

    var body: some View {
        switch weather.authorization {
        case .authorized:
            if let snap = weather.snapshot {
                Button(action: { weather.refresh() }) {
                    HStack(spacing: 5) {
                        Image(systemName: snap.symbolName)
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 14))
                        Text("\(display(snap.temperatureC))°")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(NotchPressStyle())
                .help(snap.description)
                .transition(.opacity)
            }
        case .notDetermined:
            Button(action: { weather.requestAccess() }) {
                Image(systemName: "location.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(NotchPressStyle())
            .help("Enable location for weather")
        case .denied:
            EmptyView()
        }
    }
}

@MainActor
final class WeatherManager: NSObject, ObservableObject {
    enum Authorization {
        case notDetermined
        case denied
        case authorized
    }

    struct Snapshot {
        var symbolName: String
        var temperatureC: Double
        var description: String
    }

    @Published private(set) var authorization: Authorization = .notDetermined
    @Published private(set) var snapshot: Snapshot?
    @Published private(set) var isLoading = false

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?
    private var didStart = false
    private var lastCoordinate: CLLocationCoordinate2D?
    private var inFlight: Task<Void, Never>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        updateAuthorization()
    }

    deinit {
        refreshTimer?.invalidate()
    }

    // MARK: - Lifecycle

    func start() {
        guard !didStart else { return }
        didStart = true

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        switch authorization {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized:
            requestLocation()
        case .denied:
            break
        }
    }

    func requestAccess() {
        if authorization == .denied {
            openSystemSettings()
        } else {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        guard authorization == .authorized else { return }
        requestLocation()
    }

    private func requestLocation() {
        locationManager.requestLocation()
    }

    // MARK: - Authorization

    private func updateAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            authorization = .notDetermined
        case .restricted, .denied:
            authorization = .denied
        case .authorized, .authorizedAlways, .authorizedWhenInUse:
            authorization = .authorized
        @unknown default:
            authorization = .notDetermined
        }
    }

    // MARK: - Fetch

    private func fetch(for coordinate: CLLocationCoordinate2D) {
        inFlight?.cancel()
        isLoading = true
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        inFlight = Task { [weak self] in
            defer { Task { @MainActor in self?.isLoading = false } }
            guard let url = URL(string:
                "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,is_day&timezone=auto"
            ) else { return }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
                let isDay = decoded.current.is_day == 1
                let symbol = Self.symbolName(for: decoded.current.weather_code, isDay: isDay)
                let desc = Self.description(for: decoded.current.weather_code)
                let snap = Snapshot(
                    symbolName: symbol,
                    temperatureC: decoded.current.temperature_2m,
                    description: desc
                )
                await MainActor.run { self?.snapshot = snap }
            } catch {
                // Keep previous snapshot on transient errors.
            }
        }
    }

    // MARK: - WMO mapping

    private static func symbolName(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57: return "cloud.sleet.fill"
        case 61, 63: return "cloud.rain.fill"
        case 65: return "cloud.heavyrain.fill"
        case 66, 67: return "cloud.sleet.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81: return "cloud.rain.fill"
        case 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.rain.fill"
        case 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    private static func description(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81: return "Rain showers"
        case 82: return "Heavy showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm w/ hail"
        default: return "Unknown"
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension WeatherManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            updateAuthorization()
            if authorization == .authorized { requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coord = locations.last?.coordinate else { return }
        Task { @MainActor in
            lastCoordinate = coord
            fetch(for: coord)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // If we have a cached coordinate, just retry the fetch silently.
        Task { @MainActor in
            if let coord = lastCoordinate { fetch(for: coord) }
        }
    }
}

// MARK: - Open-Meteo decoding

private struct OpenMeteoResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
    let current: Current
}
