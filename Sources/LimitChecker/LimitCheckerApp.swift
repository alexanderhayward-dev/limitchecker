import Foundation
import SwiftUI

@main
struct LimitCheckerApp: App {
    @StateObject private var usageStore = UsageStore()
    @StateObject private var updateStore = UpdateStore()

    var body: some Scene {
        MenuBarExtra {
            LimitMenuView(store: usageStore, updateStore: updateStore)
        } label: {
            MenuBarLabel(store: usageStore, updateStore: updateStore)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        HStack(spacing: 3) {
            // The percentages identify the app on their own; the gauge only
            // holds the place while no service has reported a value yet.
            if let summary = store.menuBarSummary {
                Text(summary)
                    .monospacedDigit()
            } else {
                Image(systemName: "gauge.with.dots.needle.50percent")
            }
            if updateStore.availableRelease != nil {
                Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .accessibilityLabel("Update verfügbar")
            }
        }
        .accessibilityLabel("LimitChecker")
        .task {
            store.start()
            updateStore.start()
        }
    }
}

private struct LimitMenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LimitChecker")
                    .font(.headline)
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .help("Aktualisiere")
                } else {
                    Button(action: store.refresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Aktualisieren")
                }
                UpdateMenu(store: updateStore)
            }

            if updateStore.availableRelease != nil {
                UpdateBanner(store: updateStore)
                Divider()
            }

            serviceSection(title: "Claude Code", usage: store.claude, issue: store.claudeIssue)
            Divider()
            serviceSection(title: "Codex", usage: store.codex, issue: store.codexIssue)

            Divider()
            UsageHistoryView(points: store.historyPoints, now: store.displayTime)

            Divider()
            HStack {
                Text(store.lastUpdatedText)
                    .font(.caption)
                    .foregroundStyle(store.statusColor)
                Spacer()
                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(16)
        .frame(width: 430)
        .onAppear {
            store.start()
            updateStore.start()
        }
    }

    @ViewBuilder
    private func serviceSection(title: String, usage: ServiceUsage?, issue: String?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            if let usage, usage.ok {
                ForEach(usage.windows) { window in
                    LimitRow(window: window)
                }
                if let issue {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if store.isRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Aktualisiere …")
                        .foregroundStyle(.secondary)
                }
            } else if let issue {
                Label(issue, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(usage?.error ?? "Noch nicht abgerufen")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct LimitRow: View {
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(window.percentLeft)% frei")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
            }
            LimitProgressBar(percentLeft: window.percentLeft, tint: tint)
            if let resets = window.resets {
                Text("Reset: \(resets)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var tint: Color {
        switch window.percentLeft {
        case 0...20: .red
        case 21...50: .orange
        default: .green
        }
    }
}

private struct LimitProgressBar: View {
    let percentLeft: Int
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(max(Double(percentLeft) / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geometry.size.width * fraction))
            }
        }
        .frame(height: 16)
        .accessibilityLabel("\(percentLeft) Prozent frei")
    }
}

private struct UsageHistoryView: View {
    let points: [UsageHistoryPoint]
    let now: Date

    private var claudeValues: [(Date, Int)] {
        points.compactMap { point in
            point.claudeSessionPercentLeft.map { (point.timestamp, $0) }
        }
    }

    private var codexValues: [(Date, Int)] {
        points.compactMap { point in
            point.codexFiveHourPercentLeft.map { (point.timestamp, $0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Verlauf des Restkontingents")
                    .font(.subheadline.weight(.semibold))
                Text("12 Stunden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if claudeValues.isEmpty && codexValues.isEmpty {
                Text("Verlauf baut sich mit den nächsten Aktualisierungen auf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                if !claudeValues.isEmpty {
                    HistoryChart(
                        title: "Claude Code · Session",
                        values: claudeValues,
                        color: .orange,
                        now: now
                    )
                }
                if !codexValues.isEmpty {
                    HistoryChart(
                        title: "Codex · 5h-Limit",
                        values: codexValues,
                        color: .blue,
                        now: now
                    )
                }
            }
        }
    }
}

private struct HistoryChart: View {
    let title: String
    let values: [(Date, Int)]
    let color: Color
    let now: Date

    private let chartHeight: CGFloat = 112
    private var latestPercent: Int? { values.last?.1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                Spacer()
                if let latestPercent {
                    Text("\(latestPercent)% frei")
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
            }

            if values.count >= 2 {
                HStack(alignment: .top, spacing: 7) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("100%")
                        Spacer()
                        Text("50%")
                        Spacer()
                        Text("0%")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(height: chartHeight)

                    Canvas { context, size in
                        drawChart(in: context, size: size)
                    }
                    .frame(height: chartHeight)
                }

                HStack(spacing: 0) {
                    Text("vor 12 Std.")
                    Spacer()
                    Text("vor 6 Std.")
                    Spacer()
                    Text("jetzt")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 39)
            } else {
                Text("Noch ein Messwert, dann wird der Verlauf gezeigt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: chartHeight, alignment: .center)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), Verlauf des Restkontingents")
    }

    private func drawChart(in context: GraphicsContext, size: CGSize) {
        let start = now.addingTimeInterval(-12 * 60 * 60)
        let duration = max(now.timeIntervalSince(start), 1)
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let point = { (value: (Date, Int)) in
            CGPoint(
                x: min(max(width * value.0.timeIntervalSince(start) / duration, 0), width),
                y: height * (1 - Double(value.1) / 100)
            )
        }

        for fraction in [0.0, 0.5, 1.0] {
            var guide = Path()
            let y = height * fraction
            guide.move(to: CGPoint(x: 0, y: y))
            guide.addLine(to: CGPoint(x: width, y: y))
            context.stroke(guide, with: .color(.secondary.opacity(0.22)), lineWidth: 1)
        }

        var path = Path()
        for (index, value) in values.enumerated() {
            let current = point(value)
            if index == 0 {
                path.move(to: current)
            } else {
                let previous = point(values[index - 1])
                path.addLine(to: CGPoint(x: current.x, y: previous.y))
                path.addLine(to: current)
            }
        }
        context.stroke(path, with: .color(color), lineWidth: 2)

        for (index, value) in values.enumerated() where index > 0 {
            let previous = values[index - 1]
            guard value.1 == 100, previous.1 < 100 else { continue }
            let resetPoint = point(value)
            var marker = Path()
            marker.move(to: CGPoint(x: resetPoint.x, y: 0))
            marker.addLine(to: CGPoint(x: resetPoint.x, y: height))
            context.stroke(
                marker,
                with: .color(color.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.fill(
                Path(ellipseIn: CGRect(x: resetPoint.x - 3, y: resetPoint.y - 3, width: 6, height: 6)),
                with: .color(color)
            )
            context.draw(
                Text("Reset")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color),
                at: CGPoint(x: min(resetPoint.x + 4, width - 36), y: 3),
                anchor: .topLeading
            )
        }
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var claude: ServiceUsage?
    @Published private(set) var codex: ServiceUsage?
    @Published private(set) var isRefreshing = false
    @Published private(set) var displayTime = Date.now
    @Published private(set) var historyPoints: [UsageHistoryPoint]

    private var lastSuccessfulRefresh: Date?
    private var lastRefreshFailed = false
    private var claudeError: String?
    private var codexError: String?

    private var refreshTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var didStart = false

    init() {
        historyPoints = UsageHistory.load()
    }

    deinit {
        refreshTask?.cancel()
        clockTask?.cancel()
    }

    var menuBarSummary: String? {
        var values: [String] = []
        if let claudeSession = claude?.windows.first?.percentLeft {
            values.append("C \(claudeSession)%")
        }
        if let codexFiveHour = codex?.windows.first?.percentLeft {
            values.append("O \(codexFiveHour)%")
        }
        return values.isEmpty ? nil : values.joined(separator: "  ")
    }

    var lastUpdatedText: String {
        guard let lastSuccessfulRefresh else { return "Noch keine erfolgreichen Daten" }
        let time = lastSuccessfulRefresh.formatted(date: .omitted, time: .shortened)
        if lastRefreshFailed {
            return "Aktualisierung fehlgeschlagen · Werte von \(time)"
        }
        if isStale {
            return "Daten veraltet · Werte von \(time)"
        }
        return "Aktuell · \(time)"
    }

    var statusColor: Color {
        if lastRefreshFailed || isStale { return .orange }
        return .secondary
    }

    var claudeIssue: String? { claudeError }
    var codexIssue: String? { codexError }

    private var isStale: Bool {
        guard let lastSuccessfulRefresh else { return false }
        return displayTime.timeIntervalSince(lastSuccessfulRefresh) > 120
    }

    func start() {
        guard !didStart else { return }
        didStart = true
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                self?.displayTime = .now
            }
        }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let result = await ProbeRunner.run()
            let claudeResult = result.first(where: { $0.service == "claude" })
            let codexResult = result.first(where: { $0.service == "codex" })
            let completedAt = Date.now

            if let claudeResult, claudeResult.ok {
                claude = claudeResult
                claudeError = nil
            } else {
                claudeError = claudeResult?.error ?? "Claude Code hat keine Daten geliefert."
            }
            if let codexResult, codexResult.ok {
                codex = codexResult
                codexError = nil
            } else {
                codexError = codexResult?.error ?? "Codex hat keine Daten geliefert."
            }

            let succeeded = claudeResult?.ok == true || codexResult?.ok == true
            lastRefreshFailed = !succeeded
            if succeeded {
                lastSuccessfulRefresh = completedAt
                appendHistory(at: completedAt)
            }
            displayTime = completedAt
            isRefreshing = false
        }
    }

    private func appendHistory(at timestamp: Date) {
        let point = UsageHistoryPoint(
            timestamp: timestamp,
            claudeSessionPercentLeft: claude?.windows.first?.percentLeft,
            codexFiveHourPercentLeft: codex?.windows.first?.percentLeft
        )
        historyPoints = UsageHistory.append(point, to: historyPoints)
    }
}

private enum ProbeRunner {
    static func run() async -> [ServiceUsage] {
        await Task.detached(priority: .utility) {
            let projectDirectory = FileManager.default.currentDirectoryPath
            let bundledProbe = Bundle.main.url(forResource: "LimitProbe", withExtension: nil)
            let developmentProbe = URL(fileURLWithPath: projectDirectory)
                .appendingPathComponent(".build/debug/LimitProbe")
            let probeURL = bundledProbe ?? developmentProbe
            guard FileManager.default.isExecutableFile(atPath: probeURL.path) else {
                return [
                    ServiceUsage.error(service: "claude", message: "LimitChecker-Helfer wurde nicht gefunden."),
                    ServiceUsage.error(service: "codex", message: "LimitChecker-Helfer wurde nicht gefunden."),
                ]
            }
            let process = Process()
            process.executableURL = probeURL
            process.arguments = ["--service", "all"]
            process.currentDirectoryURL = FileManager.default.temporaryDirectory
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()

            do {
                try process.run()
                let deadline = Date.now.addingTimeInterval(75)
                while process.isRunning && Date.now < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                    return [
                        ServiceUsage.error(service: "claude", message: "Aktualisierung hat zu lange gedauert."),
                        ServiceUsage.error(service: "codex", message: "Aktualisierung hat zu lange gedauert."),
                    ]
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return try JSONDecoder().decode(ProbePayload.self, from: data).results
            } catch {
                return [
                    ServiceUsage.error(service: "claude", message: error.localizedDescription),
                    ServiceUsage.error(service: "codex", message: error.localizedDescription),
                ]
            }
        }.value
    }
}

private struct ProbePayload: Decodable {
    let results: [ServiceUsage]
}

struct ServiceUsage: Decodable {
    let service: String
    let ok: Bool
    let windows: [LimitWindow]
    let error: String?

    static func error(service: String, message: String) -> ServiceUsage {
        ServiceUsage(service: service, ok: false, windows: [], error: message)
    }
}

struct LimitWindow: Decodable, Identifiable {
    let name: String
    let percentUsed: Int?
    private let percentLeftValue: Int?
    private let rawResets: String?

    private enum CodingKeys: String, CodingKey {
        case name
        case percentUsed = "percent_used"
        case percentLeftValue = "percent_left"
        case rawResets = "resets"
    }

    var id: String { name }
    var percentLeft: Int { percentLeftValue ?? max(0, 100 - (percentUsed ?? 0)) }
    var resets: String? { rawResets.map(ResetTimeFormatter.display) }
}

struct UsageHistoryPoint: Codable, Identifiable {
    let timestamp: Date
    let claudeSessionPercentLeft: Int?
    let codexFiveHourPercentLeft: Int?

    var id: Date { timestamp }
}

private enum UsageHistory {
    private static let retention: TimeInterval = 12 * 60 * 60

    static func load() -> [UsageHistoryPoint] {
        guard let data = try? Data(contentsOf: fileURL),
              let points = try? JSONDecoder().decode([UsageHistoryPoint].self, from: data) else {
            return []
        }
        return trim(points, now: .now)
    }

    static func append(_ point: UsageHistoryPoint, to existing: [UsageHistoryPoint]) -> [UsageHistoryPoint] {
        var points = trim(existing, now: point.timestamp)
        if points.last.map({ point.timestamp.timeIntervalSince($0.timestamp) < 30 }) != true {
            points.append(point)
        }
        if let data = try? JSONEncoder().encode(points) {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
        return points
    }

    private static var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("LimitChecker/history.json")
    }

    private static func trim(_ points: [UsageHistoryPoint], now: Date) -> [UsageHistoryPoint] {
        points.filter { $0.timestamp >= now.addingTimeInterval(-retention) }
    }
}

private enum ResetTimeFormatter {
    private static let months = [
        "Jan": "Jan.", "Feb": "Feb.", "Mar": "März", "Apr": "Apr.",
        "May": "Mai", "Jun": "Juni", "Jul": "Juli", "Aug": "Aug.",
        "Sep": "Sept.", "Oct": "Okt.", "Nov": "Nov.", "Dec": "Dez.",
    ]

    static func display(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "(Europe/Berlin)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let time = germanTime(in: cleaned) else { return cleaned }

        let words = cleaned
            .replacingOccurrences(of: "at", with: "")
            .replacingOccurrences(of: "on", with: "")
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        for (index, word) in words.enumerated() {
            guard let month = months[word] else { continue }
            if index + 1 < words.count, let day = Int(words[index + 1]) {
                return "\(day). \(month), \(time)"
            }
            if index > 0, let day = Int(words[index - 1]) {
                return "\(day). \(month), \(time)"
            }
        }

        let currentHour = Calendar.current.component(.hour, from: .now)
        let resetHour = Int(time.prefix(2)) ?? currentHour
        return resetHour < currentHour ? "Morgen, \(time)" : "Heute, \(time)"
    }

    private static func germanTime(in text: String) -> String? {
        let pattern = #"(?i)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              let hourValue = Int(text[hourRange]) else { return nil }
        let minute = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
        let meridiem = Range(match.range(at: 3), in: text).map { String(text[$0]).lowercased() }
        let hour: Int
        switch meridiem {
        case "am" where hourValue == 12: hour = 0
        case "pm" where hourValue < 12: hour = hourValue + 12
        default: hour = hourValue
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}
