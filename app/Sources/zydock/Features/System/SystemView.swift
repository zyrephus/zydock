import SwiftUI

struct SystemView: View {
    @ObservedObject var metrics: MetricsPoller
    @State private var cpuExpanded = false
    @State private var ramExpanded = false

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width - Layout.horizontalPadding * 2 - 1
            let m = metrics.metrics
            let ramFraction = m.map { $0.memTotalGB > 0 ? $0.memUsedGB / $0.memTotalGB : 0 } ?? 0
            let ramText = m.map { String(format: "%.1f/%.0fG", $0.memUsedGB, $0.memTotalGB) } ?? "–"

            HStack(spacing: 0) {
                column(
                    label: "CPU",
                    valueText: m.map { String(format: "%.0f%%", $0.cpuUsage) } ?? "–",
                    fraction: m.map { $0.cpuUsage / 100.0 } ?? 0,
                    isExpanded: $cpuExpanded,
                    procs: Array((m?.topCPU ?? []).prefix(5)),
                    procValue: { $0.cpuPct }
                )
                .frame(width: available / 2)

                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 1)
                    .padding(.vertical, 6)

                column(
                    label: "RAM",
                    valueText: ramText,
                    fraction: ramFraction,
                    isExpanded: $ramExpanded,
                    procs: Array((m?.topMem ?? []).prefix(5)),
                    procValue: { $0.memPct }
                )
                .frame(width: available / 2)
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func column(
        label: String,
        valueText: String,
        fraction: Double,
        isExpanded: Binding<Bool>,
        procs: [ProcessInfo],
        procValue: @escaping (ProcessInfo) -> Double
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                metricRow(
                    label: label,
                    valueText: valueText,
                    fraction: fraction,
                    isExpanded: isExpanded
                )
                if isExpanded.wrappedValue {
                    processRows(procs: procs, value: procValue)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func metricRow(
        label: String,
        valueText: String,
        fraction: Double,
        isExpanded: Binding<Bool>
    ) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: Typography.primary, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(valueText)
                        .font(.system(size: Typography.primary, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 16, height: 16)
                }
                MetricBar(value: fraction)
                    .frame(height: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(NotchPressStyle())
    }

    private func processRows(procs: [ProcessInfo], value: @escaping (ProcessInfo) -> Double) -> some View {
        VStack(spacing: 2) {
            ForEach(procs) { proc in
                HStack {
                    Text(proc.name)
                        .font(.system(size: Typography.secondary))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(String(format: "%.1f%%", value(proc)))
                        .font(.system(size: Typography.secondary, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .padding(.leading, 6)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

struct MetricBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.65))
                    .frame(width: geo.size.width * min(1, max(0, value)))
            }
        }
    }
}
