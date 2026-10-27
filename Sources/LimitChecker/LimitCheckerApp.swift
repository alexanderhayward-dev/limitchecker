import Accessibility
import Foundation
import ImageIO
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
    /// Side inset of text and separators, as in Apple's menus.
    static let sectionInset: CGFloat = 16
    static let sectionPadding: CGFloat = 12
    static let rowSpacing: CGFloat = 12
    static let barHeight: CGFloat = 6
    static let hitTarget: CGFloat = 24
    static let iconSize: CGFloat = 28

    static let separator = Color.primary.opacity(0.12)
    static let barTrack = Color.primary.opacity(0.10)
    /// Darkens the window's glass in dark mode to the depth of the system menus, which sit
    /// on a darker glass than a SwiftUI menu bar window gets by default.
    static let darkGlassShade = Color.black.opacity(0.3)
    static let gridline = Color.secondary.opacity(0.25)
    static let leader = Color.secondary.opacity(0.5)
    /// Line opacity across time without measurements, usually a sleeping Mac.
    static let bridgeOpacity = 0.35

    /// Secondary text. The system's secondary label measured 3.9:1 on a light module;
    /// this tone measured 5.6:1 light and 5.9:1 dark.
    static let secondaryText = Color.primary.opacity(0.72)

    /// Colour means one of two things. Each service has its brand colour, taken from its app
    /// icon: its bars and its chart line. The icon itself is the original one, read from the
    /// installed app.
    static let claude = ServiceStyle(
        color: Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255),
        icon: .appIcon(bundleID: "com.anthropic.claudefordesktop"),
        fallbackSymbol: "asterisk"
    )
    static let codex = ServiceStyle(
        color: Color(red: 0x64 / 255, green: 0x7A / 255, blue: 0xF8 / 255),
        icon: .appResource(bundleID: "com.openai.codex", light: "icon-codex-light", dark: "icon-codex-dark-color"),
        fallbackSymbol: "cloud.fill"
    )

    /// The signals: red takes over a bar that runs low, orange marks problems. They colour
    /// fills and symbols, never text, which they would not carry legibly on a light background.
    /// Orange no longer marks a half-used bar: Claude's own colour is orange.
    static let warning = Color.orange
    static let critical = Color.red

    /// Narrow no-break space between number and percent sign, as German typesetting has it.
    static func percent(_ value: Int) -> String { "\(value)\u{202F}%" }
}

struct ServiceStyle {
    enum IconSource {
        case appIcon(bundleID: String)
        /// The Codex app shows its cloud icon from a resource; its bundle icon is another one.
        case appResource(bundleID: String, light: String, dark: String)
    }

    let color: Color
    let icon: IconSource
    /// Shown on a disc in the service colour when the app is not installed.
    let fallbackSymbol: String
}

/// Reads the services' original icons from the installed apps, so none ship with LimitChecker.
@MainActor
enum ServiceIcons {
    private static var cache: [String: NSImage] = [:]

    static func image(for source: ServiceStyle.IconSource, dark: Bool) -> NSImage? {
        let key = "\(source)-\(dark)"
        if let cached = cache[key] { return cached }
        let image: NSImage?
        switch source {
        case .appIcon(let bundleID):
            image = appURL(bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        case .appResource(let bundleID, let light, let darkName):
            image = appURL(bundleID)
                .flatMap { Bundle(url: $0)?.url(forResource: dark ? darkName : light, withExtension: "png") }
                .flatMap { downsampled($0, points: Theme.iconSize) }
        }
        if let image { cache[key] = image }
        return image
    }

    /// The resource holds a single 1024 px image. SwiftUI shrinks that so coarsely that the
    /// cloud's glossy rim breaks into white specks, so ImageIO filters it down to each scale.
    private static func downsampled(_ url: URL, points: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let image = NSImage(size: NSSize(width: points, height: points))
        for scale in [1, 2, 3] as [CGFloat] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: points * scale,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { continue }
            let rep = NSBitmapImageRep(cgImage: thumbnail)
            rep.size = image.size
            image.addRepresentation(rep)
        }
        return image.representations.isEmpty ? nil : image
    }

    private static func appURL(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// A section of the window, sitting directly on the glass like the sections of Apple's menus.
private struct MenuSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.sectionInset)
            .padding(.vertical, Theme.sectionPadding)
    }
}

private struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
            .padding(.horizontal, Theme.sectionInset)
    }
}

private struct LimitMenuView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MenuSeparator()
            ServiceSection(
                title: "Claude Code",
                style: Theme.claude,
                usage: store.claude,
                issue: store.claudeIssue,
                isRefreshing: store.isRefreshing,
                now: store.displayTime
            )
            MenuSeparator()
            ServiceSection(
                title: "Codex",
                style: Theme.codex,
                usage: store.codex,
                issue: store.codexIssue,
                isRefreshing: store.isRefreshing,
                now: store.displayTime
            )

            // After the quotas: the window answers "how much is left" first. The menu bar
            // dot already announces the update.
            if updateStore.availableRelease != nil {
                MenuSeparator()
                MenuSection { UpdateBanner(store: updateStore) }
            }

            MenuSeparator()
            MenuSection {
                UsageHistoryView(
                    points: store.historyPoints,
                    now: store.displayTime,
                    claudeWindowStart: store.claude?.currentWindowStart,
                    codexWindowStart: store.codex?.currentWindowStart
                )
            }

            MenuSeparator()
            HStack(alignment: .firstTextBaseline) {
                statusLine
                Spacer()
                Text("Version \(updateStore.currentVersionText)")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, Theme.sectionInset)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .frame(width: Theme.width)
        .background(GlassShade())
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
        .padding(.leading, Theme.sectionInset)
        .padding(.trailing, Theme.sectionInset - 6)
        .padding(.top, 10)
        .padding(.bottom, 8)
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

/// Darkens the glass in dark mode only; Apple's light menus are as light as ours.
private struct GlassShade: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            Theme.darkGlassShade
        }
    }
}

private struct ServiceSection: View {
    let title: String
    let style: ServiceStyle
    let usage: ServiceUsage?
    let issue: String?
    let isRefreshing: Bool
    let now: Date

    var body: some View {
        MenuSection {
            VStack(alignment: .leading, spacing: Theme.rowSpacing) {
                HStack(spacing: 6) {
                    ServiceIcon(style: style, isActive: usage?.ok == true)
                    Text(title)
                        .font(.body.weight(.semibold))
                }

                if let usage, usage.ok {
                    ForEach(usage.windows) { window in
                        LimitRow(
                            window: window,
                            color: style.color,
                            capturedAt: usage.capturedAt,
                            capturedZone: usage.capturedZone,
                            now: now
                        )
                    }
                    if let issue {
                        IssueLine(text: issue)
                    }
                } else if isRefreshing {
                    // Shaped like the real rows, so the window keeps its height when data arrives.
                    ForEach(LimitWindow.placeholders) { window in
                        LimitRow(window: window, color: style.color, capturedAt: now, capturedZone: .current, now: now)
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

/// The service's own app icon. Without current data it turns grey, as Apple's menus show an
/// inactive item.
private struct ServiceIcon: View {
    let style: ServiceStyle
    let isActive: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = ServiceIcons.image(for: style.icon, dark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: style.fallbackSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Theme.iconSize - 6, height: Theme.iconSize - 6)
                    .background(style.color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .frame(width: Theme.iconSize, height: Theme.iconSize)
        .saturation(isActive ? 1 : 0)
        .opacity(isActive ? 1 : 0.5)
        .accessibilityHidden(true)
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
    let color: Color
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
        default: color
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

private struct HistorySample {
    let time: Date
    let percent: Int
    /// Start of the 5-hour window this value belongs to, when known.
    var windowStart: Date?
}

private struct HistorySeries {
    enum Marker { case circle, square }

    let name: String
    let color: Color
    /// Tells the series apart without colour, at the line end and next to the name.
    let marker: Marker
    let values: [HistorySample]
}

private enum HistoryWindow {
    static let span: TimeInterval = 12 * 60 * 60
    /// The chart shows the rough course, one value per bucket; per-minute steps are noise.
    static let bucket: TimeInterval = 10 * 60
    /// Longer stretches without a measurement (the Mac was asleep) are bridged faintly.
    static let maxGap: TimeInterval = 25 * 60
    /// Both charted limits are 5-hour windows: each one starts five hours before its reset.
    static let sessionLength: TimeInterval = 5 * 60 * 60
    /// Without a known window start: rises in percentage points that count as a reset,
    /// anywhere or ending on 100 %.
    static let resetRise = 30
    static let resetRiseToFull = 10
}

private struct UsageHistoryView: View {
    let points: [UsageHistoryPoint]
    let now: Date
    /// Start of the window running now, from the latest reading.
    let claudeWindowStart: Date?
    let codexWindowStart: Date?

    /// The values inside the visible window. Empty state, drawing, labels and VoiceOver
    /// all read this one set, so they cannot disagree about what is shown.
    private var series: [HistorySeries] {
        let start = now.addingTimeInterval(-HistoryWindow.span)
        let visible = points.filter { $0.timestamp >= start && $0.timestamp <= now }
        func windowStart(_ resetAt: Date?) -> Date? {
            resetAt?.addingTimeInterval(-HistoryWindow.sessionLength)
        }
        return [
            HistorySeries(
                name: "Claude",
                color: Theme.claude.color,
                marker: .circle,
                values: Self.fillingWindowStarts(
                    visible.compactMap { point in
                        point.claudeSessionPercentLeft.map {
                            HistorySample(time: point.timestamp, percent: $0, windowStart: windowStart(point.claudeSessionResetAt))
                        }
                    },
                    current: claudeWindowStart
                )
            ),
            HistorySeries(
                name: "Codex",
                color: Theme.codex.color,
                marker: .square,
                values: Self.fillingWindowStarts(
                    visible.compactMap { point in
                        point.codexFiveHourPercentLeft.map {
                            HistorySample(time: point.timestamp, percent: $0, windowStart: windowStart(point.codexFiveHourResetAt))
                        }
                    },
                    current: codexWindowStart
                )
            ),
        ]
        .filter { !$0.values.isEmpty }
    }

    /// Points saved before 1.0.11 carry no reset time. Every point at or after a known window
    /// start still belongs to that window, so the start is carried back from the newest known
    /// one, beginning with the current reading, until the first point that predates it.
    static func fillingWindowStarts(_ samples: [HistorySample], current: Date?) -> [HistorySample] {
        var result = samples
        var known = current
        for index in result.indices.reversed() {
            if let own = result[index].windowStart {
                known = own
            } else if let start = known, result[index].time >= start {
                result[index].windowStart = start
            }
        }
        return result
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
            var text = "\(item.name): \(Theme.percent(last.percent)) frei"
            if now.timeIntervalSince(last.time) > HistoryWindow.maxGap {
                text += ", letzter Wert \(ago(last.time))"
            }
            if item.values.count > 1 {
                text += ", \(ago(first.time)) \(Theme.percent(first.percent))"
            }
            let resets = Self.resetMoments(in: item.values)
            if let latest = resets.last {
                let time = latest.formatted(date: .omitted, time: .shortened)
                text += resets.count == 1 ? ", Reset um \(time)" : ", \(resets.count) Resets, zuletzt um \(time)"
            }
            return text
        }
        .joined(separator: "; ")
    }

    private func ago(_ date: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 60 ? "vor \(max(minutes, 1)) Min." : "vor \(Int((Double(minutes) / 60).rounded())) Std."
    }

    /// When the window rolled over between two samples, if it did. Exact when the later sample
    /// knows its window start, even across a stretch the Mac slept through. Without one, a sharp
    /// rise between close samples counts: usage only lowers the remaining quota.
    static func resetMoment(from previous: HistorySample, to value: HistorySample) -> Date? {
        if let start = value.windowStart {
            // A window nobody used rolls over without anything to show.
            guard start > previous.time, start <= value.time, previous.percent < 100 else { return nil }
            return start
        }
        let rise = value.percent - previous.percent
        let isJump = rise >= HistoryWindow.resetRise || (value.percent == 100 && rise >= HistoryWindow.resetRiseToFull)
        guard isJump, value.time.timeIntervalSince(previous.time) <= HistoryWindow.maxGap else { return nil }
        return value.time
    }

    static func resetMoments(in values: [HistorySample]) -> [Date] {
        let values = bucketed(values)
        return zip(values, values.dropFirst()).compactMap { resetMoment(from: $0, to: $1) }
    }

    /// The last sample of every bucket, at its own time.
    static func bucketed(_ values: [HistorySample]) -> [HistorySample] {
        var result: [HistorySample] = []
        var currentBucket: Int?
        for value in values {
            let bucket = Int(value.time.timeIntervalSinceReferenceDate / HistoryWindow.bucket)
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
            // Stretches without measurements stay readable, but faint, so the estimate does
            // not pass for data.
            func segment(_ from: CGPoint, _ to: CGPoint, spanning duration: TimeInterval) {
                if duration > HistoryWindow.maxGap {
                    bridged.move(to: from)
                    bridged.addLine(to: to)
                } else {
                    measured.move(to: from)
                    measured.addLine(to: to)
                }
            }

            for (previous, value) in zip(values, values.dropFirst()) {
                let from = CGPoint(x: x(previous.time), y: y(previous.percent))
                let to = CGPoint(x: x(value.time), y: y(value.percent))
                guard let reset = Self.resetMoment(from: previous, to: value) else {
                    segment(from, to, spanning: value.time.timeIntervalSince(previous.time))
                    continue
                }

                // A reset is a jump at a known moment: the old level holds until then, the
                // quota returns to 100 %, and use in the new window takes it down again.
                let resetX = x(reset)
                let hold = CGPoint(x: resetX, y: from.y)
                let full = CGPoint(x: resetX, y: y(100))
                segment(from, hold, spanning: reset.timeIntervalSince(previous.time))
                measured.move(to: hold)
                measured.addLine(to: full)
                segment(full, to, spanning: value.time.timeIntervalSince(reset))

                var marker = Path()
                marker.move(to: CGPoint(x: resetX, y: plot.minY))
                marker.addLine(to: CGPoint(x: resetX, y: plot.maxY))
                context.stroke(marker, with: .color(item.color.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                // Above the plot, so the label never sits on a line.
                let labelX = min(max(resetX, plot.minX + 16), plot.maxX - 16)
                if resetLabels.allSatisfy({ abs($0 - labelX) > 40 }) {
                    resetLabels.append(labelX)
                    context.draw(
                        Text("Reset").font(.subheadline).foregroundStyle(Theme.secondaryText),
                        at: CGPoint(x: labelX, y: 0),
                        anchor: .top
                    )
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
            return (item, CGPoint(x: x(last.time), y: y(last.percent)), last.percent)
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
                    AXDataPoint(x: value.time.timeIntervalSince(now) / 3600, y: Double(value.percent))
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
        func resetAt(_ usage: ServiceUsage?) -> Date? {
            usage.flatMap { $0.windows.first?.resetDate(capturedAt: $0.capturedAt, capturedZone: $0.capturedZone) }
        }
        let point = UsageHistoryPoint(
            timestamp: timestamp,
            claudeSessionPercentLeft: claude?.windows.first?.percentLeft,
            codexFiveHourPercentLeft: codex?.windows.first?.percentLeft,
            claudeSessionResetAt: resetAt(claude),
            codexFiveHourResetAt: resetAt(codex)
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

    /// Start of the 5-hour window, five hours before its reset.
    var currentWindowStart: Date? {
        windows.first?
            .resetDate(capturedAt: capturedAt, capturedZone: capturedZone)?
            .addingTimeInterval(-HistoryWindow.sessionLength)
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

    func resetDate(capturedAt: Date, capturedZone: TimeZone) -> Date? {
        rawResets.flatMap { ResetTimeFormatter.instant($0, capturedAt: capturedAt, capturedZone: capturedZone) }
    }

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
    /// When the measured 5-hour window resets. Lets the chart place resets the Mac slept
    /// through; points saved before 1.0.11 have none.
    var claudeSessionResetAt: Date? = nil
    var codexFiveHourResetAt: Date? = nil

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
        guard let date = instant(raw, capturedAt: capturedAt, capturedZone: capturedZone) else {
            return cleaned(raw)
        }

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

    /// The reset as a fixed instant, in the zone the text names or else the capture zone.
    static func instant(_ raw: String, capturedAt: Date, capturedZone: TimeZone) -> Date? {
        resetDate(cleaned(raw), capturedAt: capturedAt, zone: namedZone(in: raw) ?? capturedZone)
    }

    private static func cleaned(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\([^)]*\)"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
