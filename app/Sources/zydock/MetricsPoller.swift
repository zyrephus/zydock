import Foundation

struct SystemMetrics: Codable {
    let cpuUsage: Double
    let memUsedGB: Double
    let memTotalGB: Double
    let batteryPct: Int
    let charging: Bool
    let collectedAt: Int64

    enum CodingKeys: String, CodingKey {
        case cpuUsage = "cpu_usage"
        case memUsedGB = "mem_used_gb"
        case memTotalGB = "mem_total_gb"
        case batteryPct = "battery_pct"
        case charging
        case collectedAt = "collected_at"
    }
}

class MetricsPoller: ObservableObject {
    @Published var metrics: SystemMetrics?

    private let url = URL(string: "http://localhost:6767/metrics")!
    private var timer: Timer?

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let data = data, error == nil,
                  let m = try? JSONDecoder().decode(SystemMetrics.self, from: data) else {
                return
            }
            DispatchQueue.main.async {
                self?.metrics = m
            }
        }.resume()
    }
}
