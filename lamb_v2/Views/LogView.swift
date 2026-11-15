import SwiftUI

struct LogView: View {
    @State private var log = LogPath()
    @State private var settings = PathSettings()
    @State private var run = PathRun()
    @State private var showSettings = false
    @State private var importing = false
    @State private var pathFile: URL?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PathPlotView(lines: run.lines, showsGrid: Bindable(settings).showsGrid)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .frame(maxHeight: .infinity)
                VStack(spacing: 10) {
                    HStack {
                        Text(log.status).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(summary).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    if let talk = spoken {
                        Text(talk)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 10) {
                        Button { importing = true } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(log.isLogging)
                        Button {
                            log.toggle()
                            if log.isLogging { run.reset() } else { run.show(settings.visible) }
                        } label: {
                            Label(log.isLogging ? "Stop" : "Log", systemImage: log.isLogging ? "stop.fill" : "book.pages")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(log.isLogging ? .red : .accentColor)
                        if let url = log.fileURL {
                            ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.bordered)
                        }
                    }
                    HStack(spacing: 10) {
                        Button { findPath() } label: {
                            Label("Find", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        }
                        .buttonStyle(.bordered)
                        .disabled(log.isLogging)
                        Button { savePath() } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.bordered)
                        .disabled(log.isLogging || run.lines.isEmpty)
                        if let pathFile {
                            ShareLink(item: pathFile) { Label("Path", systemImage: "square.and.arrow.up") }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(20)
                .background(.bar)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Log")
            .navigationSubtitle(log.fileURL?.deletingPathExtension().lastPathComponent ?? "No file")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { ChartsView(log: log) } label: { Image(systemName: "chart.xyaxis.line") }
                        .accessibilityLabel("Charts")
                    NavigationLink { PathView(log: log, settings: settings) } label: { Image(systemName: "map") }
                        .accessibilityLabel("Path")
                    Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                        .accessibilityLabel("Lines")
                }
            }
            .sheet(isPresented: $showSettings) {
                PathSettingsView(settings: settings)
                    .presentationDetents([.medium, .large])
                    .onDisappear { run.show(settings.visible) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: LogFile.readableTypes) { result in
                guard case .success(let url) = result else { return }
                log.importLog(from: url)
                run.reset()
                run.follow(log.samples, visible: settings.visible)
                if let csv = log.fileURL {
                    let saved = SavedPath.url(beside: csv)
                    pathFile = FileManager.default.fileExists(atPath: saved.path) ? saved : nil
                }
            }
            .onAppear {
                guard !log.isLogging, log.samples.isEmpty else { return }
                findPath()
            }
            .onChange(of: log.samples.count) {
                guard log.isLogging else { return }
                run.follow(log.samples, visible: settings.visible)
            }
        }
    }

    private func findPath() {
        guard !log.isLogging else { return }
        guard let url = log.fileURL ?? LogFile.newest() else { return }
        let loaded = LogFile.load(url)
        guard !loaded.isEmpty else { return }
        log.fileURL = url
        log.samples = loaded
        log.status = url.deletingPathExtension().lastPathComponent
        run.reset()
        run.follow(loaded, visible: settings.visible)
        let saved = SavedPath.url(beside: url)
        pathFile = FileManager.default.fileExists(atPath: saved.path) ? saved : nil
    }

    private func savePath() {
        guard let csv = log.fileURL, !run.lines.isEmpty else { return }
        pathFile = SavedPath.write(run.lines, beside: csv)
    }

    private var summary: String {
        guard let last = log.samples.last else { return "0 samples" }
        return String(format: "%.0f s · %d samples", last.elapsed, log.samples.count)
    }

    private var spoken: String? {
        let line = run.lines.first { $0.id == "k2" } ?? run.lines.first
        guard let line, line.points.count > 1 else { return nil }
        return PathTalk.say(line)
    }
}
