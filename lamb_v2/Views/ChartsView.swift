import Charts
import SwiftUI

struct ChartsView: View {
    var log: LogPath
    @State private var samples: [Sample] = []
    @State private var importing = false

    var body: some View {
        Group {
            if samples.isEmpty {
                ContentUnavailableView("No log", systemImage: "chart.xyaxis.line", description: Text("Log a walk or import a CSV."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        chart("Acceleration", "East", "North", "Up", samples.filter(\.isPath)) { sample in
                            (sample.eastAcceleration, sample.northAcceleration, sample.upAcceleration)
                        }
                        chart("Rotation", "X", "Y", "Z", samples.filter(\.isPath)) { sample in
                            (sample.deviceRotation.x, sample.deviceRotation.y, sample.deviceRotation.z)
                        }
                        chart("Yaw", "Heading", "Rate", nil, samples.filter(\.isPath)) { sample in
                            (sample.heading, sample.yawRate, 0)
                        }
                        chart("Pedometer", "Distance", nil, nil, samples.filter(\.isPath)) { sample in
                            (sample.pedometerDistance, 0, 0)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Charts")
        .toolbar {
            Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                .accessibilityLabel("Import")
                .disabled(log.isLogging)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: LogFile.readableTypes) { result in
            guard case .success(let url) = result else { return }
            log.importLog(from: url)
            samples = log.samples
        }
        .onAppear {
            if log.isLogging || !log.samples.isEmpty { samples = log.samples }
            else if samples.isEmpty, let url = log.fileURL ?? LogFile.newest() { samples = LogFile.load(url) }
        }
        .onChange(of: log.samples.count) {
            if log.isLogging || !log.samples.isEmpty { samples = log.samples }
        }
    }

    private func chart(_ title: String, _ a: String, _ b: String?, _ c: String?, _ rows: [Sample], _ value: @escaping (Sample) -> (Double, Double, Double)) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Chart {
                ForEach(Array(rows.enumerated()), id: \.offset) { item in
                    let parts = value(item.element)
                    LineMark(x: .value("Time", item.element.elapsed), y: .value(a, parts.0))
                        .foregroundStyle(by: .value("Series", a))
                    if let b {
                        LineMark(x: .value("Time", item.element.elapsed), y: .value(b, parts.1))
                            .foregroundStyle(by: .value("Series", b))
                    }
                    if let c {
                        LineMark(x: .value("Time", item.element.elapsed), y: .value(c, parts.2))
                            .foregroundStyle(by: .value("Series", c))
                    }
                }
            }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 200)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
