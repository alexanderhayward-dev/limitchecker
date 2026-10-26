import Accessibility
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

/// Layout, type and colour tokens of the detail window. DESIGN.md gives the reasons;
/// the values live here.
enum Theme {
    static let width: CGFloat = 400
    static let outerPadding: CGFloat = 12
    static let platterPadding: CGFloat = 12
    static let platterSpacing: CGFloat = 8
    static let platterRadius: CGFloat = 10
    static let rowSpacing: CGFloat = 12
    static let barHeight: CGFloat = 6
    static let hitTarget: CGFloat = 24

    static let platterFill = Color.primary.opacity(0.05)
    static let hairline = Color.primary.opacity(0.08)
    static let barTrack = Color.primary.opacity(0.10)
    static let barNeutral = Color.primary.opacity(0.55)
    static let gridline = Color.secondary.opacity(0.25)
    static let leader = Color.secondary.opacity(0.5)
    /// Line opacity across time without measurements, usually a sleeping Mac.
    static let bridgeOpacity = 0.35

    /// Secondary text. The system's secondary label measured 3.9:1 on a light module;
    /// this tone measured 5.6:1 light and 5.9:1 dark.
    static let secondaryText = Color.primary.opacity(0.72)

    /// Colour is a signal: only these two mean "look here". They colour fills and symbols,
    /// never text, which they would not carry legibly on a light background.
    static let warning = Color.orange
    static let critical = Color.red

    /// Series colours stay clear of the signal colours.
    static let claudeSeries = Color.purple
    static let codexSeries = Color.blue

    /// Narrow no-break space between number and percent sign, as German typesetting has it.
    static func percent(_ value: Int) -> String { "\(value)\u{202F}%" }
}

/// A Control-Center-style module on the window's material.
private struct Platter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.platterRadius, style: .continuous)
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.platterPadding)
            .background(Theme.platterFill, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline))
    }
}

private struct LimitMenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.platterSpacing) {
            header

            ServicePlatter(
                title: "Claude Code",
                usage: store.claude,
                issue: store.claudeIssue,
                isRefreshing: store.isRefreshing,
                now: store.displayTime
            )
            ServicePlatter(
                title: "Codex",
                usage: store.codex,
                issue: store.codexIssue,
                isRefreshing: store.isRefreshing,
                now: store.displayTime
            )

            // After the quotas: the window answers "how much is left" first. The menu bar
            // dot already announces the update.
            if updateStore.availableRelease != nil {
                Platter { UpdateBanner(store: updateStore) }
            }

            Platter { UsageHistoryView(points: store.historyPoints, now: store.displayTime) }

            statusLine
                .padding(.horizontal, Theme.platterPadding)
                .padding(.top, 2)
        }
        .padding(Theme.outerPadding)
        .frame(width: Theme.width)
        .onAppear {
            store.start()
            updateStore.start()
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Text("LimitChecker")
                .font(.headline)
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                    .help("Aktualisiere")
                    .accessibilityLabel("Aktualisiere")
            } else {
                Button(action: store.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("Aktualisieren")
                .accessibilityLabel("Aktualisieren")
            }
            OptionsMenu(updateStore: updateStore)
        }
        .padding(.leading, Theme.platterPadding)
    }

    @ViewBuilder
    private var statusLine: some View {
        if store.statusNeedsAttention {
            Label {
                Text(store.lastUpdatedText).foregroundStyle(Theme.secondaryText)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warning)
            }
            .font(.subheadline)
        } else {
            Text(store.lastUpdatedText)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}

private struct OptionsMenu: View {
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        Menu {
            UpdateMenuItems(store: updateStore)
            Divider()
            Button("LimitChecker beenden") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            // The frame belongs inside the label: outside, it only pads the layout and
            // leaves the clickable area at the symbol's size.
            Image(systemName: "ellipsis.circle")
                .frame(width: Theme.hitTarget, height: Theme.hitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Optionen")
        .accessibilityLabel("Optionen")
    }
}

private struct ServicePlatter: View {
    let title: String
    let usage: ServiceUsage?
    let issue: String?
    let isRefreshing: Bool
    let now: Date

    var body: some View {
        Platter {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                Text(title)
                    .font(.body.weight(.semibold))

                if let usage, usage.ok {
                    ForEach(usage.windows) { window in
                        LimitRow(window: window, capturedAt: usage.capturedAt, capturedZone: usage.capturedZone, now: now)
                    }
                    if let issue {
                        IssueLine(text: issue)
                    }
                } else if isRefreshing {
                    // Shaped like the real rows, so the window keeps its height when data arrives.
                    ForEach(LimitWindow.placeholders) { window in
                        LimitRow(window: window, capturedAt: now, capturedZone: .current, now: now)
                    }
                    .redacted(reason: .placeholder)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Wird geladen")
                } else if let issue {
                    IssueLine(text: issue)
                } else {
                    Text(usage?.error ?? "Noch nicht abgerufen")
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct IssueLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
        }
        .font(.callout)
    }
}

private struct LimitRow: View {
    let window: LimitWindow
    let capturedAt: Date
    let capturedZone: TimeZone
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(window.displayName)
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text(Theme.percent(window.percentLeft))
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text("frei")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
            LimitProgressBar(percentLeft: window.percentLeft, tint: tint)
            if let resets = window.resetText(capturedAt: capturedAt, capturedZone: capturedZone, now: now) {
                Text("Reset \(resets)")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        switch window.percentLeft {
        case ...20: Theme.critical
        case ...50: Theme.warning
        default: Theme.barNeutral
        }
    }
}

private struct LimitProgressBar: View {
    let percentLeft: Int
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GeometryReader { geometry in
            // Redaction hides text only; an unfilled track keeps a placeholder from passing for data.
            let fraction = redactionReasons.isEmpty ? min(max(Double(percentLeft) / 100, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.barTrack)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: Theme.barHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: percentLeft)
        .accessibilityHidden(true)
    }
}

private struct HistorySeries {
    enum Marker { case circle, square }

    let name: String
    let color: Color
    /// Tells the series apart without colour, at the line end and next to the name.
    let marker: Marker
    let values: [(Date, Int)]
}

private enum HistoryWindow {
    static let span: TimeInterval = 12 * 60 * 60
    /// The chart shows the rough course, one value per bucket; per-minute steps are noise.
    static let bucket: TimeInterval = 10 * 60
    /// Longer stretches without a measurement (the Mac was asleep) are bridged faintly.
    static let maxGap: TimeInterval = 25 * 60
    /// Rises in percentage points that count as a reset: anywhere, or ending on 100 %.
    static let resetRise = 30
    static let resetRiseToFull = 10
}

private struct UsageHistoryView: View {
    let points: [UsageHistoryPoint]
    let now: Date

    /// The values inside the visible window. Empty state, drawing, labels and VoiceOver
    /// all read this one set, so they cannot disagree about what is shown.
    private var series: [HistorySeries] {
        let start = now.addingTimeInterval(-HistoryWindow.span)
        let visible = points.filter { $0.timestamp >= start && $0.timestamp <= now }
        return [
            HistorySeries(
                name: "Claude",
                color: Theme.claudeSeries,
                marker: .circle,
                values: visible.compactMap { point in point.claudeSessionPercentLeft.map { (point.timestamp, $0) } }
            ),
            HistorySeries(
                name: "Codex",
                color: Theme.codexSeries,
                marker: .square,
                values: visible.compactMap { point in point.codexFiveHourPercentLeft.map { (point.timestamp, $0) } }
            ),
        ]
        .filter { !$0.values.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Verlauf")
                    .font(.body.weight(.semibold))
                Text("5-Stunden-Fenster, letzte 12 Std.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            }

            let current = series
            if current.isEmpty {
                Text("Der Verlauf baut sich mit den nächsten Aktualisierungen auf.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                HistoryChart(series: current, now: now)
            }
        }
    }
}

/// Both series share one 0–100 scale and one time axis; each is labelled directly at its
/// end instead of through a legend.
private struct HistoryChart: View {
    let series: [HistorySeries]
    let now: Date

    private let topBand: CGFloat = 16
    private let plotHeight: CGFloat = 72
    private let bottomBand: CGFloat = 22
    private let axisWidth: CGFloat = 38
    private let labelWidth: CGFloat = 88

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .frame(height: topBand + plotHeight + bottomBand)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf der letzten 12 Stunden")
        .accessibilityValue(summary)
        .accessibilityChartDescriptor(HistoryChartDescriptor(series: series, now: now))
    }

    private var summary: String {
        series.compactMap { item -> String? in
            guard let first = item.values.first, let last = item.values.last else { return nil }
            var text = "\(item.name): \(Theme.percent(last.1)) frei"
            if now.timeIntervalSince(last.0) > HistoryWindow.maxGap {
                text += ", letzter Wert \(ago(last.0))"
            }
            if item.values.count > 1 {
                text += ", \(ago(first.0)) \(Theme.percent(first.1))"
            }
            let resets = Self.resetCount(in: item.values)
            if resets > 0 { text += resets == 1 ? ", ein Reset" : ", \(resets) Resets" }
            return text
        }
        .joined(separator: "; ")
    }

    private func ago(_ date: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 60 ? "vor \(max(minutes, 1)) Min." : "vor \(Int((Double(minutes) / 60).rounded())) Std."
    }

    /// Usage only ever lowers the remaining quota, so a rise means a reset: a large one even
    /// when the next measurement no longer reads exactly 100 %, a smaller one when it lands
    /// on 100 %. A point or two is rounding. After a gap the moment is unknown, so none is claimed.
    static func isReset(from previous: (Date, Int), to value: (Date, Int)) -> Bool {
        let rise = value.1 - previous.1
        let isJump = rise >= HistoryWindow.resetRise || (value.1 == 100 && rise >= HistoryWindow.resetRiseToFull)
        return isJump && value.0.timeIntervalSince(previous.0) <= HistoryWindow.maxGap
    }

    static func resetCount(in values: [(Date, Int)]) -> Int {
        let values = bucketed(values)
        return zip(values, values.dropFirst()).filter { isReset(from: $0, to: $1) }.count
    }

    /// The last value of every bucket, at its own time.
    static func bucketed(_ values: [(Date, Int)]) -> [(Date, Int)] {
        var result: [(Date, Int)] = []
        var currentBucket: Int?
        for value in values {
            let bucket = Int(value.0.timeIntervalSinceReferenceDate / HistoryWindow.bucket)
            if bucket == currentBucket {
                result[result.count - 1] = value
            } else {
                result.append(value)
                currentBucket = bucket
            }
        }
        return result
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let plot = CGRect(
            x: axisWidth,
            y: topBand,
            width: max(size.width - axisWidth - labelWidth, 1),
            height: plotHeight
        )
        let start = now.addingTimeInterval(-HistoryWindow.span)
        func x(_ date: Date) -> CGFloat {
            plot.minX + plot.width * CGFloat(min(max(date.timeIntervalSince(start) / HistoryWindow.span, 0), 1))
        }
        func y(_ percent: Int) -> CGFloat {
            plot.maxY - plot.height * CGFloat(min(max(percent, 0), 100)) / 100
        }

        for percent in [0, 50, 100] {
            var guide = Path()
            guide.move(to: CGPoint(x: plot.minX, y: y(percent)))
            guide.addLine(to: CGPoint(x: plot.maxX, y: y(percent)))
            context.stroke(guide, with: .color(Theme.gridline), lineWidth: 1)
            context.draw(
                Text(Theme.percent(percent)).font(.subheadline).monospacedDigit().foregroundStyle(Theme.secondaryText),
                at: CGPoint(x: plot.minX - 6, y: y(percent)),
                anchor: .trailing
            )
        }

        // Time labels at their exact positions; spacers between labels of unequal width
        // would pull "vor 6 Std." off the middle.
        let timeLabels: [(String, CGFloat, UnitPoint)] = [
            ("vor 12 Std.", plot.minX, .topLeading),
            ("vor 6 Std.", plot.midX, .top),
            ("jetzt", plot.maxX, .topTrailing),
        ]
        for (text, labelX, anchor) in timeLabels {
            context.draw(
                Text(text).font(.subheadline).foregroundStyle(Theme.secondaryText),
                at: CGPoint(x: labelX, y: plot.maxY + 8),
                anchor: anchor
            )
        }

        var resetLabels: [CGFloat] = []
        for item in series {
            let values = Self.bucketed(item.values)
            var measured = Path()
            var bridged = Path()
            for (previous, value) in zip(values, values.dropFirst()) {
                let from = CGPoint(x: x(previous.0), y: y(previous.1))
                let to = CGPoint(x: x(value.0), y: y(value.1))
                if value.0.timeIntervalSince(previous.0) > HistoryWindow.maxGap {
                    // No measurements in between: keep the course readable, but faint, so
                    // the estimate does not pass for data.
                    bridged.move(to: from)
                    bridged.addLine(to: to)
                    continue
                }
                measured.move(to: from)
                measured.addLine(to: to)
                if Self.isReset(from: previous, to: value) {
                    var marker = Path()
                    marker.move(to: CGPoint(x: to.x, y: plot.minY))
                    marker.addLine(to: CGPoint(x: to.x, y: plot.maxY))
                    context.stroke(marker, with: .color(item.color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    // Above the plot, so the label never sits on a line.
                    let labelX = min(max(to.x, plot.minX + 16), plot.maxX - 16)
                    if resetLabels.allSatisfy({ abs($0 - labelX) > 40 }) {
                        resetLabels.append(labelX)
                        context.draw(
                            Text("Reset").font(.subheadline).foregroundStyle(Theme.secondaryText),
                            at: CGPoint(x: labelX, y: 0),
                            anchor: .top
                        )
                    }
                }
            }
            let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            context.stroke(bridged, with: .color(item.color.opacity(Theme.bridgeOpacity)), style: style)
            context.stroke(measured, with: .color(item.color), style: style)
        }

        // Direct labels right of the plot. Each line ends in its marker at its real last value;
        // a thin leader joins marker and label whenever the label had to move or the data is old.
        let ends = series.compactMap { item -> (HistorySeries, CGPoint, Int)? in
            guard let last = item.values.last else { return nil }
            return (item, CGPoint(x: x(last.0), y: y(last.1)), last.1)
        }
        .sorted { $0.1.y < $1.1.y }
        var labelYs = ends.map(\.1.y)
        for index in labelYs.indices.dropFirst() {
            labelYs[index] = max(labelYs[index], labelYs[index - 1] + 15)
        }
        if let overflow = labelYs.last.map({ $0 - (plot.maxY + 7) }), overflow > 0 {
            labelYs = labelYs.map { $0 - overflow }
        }
        for (index, end) in ends.enumerated() {
            let (item, endPoint, percent) = end
            let labelY = labelYs[index]
            context.fill(Self.markerPath(item.marker, at: endPoint), with: .color(item.color))
            var leader = Path()
            leader.move(to: CGPoint(x: endPoint.x + 4, y: endPoint.y))
            leader.addLine(to: CGPoint(x: plot.maxX + 6, y: labelY))
            if abs(labelY - endPoint.y) > 1 || plot.maxX - endPoint.x > 4 {
                context.stroke(leader, with: .color(Theme.leader), lineWidth: 1)
            }
            context.fill(Self.markerPath(item.marker, at: CGPoint(x: plot.maxX + 11, y: labelY)), with: .color(item.color))
            context.draw(
                Text("\(item.name) \(Theme.percent(percent))").font(.subheadline.weight(.medium)).monospacedDigit(),
                at: CGPoint(x: plot.maxX + 20, y: labelY),
                anchor: .leading
            )
        }
    }
}

private extension HistoryChart {
    static func markerPath(_ marker: HistorySeries.Marker, at center: CGPoint) -> Path {
        let size: CGFloat = 7
        let rect = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
        switch marker {
        case .circle: return Path(ellipseIn: rect)
        case .square: return Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 1.5)
        }
    }
}

/// Gives VoiceOver the full series as an audio graph instead of two end values.
private struct HistoryChartDescriptor: AXChartDescriptorRepresentable {
    let series: [HistorySeries]
    let now: Date

    func makeChartDescriptor() -> AXChartDescriptor {
        let xAxis = AXNumericDataAxisDescriptor(
            title: "Zeit",
            range: -12...0,
            gridlinePositions: [-12, -6, 0]
        ) { value in
            let minutes = Int((-value * 60).rounded())
            switch minutes {
            case ..<1: return "jetzt"
            case ..<60: return "vor \(minutes) Min."
            default: return "vor \(Int((Double(minutes) / 60).rounded())) Std."
            }
        }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "Restkontingent",
            range: 0...100,
            gridlinePositions: [0, 50, 100]
        ) { value in
            Theme.percent(Int(value.rounded()))
        }
        let dataSeries = series.map { item in
            // Discrete points: gaps and resets stay audible instead of being bridged.
            AXDataSeriesDescriptor(
                name: item.name,
                isContinuous: false,
                dataPoints: item.values.map { value in
                    AXDataPoint(x: value.0.timeIntervalSince(now) / 3600, y: Double(value.1))
                }
            )
        }
        return AXChartDescriptor(
            title: "Verlauf der 5-Stunden-Fenster",
            summary: nil,
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: dataSeries
        )
    }

    /// Without this, VoiceOver keeps the descriptor from the first render while the data moves on.
    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        let current = makeChartDescriptor()
        descriptor.title = current.title
        descriptor.summary = current.summary
        descriptor.xAxis = current.xAxis
        descriptor.yAxis = current.yAxis
        descriptor.series = current.series
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

    var statusNeedsAttention: Bool { lastRefreshFailed || isStale }

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
                // systemUptime stands still while the Mac sleeps. A wall-clock deadline expired
                // across every sleep and killed helpers that were merely suspended, before
                // they could end their CLI sessions.
                let deadline = ProcessInfo.processInfo.systemUptime + 75
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if process.isRunning {
                    // SIGTERM lets the helper end its CLI sessions first; it needs about a second.
                    process.terminate()
                    let grace = ProcessInfo.processInfo.systemUptime + 3
                    while process.isRunning && ProcessInfo.processInfo.systemUptime < grace {
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
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
    /// When the probe delivered this result. Reset times like "3:40pm" only make sense
    /// relative to it; the store keeps showing old results after a failed refresh.
    var capturedAt = Date.now
    /// The zone the CLI's wall-clock times were meant in, unless the text names one.
    var capturedZone = TimeZone.current

    private enum CodingKeys: String, CodingKey {
        case service, ok, windows, error
    }

    static func error(service: String, message: String) -> ServiceUsage {
        ServiceUsage(service: service, ok: false, windows: [], error: message, capturedAt: .now)
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

    init(name: String, percentLeft: Int, resets: String?) {
        self.name = name
        percentUsed = 100 - percentLeft
        percentLeftValue = percentLeft
        rawResets = resets
    }

    var id: String { name }
    var percentLeft: Int { percentLeftValue ?? max(0, 100 - (percentUsed ?? 0)) }

    func resetText(capturedAt: Date, capturedZone: TimeZone, now: Date) -> String? {
        rawResets.map { ResetTimeFormatter.display($0, capturedAt: capturedAt, capturedZone: capturedZone, now: now) }
    }

    private static let knownNames: [(prefix: String, german: String)] = [
        ("current session", "5-Stunden-Fenster"),
        ("5h limit", "5-Stunden-Fenster"),
        ("current week", "Woche"),
        ("weekly limit", "Woche"),
    ]

    /// The CLIs name the same two windows differently, and in English. Only the known base
    /// names are translated, anything after them is kept; unknown names pass unchanged.
    var displayName: String {
        let lower = name.lowercased()
        guard let known = Self.knownNames.first(where: { entry in
            // Whole words only: "Current weekly limit" must not become "Wochely limit".
            guard lower.hasPrefix(entry.prefix) else { return false }
            return lower.dropFirst(entry.prefix.count).first.map { !$0.isLetter && !$0.isNumber } ?? true
        }) else {
            return name
        }
        let rest = String(name.dropFirst(known.prefix.count))
            .replacingOccurrences(of: "all models", with: "alle Modelle")
        return known.german + rest
    }

    static let placeholders = [
        LimitWindow(name: "5-Stunden-Fenster", percentLeft: 60, resets: "15:00"),
        LimitWindow(name: "Woche", percentLeft: 60, resets: "15:00"),
    ]
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

enum ResetTimeFormatter {
    private static let monthNames = [
        "Jan.", "Feb.", "März", "Apr.", "Mai", "Juni",
        "Juli", "Aug.", "Sept.", "Okt.", "Nov.", "Dez.",
    ]
    private static let englishMonths = [
        "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
        "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
    ]

    /// "heute 15:40", "morgen 02:00", "29. Okt., 02:00". The reset is fixed as an instant
    /// from the measurement time and the zone the CLI meant; only the wording follows the
    /// clock and zone of the reader. An old value never turns a past reset into tomorrow's,
    /// and a trip to another zone shows the reset in local time.
    static func display(
        _ raw: String,
        capturedAt: Date,
        capturedZone: TimeZone,
        now: Date,
        displayZone: TimeZone = .current
    ) -> String {
        let cleaned = raw.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceZone = namedZone(in: raw) ?? capturedZone
        guard let date = resetDate(cleaned, capturedAt: capturedAt, zone: sourceZone) else { return cleaned }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = displayZone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let offset = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)
        ).day ?? 0
        switch offset {
        case 0: return "heute \(time)"
        case 1: return "morgen \(time)"
        case -1: return "gestern \(time)"
        default: return "\(parts.day ?? 0). \(monthNames[(parts.month ?? 1) - 1]), \(time)"
        }
    }

    /// "(Europe/Berlin)" as Claude Code prints it, or any other zone name or abbreviation.
    static func namedZone(in raw: String) -> TimeZone? {
        guard let range = raw.range(of: #"\([^()]+\)"#, options: .regularExpression) else { return nil }
        let name = raw[range].dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        return TimeZone(identifier: name) ?? TimeZone(abbreviation: name)
    }

    static func resetDate(_ text: String, capturedAt: Date, zone: TimeZone) -> Date? {
        guard let time = clockTime(in: text) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        let words = text.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        if let index = words.firstIndex(where: { englishMonths[$0] != nil }) {
            let day = (index + 1 < words.count ? Int(words[index + 1]) : nil)
                ?? (index > 0 ? Int(words[index - 1]) : nil)
            guard let day, let month = englishMonths[words[index]] else { return nil }
            // The text has no year: take the one that puts the date nearest the measurement,
            // which covers "Jan 2" in late December and "Dec 31" on New Year's Day alike.
            let year = calendar.component(.year, from: capturedAt)
            return (year - 1...year + 1)
                .compactMap { candidate in
                    calendar.date(from: DateComponents(year: candidate, month: month, day: day, hour: time.hour, minute: time.minute))
                }
                .min { abs($0.timeIntervalSince(capturedAt)) < abs($1.timeIntervalSince(capturedAt)) }
        }

        // A bare time is its next occurrence after the measurement. On the day the clocks go
        // back, 02:30 happens twice: asking for both and taking the earlier one finds the
        // first when it is still ahead and the second once the first has passed.
        let after = capturedAt.addingTimeInterval(-60)
        let wanted = DateComponents(hour: time.hour, minute: time.minute)
        return [Calendar.RepeatedTimePolicy.first, .last]
            .compactMap { policy in
                calendar.nextDate(after: after, matching: wanted, matchingPolicy: .nextTime, repeatedTimePolicy: policy)
            }
            .min()
    }

    /// A time of day: "3:40pm", "2am" or "15:40". A bare number is not one: in
    /// "Oct 22 at 2am" the 22 is the day, and reading it as the hour showed 22:00.
    static func clockTime(in text: String) -> (hour: Int, minute: Int)? {
        let pattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b|\b(\d{1,2}):(\d{2})\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }

        if let meridiem = group(3)?.lowercased(), let rawHour = group(1).flatMap(Int.init), (1...12).contains(rawHour) {
            let minute = group(2).flatMap(Int.init) ?? 0
            guard minute < 60 else { return nil }
            let hour = rawHour % 12 + (meridiem == "pm" ? 12 : 0)
            return (hour, minute)
        }
        if let hour = group(4).flatMap(Int.init), let minute = group(5).flatMap(Int.init), hour < 24, minute < 60 {
            return (hour, minute)
        }
        return nil
    }
}
