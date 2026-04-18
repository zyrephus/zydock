import Foundation

struct ProcessInfo: Codable, Identifiable {
    let pid: Int
    let name: String
    let cpuPct: Double
    let memPct: Double

    var id: Int { pid }

    enum CodingKeys: String, CodingKey {
        case pid, name
        case cpuPct = "cpu_pct"
        case memPct = "mem_pct"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int.self, forKey: .pid)
        name = try container.decode(String.self, forKey: .name)
        cpuPct = try container.decodeIfPresent(Double.self, forKey: .cpuPct) ?? 0
        memPct = try container.decodeIfPresent(Double.self, forKey: .memPct) ?? 0
    }
}

struct SystemMetrics: Codable {
    let cpuUsage: Double
    let memUsedGB: Double
    let memTotalGB: Double
    let collectedAt: Int64
    let topCPU: [ProcessInfo]
    let topMem: [ProcessInfo]

    enum CodingKeys: String, CodingKey {
        case cpuUsage = "cpu_usage"
        case memUsedGB = "mem_used_gb"
        case memTotalGB = "mem_total_gb"
        case collectedAt = "collected_at"
        case topCPU = "top_cpu"
        case topMem = "top_mem"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cpuUsage = try container.decode(Double.self, forKey: .cpuUsage)
        memUsedGB = try container.decode(Double.self, forKey: .memUsedGB)
        memTotalGB = try container.decode(Double.self, forKey: .memTotalGB)
        collectedAt = try container.decode(Int64.self, forKey: .collectedAt)
        topCPU = try container.decodeIfPresent([ProcessInfo].self, forKey: .topCPU) ?? []
        topMem = try container.decodeIfPresent([ProcessInfo].self, forKey: .topMem) ?? []
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
