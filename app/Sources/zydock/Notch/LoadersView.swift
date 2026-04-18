import SwiftUI

// MARK: - Core renderer

struct PixelLoader: View {
    let pattern: LoaderPattern
    var grid: Int = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: pattern.period)) / pattern.period

            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let step = side / CGFloat(grid)
                let px = step
                ZStack {
                    ForEach(0..<pattern.cells.count, id: \.self) { i in
                        let cell = pattern.cells[i]
                        let b = pulse(phase: phase, offset: cell.phase, sharpness: pattern.sharpness)
                        pixelView(size: px, brightness: b)
                            .position(
                                x: step * (CGFloat(cell.col) + 0.5),
                                y: step * (CGFloat(cell.row) + 0.5)
                            )
                    }
                }
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func pixelView(size: CGFloat, brightness: Double) -> some View {
        ZStack {
            Rectangle()
                .fill(pattern.tint)
                .frame(width: size * 1.8, height: size * 1.8)
                .blur(radius: size * 0.6)
                .opacity(brightness * 0.3)
            Rectangle()
                .fill(pattern.tint)
                .frame(width: size, height: size)
                .opacity(brightness)
        }
        .compositingGroup()
    }

    /// phase, offset both 0..1. Returns 0..1 with a peak when they align.
    private func pulse(phase: Double, offset: Double, sharpness: Double) -> Double {
        var x = (phase - offset).truncatingRemainder(dividingBy: 1)
        if x < 0 { x += 1 }
        // cosine bump peaking at x=0, zero at x=0.5
        let c = cos(x * 2 * .pi) * 0.5 + 0.5
        return pow(c, sharpness)
    }
}

// MARK: - Pattern model

struct LoaderCell {
    let row: Int
    let col: Int
    let phase: Double
}

struct LoaderPattern {
    var cells: [LoaderCell]
    var tint: Color
    var period: Double = 1.4
    var sharpness: Double = 2.2
}

// MARK: - Tint palette

private let tintBlue = Color(red: 0.58, green: 0.76, blue: 1.0)
private let tintAmber = Color(red: 1.0, green: 0.76, blue: 0.52)
private let tintPink = Color(red: 1.0, green: 0.58, blue: 0.66)

// MARK: - Pattern helpers

private func sync(_ positions: [(Int, Int)]) -> [LoaderCell] {
    positions.map { LoaderCell(row: $0.0, col: $0.1, phase: 0) }
}

private func sweep(_ positions: [(Int, Int)]) -> [LoaderCell] {
    let n = Double(positions.count)
    return positions.enumerated().map { i, p in
        LoaderCell(row: p.0, col: p.1, phase: Double(i) / n)
    }
}

private func stagger(_ positions: [(Int, Int)], offsets: [Double]) -> [LoaderCell] {
    zip(positions, offsets).map { LoaderCell(row: $0.0.0, col: $0.0.1, phase: $0.1) }
}

// MARK: - All loaders

enum LoaderKind: String, CaseIterable, Identifiable {
    case soloCenter = "solo-center"
    case soloTL = "solo-tl"
    case soloBR = "solo-br"
    case lineHTop = "line-h-top"
    case lineHMid = "line-h-mid"
    case lineHBot = "line-h-bot"
    case lineVLeft = "line-v-left"
    case lineVMid = "line-v-mid"
    case lineVRight = "line-v-right"
    case lineDiag1 = "line-diag-1"
    case lineDiag2 = "line-diag-2"
    case cornersOnly = "corners-only"
    case cornersSync = "corners-sync"
    case plusHollow = "plus-hollow"
    case lTL = "L-tl"
    case lTR = "L-tr"
    case lBL = "L-bl"
    case lBR = "L-br"
    case tTop = "T-top"
    case tBot = "T-bot"
    case tLeft = "T-left"
    case tRight = "T-right"
    case duoH = "duo-h"
    case duoV = "duo-v"
    case duoDiag = "duo-diag"
    case frame = "frame"
    case frameSync = "frame-sync"
    case sparse1 = "sparse-1"
    case sparse2 = "sparse-2"
    case sparse3 = "sparse-3"
    case waveTLBR = "wave-tl-br"
    case idleGreen = "idle"
    case frameAmber = "frame-amber"

    var id: String { rawValue }

    var pattern: LoaderPattern {
        switch self {
        case .soloCenter:
            return .init(cells: sync([(1, 1)]), tint: tintBlue)
        case .soloTL:
            return .init(cells: sync([(0, 0)]), tint: tintBlue)
        case .soloBR:
            return .init(cells: sync([(2, 2)]), tint: tintAmber)

        case .lineHTop:
            return .init(cells: sweep([(0, 0), (0, 1), (0, 2)]), tint: tintBlue)
        case .lineHMid:
            return .init(cells: sweep([(1, 0), (1, 1), (1, 2)]), tint: tintBlue)
        case .lineHBot:
            return .init(cells: sweep([(2, 0), (2, 1), (2, 2)]), tint: tintAmber)

        case .lineVLeft:
            return .init(cells: sweep([(0, 0), (1, 0), (2, 0)]), tint: tintPink)
        case .lineVMid:
            return .init(cells: sweep([(0, 1), (1, 1), (2, 1)]), tint: tintBlue)
        case .lineVRight:
            return .init(cells: sweep([(0, 2), (1, 2), (2, 2)]), tint: tintBlue)

        case .lineDiag1:
            return .init(cells: sweep([(0, 0), (1, 1), (2, 2)]), tint: tintAmber)
        case .lineDiag2:
            return .init(cells: sweep([(0, 2), (1, 1), (2, 0)]), tint: tintPink)

        case .cornersOnly:
            return .init(
                cells: stagger(
                    [(0, 0), (0, 2), (2, 2), (2, 0)],
                    offsets: [0, 0.25, 0.5, 0.75]
                ),
                tint: tintBlue
            )
        case .cornersSync:
            return .init(cells: sync([(0, 0), (0, 2), (2, 0), (2, 2)]), tint: tintBlue)

        case .plusHollow:
            return .init(cells: sync([(0, 1), (1, 0), (1, 2), (2, 1)]), tint: tintAmber)

        case .lTL:
            return .init(cells: sync([(0, 0), (0, 1), (1, 0)]), tint: tintPink)
        case .lTR:
            return .init(cells: sync([(0, 1), (0, 2), (1, 2)]), tint: tintBlue)
        case .lBL:
            return .init(cells: sync([(1, 0), (2, 0), (2, 1)]), tint: tintBlue)
        case .lBR:
            return .init(cells: sync([(1, 2), (2, 1), (2, 2)]), tint: tintAmber)

        case .tTop:
            return .init(cells: sync([(0, 0), (0, 1), (0, 2), (1, 1)]), tint: tintPink)
        case .tBot:
            return .init(cells: sync([(1, 1), (2, 0), (2, 1), (2, 2)]), tint: tintBlue)
        case .tLeft:
            return .init(cells: sync([(0, 0), (1, 0), (2, 0), (1, 1)]), tint: tintBlue)
        case .tRight:
            return .init(cells: sync([(0, 2), (1, 2), (2, 2), (1, 1)]), tint: tintAmber)

        case .duoH:
            return .init(cells: stagger([(1, 0), (1, 2)], offsets: [0, 0.5]), tint: tintPink)
        case .duoV:
            return .init(cells: stagger([(0, 1), (2, 1)], offsets: [0, 0.5]), tint: tintBlue)
        case .duoDiag:
            return .init(cells: stagger([(0, 0), (2, 2)], offsets: [0, 0.5]), tint: tintBlue)

        case .frame:
            let border: [(Int, Int)] = [
                (0, 0), (0, 1), (0, 2),
                (1, 2),
                (2, 2), (2, 1), (2, 0),
                (1, 0),
            ]
            var cells = sweep(border)
            cells.append(LoaderCell(row: 1, col: 1, phase: 0.5))
            return .init(
                cells: cells,
                tint: Color(red: 0xC1/255, green: 0x5F/255, blue: 0x3C/255),
                period: 2.0,
                sharpness: 3.0
            )
        case .frameSync:
            let border: [(Int, Int)] = [
                (0, 0), (0, 1), (0, 2),
                (1, 2),
                (2, 2), (2, 1), (2, 0),
                (1, 0),
            ]
            return .init(cells: sync(border), tint: tintPink, period: 1.6)

        case .sparse1:
            return .init(
                cells: stagger([(0, 2), (1, 0), (2, 1)], offsets: [0, 0.35, 0.7]),
                tint: tintBlue
            )
        case .sparse2:
            return .init(
                cells: stagger([(0, 0), (1, 2), (2, 0)], offsets: [0, 0.33, 0.66]),
                tint: tintBlue
            )
        case .sparse3:
            return .init(
                cells: sweep([(0, 2), (1, 1), (2, 0)]),
                tint: tintAmber,
                period: 1.4
            )

        case .waveTLBR:
            // Anti-diagonal bands sweep from (0,0) to (2,2).
            let bands: [[(Int, Int)]] = [
                [(0, 0)],
                [(0, 1), (1, 0)],
                [(0, 2), (1, 1), (2, 0)],
                [(1, 2), (2, 1)],
                [(2, 2)],
            ]
            var cells: [LoaderCell] = []
            for (i, band) in bands.enumerated() {
                let phase = Double(i) / Double(bands.count)
                for p in band {
                    cells.append(LoaderCell(row: p.0, col: p.1, phase: phase))
                }
            }
            return .init(cells: cells, tint: tintBlue, period: 1.6, sharpness: 3.0)

        case .idleGreen:
            // Breathing 3x3 — center leads, cross follows, corners trail, so the
            // block shimmers outward rather than pulsing in lockstep.
            let phases: [[Double]] = [
                [0.30, 0.15, 0.30],
                [0.15, 0.00, 0.15],
                [0.30, 0.15, 0.30],
            ]
            var cells: [LoaderCell] = []
            for r in 0..<3 {
                for c in 0..<3 {
                    cells.append(LoaderCell(row: r, col: c, phase: phases[r][c]))
                }
            }
            return .init(
                cells: cells,
                tint: Color(red: 0.52, green: 0.82, blue: 0.58),
                period: 1.8,
                sharpness: 1.4
            )

        case .frameAmber:
            let border: [(Int, Int)] = [
                (0, 0), (0, 1), (0, 2),
                (1, 2),
                (2, 2), (2, 1), (2, 0),
                (1, 0),
            ]
            var cells = sweep(border)
            cells.append(LoaderCell(row: 1, col: 1, phase: 0.5))
            return .init(cells: cells, tint: tintAmber, period: 2.0, sharpness: 3.0)
        }
    }
}
