import Foundation
import SwiftUI

struct PathView: View {
    var log: LogPath
    var settings: PathSettings
    @State private var run = PathRun()
    @State private var samples: [Sample] = []
    @State private var planned = PlannedPath()
    @State private var scores: [String: PathScore] = [:]
    @State private var importing = false
    @State private var editingPlanned = false
    @State private var pathFile: URL?

    var body: some View {
        VStack(spacing: 10) {
            PathPlotView(lines: shown, planned: planned.legs.isEmpty ? nil : planned.line(), showsGrid: Bindable(settings).showsGrid)
                .frame(maxHeight: .infinity)
            if shown.isEmpty {
                Text("Turn on a line in Lines, or import a log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(shown) { line in
                            PathLineCard(line: line, score: scores[line.id])
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    refreshScores()
                } label: {
                    Label("Compare", systemImage: "arrow.left.and.right")
                }
                .buttonStyle(.bordered)
                .disabled(log.isLogging || planned.legs.isEmpty || shown.isEmpty)
                Button { savePath() } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(log.isLogging || shown.isEmpty)
                if let pathFile {
                    ShareLink(item: pathFile) { Label("Path", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Path")
        .toolbar {
            Button { editingPlanned = true } label: { Image(systemName: "signpost.right") }
                .accessibilityLabel("Planned path")
            Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                .accessibilityLabel("Import")
                .disabled(log.isLogging)
        }
        .sheet(isPresented: $editingPlanned) {
            PlannedPathView(planned: $planned, lines: shown, facingDegrees: log.facingDegrees)
                .presentationDetents([.medium, .large])
                .onAppear { log.watchFacing() }
                .onDisappear {
                    log.stopFacing()
                    planned.save(beside: log.fileURL)
                    scores = [:]
                }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: LogFile.readableTypes) { result in
            guard case .success(let url) = result else { return }
            log.importLog(from: url)
            load(log.samples)
        }
        .onAppear(perform: reload)
        .onChange(of: log.samples.count) {
            if log.isLogging { reloadLive() }
            else if !log.samples.isEmpty { load(log.samples) }
        }
        .onChange(of: settings.visible) {
            run.show(settings.visible)
            scores = [:]
        }
        .onChange(of: log.isLogging) { _, logging in
            if logging { scores = [:] }
            else { run.show(settings.visible) }
        }
        .onChange(of: log.fileURL) { loadPlanned() }
    }

    private var shown: [PathLine] { run.lines }

    private func reload() {
        if log.isLogging {
            samples = log.samples
            run.reset()
            run.follow(samples, visible: settings.visible)
        } else if samples.isEmpty {
            if log.samples.isEmpty, let url = log.fileURL ?? LogFile.newest() {
                if log.fileURL == nil { log.fileURL = url }
                log.samples = LogFile.load(url)
            }
            if !log.samples.isEmpty { load(log.samples) }
        }
        if let csv = log.fileURL {
            let saved = SavedPath.url(beside: csv)
            pathFile = FileManager.default.fileExists(atPath: saved.path) ? saved : pathFile
        }
        loadPlanned()
    }

    private func reloadLive() {
        guard log.isLogging else { return }
        samples = log.samples
        run.follow(samples, visible: settings.visible)
    }

    private func load(_ loaded: [Sample]) {
        samples = loaded
        run.reset()
        run.follow(samples, visible: settings.visible)
    }

    private func loadPlanned() {
        guard let url = log.fileURL else { planned = PlannedPath(); scores = [:]; return }
        planned = PlannedPath.load(beside: url) ?? PlannedPath()
        scores = [:]
    }

    private func savePath() {
        guard let csv = log.fileURL ?? LogFile.newest(), !shown.isEmpty else { return }
        if log.fileURL == nil { log.fileURL = csv }
        pathFile = SavedPath.write(shown, beside: csv)
    }

    private func refreshScores() {
        guard !log.isLogging, !planned.legs.isEmpty else { scores = [:]; return }
        let reference = planned.line()
        var next: [String: PathScore] = [:]
        for line in shown { next[line.id] = PathScore.measure(line, planned: reference) }
        scores = next
    }
}

private struct PathLineCard: View {
    var line: PathLine
    var score: PathScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(line.name).font(.caption.weight(.semibold)).lineLimit(1)
            Text(String(format: "%.1f m", line.finalDisplacement)).font(.title3.monospacedDigit())
            Text(PathTalk.say(line)).font(.caption).fixedSize(horizontal: false, vertical: true)
            if let score {
                Text(String(format: "End %.1f m", score.endError)).font(.subheadline)
                Text(String(format: "Miss %.1f m", score.meanMiss)).font(.subheadline)
                if abs(score.fittedYawDegrees) >= 1 {
                    Text(String(format: "Turn %.0f°", score.fittedYawDegrees))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !line.detail.isEmpty {
                Text(line.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .frame(width: 280, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}
