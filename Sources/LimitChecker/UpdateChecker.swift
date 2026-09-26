import Foundation
import SwiftUI

struct SemanticVersion: Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.first == "v" || text.first == "V" {
            text.removeFirst()
        }
        guard let core = text.split(whereSeparator: { $0 == "-" || $0 == "+" }).first else { return nil }
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            numbers.append(value)
        }
        major = numbers[0]
        minor = numbers.count > 1 ? numbers[1] : 0
        patch = numbers.count > 2 ? numbers[2] : 0
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

struct ReleaseArchive: Equatable {
    let name: String
    let downloadURL: URL
    let checksumURL: URL?
}

struct AppRelease: Equatable {
    let version: SemanticVersion
    let tag: String
    let pageURL: URL
    let archive: ReleaseArchive?

    static func == (lhs: AppRelease, rhs: AppRelease) -> Bool {
        lhs.tag == rhs.tag && lhs.archive == rhs.archive
    }
}

enum AppVersion {
    static var current: SemanticVersion? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            return nil
        }
        return SemanticVersion(raw)
    }

    /// False for `swift run` builds, which carry the placeholder version from `App/Info.plist`
    /// and would otherwise report every published release as an update.
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}

enum UpdateError: LocalizedError {
    case unreachable(String)

    var errorDescription: String? {
        switch self {
        case let .unreachable(detail): return detail
        }
    }
}

@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var availableRelease: AppRelease?
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckError: String?
    @Published var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecksEnabled, forKey: Keys.automaticChecks)
            if automaticChecksEnabled && !oldValue {
                checkNow()
            }
        }
    }

    private enum Keys {
        static let automaticChecks = "UpdatesAutomaticChecksEnabled"
        static let lastCheck = "UpdatesLastCheckDate"
    }

    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private var lastCheckedAt: Date?
    private var pollTask: Task<Void, Never>?
    private var didStart = false

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Keys.automaticChecks) == nil {
            automaticChecksEnabled = true
        } else {
            automaticChecksEnabled = defaults.bool(forKey: Keys.automaticChecks)
        }
        lastCheckedAt = defaults.object(forKey: Keys.lastCheck) as? Date
    }

    deinit {
        pollTask?.cancel()
    }

    var currentVersionText: String {
        AppVersion.current?.description ?? "unbekannt"
    }

    var lastCheckText: String? {
        guard let lastCheckedAt else { return nil }
        return "Zuletzt geprüft: \(lastCheckedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    func start() {
        guard !didStart, AppVersion.isBundledApp else { return }
        didStart = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func checkNow() {
        Task { await check() }
    }

    func openReleasePage() {
        let url = availableRelease?.pageURL ?? UpdateFeed.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    private func checkIfDue() async {
        guard automaticChecksEnabled else { return }
        if let lastCheckedAt, Date.now.timeIntervalSince(lastCheckedAt) < Self.checkInterval {
            return
        }
        await check()
    }

    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await UpdateFeed.latestRelease()
            lastCheckedAt = .now
            UserDefaults.standard.set(lastCheckedAt, forKey: Keys.lastCheck)
            lastCheckError = nil

            guard let current = AppVersion.current else {
                availableRelease = nil
                return
            }
            availableRelease = release.version > current ? release : nil
        } catch {
            lastCheckError = error.localizedDescription
        }
    }
}

enum UpdateFeed {
    static let repository = "alexanderhayward-dev/limitchecker"

    static var releasesPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    private static let session = URLSession(configuration: .ephemeral)

    static func latestRelease() async throws -> AppRelease {
        let endpoint = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("LimitChecker/\(AppVersion.current?.description ?? "dev")", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateError.unreachable("GitHub hat unerwartet geantwortet.")
        }
        guard http.statusCode == 200 else {
            throw UpdateError.unreachable("GitHub antwortete mit Status \(http.statusCode).")
        }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let version = SemanticVersion(payload.tagName) else {
            throw UpdateError.unreachable("Unlesbare Versionsangabe \"\(payload.tagName)\".")
        }
        return AppRelease(
            version: version,
            tag: payload.tagName,
            pageURL: payload.htmlURL,
            archive: archive(in: payload.assets)
        )
    }

    private static func archive(in assets: [GitHubRelease.Asset]) -> ReleaseArchive? {
        guard let zip = assets.first(where: { $0.name.hasSuffix("-macos-universal.zip") }) else {
            return nil
        }
        let checksum = assets.first(where: { $0.name == "\(zip.name).sha256" })
        return ReleaseArchive(
            name: zip.name,
            downloadURL: zip.browserDownloadURL,
            checksumURL: checksum?.browserDownloadURL
        )
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
}

struct UpdateBanner: View {
    @ObservedObject var store: UpdateStore

    var body: some View {
        if let release = store.availableRelease {
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Version \(release.version.description) verfügbar")
                        .font(.subheadline.weight(.semibold))
                    Text("Installiert: \(store.currentVersionText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Aktualisieren") {
                    store.openReleasePage()
                }
                .controlSize(.small)
            }
        }
    }
}

struct UpdateMenu: View {
    @ObservedObject var store: UpdateStore

    var body: some View {
        Menu {
            Button("Jetzt nach Updates suchen") {
                store.checkNow()
            }
            .disabled(store.isChecking)
            Toggle("Automatisch nach Updates suchen", isOn: $store.automaticChecksEnabled)
            if let lastCheckText = store.lastCheckText {
                Divider()
                Text(lastCheckText)
            }
            if let error = store.lastCheckError {
                Text("Update-Suche fehlgeschlagen: \(error)")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Updates")
    }
}
