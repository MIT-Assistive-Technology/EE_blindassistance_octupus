import Darwin
import Foundation
import SwiftUI

struct PathPlotView: View {
    var lines: [PathLine]
    var planned: PathLine? = nil
    @Binding var showsGrid: Bool
    @State private var zoom = 1.0
    @State private var pinch = 1.0
    @State private var pan = CGSize.zero
    @State private var drag = CGSize.zero

    private var displayZoom: Double { min(32, max(1, zoom * pinch)) }
    private var displayPan: CGSize {
        CGSize(width: pan.width + drag.width, height: pan.height + drag.height)
    }

    var body: some View {
        VStack(spacing: 10) {
            Canvas { context, size in
                draw(context, in: size, zoom: displayZoom, pan: displayPan)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.separator).opacity(0.5), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .gesture(
                MagnifyGesture()
                    .onChanged { pinch = $0.magnification }
                    .onEnded { value in
                        zoom = min(32, max(1, zoom * value.magnification))
                        pinch = 1
                        if zoom <= 1.01 { zoom = 1; pan = .zero; drag = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard zoom * pinch > 1.01 else { return }
                        drag = value.translation
                    }
                    .onEnded { value in
                        guard zoom > 1.01 else { drag = .zero; return }
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                        drag = .zero
                    }
            )
            .onTapGesture(count: 2) {
                zoom = 1
                pinch = 1
                pan = .zero
                drag = .zero
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(lines) { line in
                        HStack(spacing: 10) {
                            Circle().fill(swatch(line.id)).frame(width: 10, height: 10)
                            Text(line.name).font(.caption2).lineLimit(1)
                        }
                    }
                    if planned != nil {
                        HStack(spacing: 10) {
                            Capsule().fill(.primary).frame(width: 20, height: 10)
                            Text("Planned path").font(.caption2)
                        }
                    }
                }
            }
            Toggle("Grid", isOn: $showsGrid)
                .font(.footnote)
        }
    }

    private func swatch(_ id: String) -> Color {
        let rgb = Stats.color(for: id)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private func draw(_ context: GraphicsContext, in size: CGSize, zoom: Double, pan: CGSize) {
        var minEast = 0.0, maxEast = 0.0, minNorth = 0.0, maxNorth = 0.0
        var any = true
        func include(_ point: PathPoint) {
            minEast = any ? min(minEast, point.east) : point.east
            maxEast = any ? max(maxEast, point.east) : point.east
            minNorth = any ? min(minNorth, point.north) : point.north
            maxNorth = any ? max(maxNorth, point.north) : point.north
            any = true
        }
        for line in lines {
            for point in line.points { include(point) }
        }
        for point in planned?.points ?? [] { include(point) }
        let plot = CGRect(x: 20, y: 20, width: max(1, size.width - 40), height: max(1, size.height - 60))
        let spanEast = max(maxEast - minEast, 1)
        let spanNorth = max(maxNorth - minNorth, 1)
        let fit = min(plot.width / spanEast, plot.height / spanNorth)
        let scale = fit * zoom
        let midEast = (minEast + maxEast) / 2
        let midNorth = (minNorth + maxNorth) / 2
        let shiftX = Double(pan.width)
        let shiftY = Double(pan.height)
        func place(east: Double, north: Double) -> CGPoint {
            CGPoint(x: plot.midX + (east - midEast) * scale + shiftX, y: plot.midY - (north - midNorth) * scale + shiftY)
        }
        func east(at x: CGFloat) -> Double { midEast + (Double(x) - plot.midX - shiftX) / scale }
        func north(at y: CGFloat) -> Double { midNorth - (Double(y) - plot.midY - shiftY) / scale }
        let step = nice(40 / max(scale, 1e-6))
        if showsGrid {
            let lowEast = east(at: plot.minX)
            let highEast = east(at: plot.maxX)
            let highNorth = north(at: plot.minY)
            let lowNorth = north(at: plot.maxY)
            var gridEast = (lowEast / step).rounded(.down) * step
            var count = 0
            while gridEast <= highEast + step, count < 80 {
                var path = Path()
                path.move(to: place(east: gridEast, north: lowNorth - step))
                path.addLine(to: place(east: gridEast, north: highNorth + step))
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                gridEast += step
                count += 1
            }
            var gridNorth = (lowNorth / step).rounded(.down) * step
            count = 0
            while gridNorth <= highNorth + step, count < 80 {
                var path = Path()
                path.move(to: place(east: lowEast - step, north: gridNorth))
                path.addLine(to: place(east: highEast + step, north: gridNorth))
                context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                gridNorth += step
                count += 1
            }
        }
        context.draw(Text("N").font(.caption.bold()), at: CGPoint(x: plot.midX, y: 10))
        for line in lines {
            let kept = thinned(line.points)
            guard kept.count >= 2 else { continue }
            var path = Path()
            path.addLines(kept.map { place(east: $0.east, north: $0.north) })
            let rgb = Stats.color(for: line.id)
            context.stroke(path, with: .color(Color(red: rgb.0, green: rgb.1, blue: rgb.2)), lineWidth: 2)
        }
        if let planned, planned.points.count >= 2 {
            var path = Path()
            path.addLines(planned.points.map { place(east: $0.east, north: $0.north) })
            context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [10, 10]))
        }
        let barWidth = step * scale
        let origin = CGPoint(x: 20, y: size.height - 20)
        var bar = Path()
        bar.move(to: origin)
        bar.addLine(to: CGPoint(x: origin.x + barWidth, y: origin.y))
        context.stroke(bar, with: .color(.primary), lineWidth: 2)
        let label = step >= 1 ? String(format: "%.0f m", step) : String(format: "%.1f m", step)
        context.draw(Text(label).font(.caption), at: CGPoint(x: origin.x + barWidth + 30, y: origin.y))
    }

    private func thinned(_ points: [PathPoint]) -> [PathPoint] {
        guard var last = points.first else { return [] }
        var kept = [last]
        for point in points.dropFirst() {
            if point.time - last.time >= Stats.Path.pointSpacing || point.id == points.last?.id {
                kept.append(point)
                last = point
            }
        }
        return kept
    }

    private func nice(_ raw: Double) -> Double {
        let value = max(raw, 0.1)
        let power = pow(10, floor(log10(value)))
        let unit = value / power
        let picked = unit <= 1 ? 1.0 : unit <= 2 ? 2.0 : unit <= 5 ? 5.0 : 10.0
        return picked * power
    }
}
