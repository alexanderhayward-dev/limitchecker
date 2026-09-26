import CryptoKit
import Foundation

enum InstallPhase: Equatable {
    case idle
    case downloading
    case verifying
    case installing
    case failed(String)

    var label: String? {
        switch self {
        case .idle: return nil
        case .downloading: return "Lade herunter …"
        case .verifying: return "Prüfe Download …"
        case .installing: return "Installiere …"
        case let .failed(message): return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing: return true
        case .idle, .failed: return false
        }
    }

    var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }
}

enum InstallError: LocalizedError {
    case noArchive
    case noChecksum
    case notWritable(String)
    case downloadFailed(String)
    case digestMismatch
    case unreadableChecksum
    case extractionFailed(String)
    case unexpectedPayload(String)
    case handoffFailed(String)

    var errorDescription: String? {
        switch self {
        case .noArchive:
            return "Das Release enthält kein ZIP-Archiv."
        case .noChecksum:
            return "Das Release enthält keine Prüfsumme. Bitte manuell herunterladen."
        case let .notWritable(path):
            return "Keine Schreibrechte für \(path). Bitte manuell installieren."
        case let .downloadFailed(detail):
            return "Download fehlgeschlagen: \(detail)"
        case .digestMismatch:
            return "Prüfsumme stimmt nicht. Installation abgebrochen."
        case .unreadableChecksum:
            return "Prüfsummen-Datei ist unlesbar. Installation abgebrochen."
        case let .extractionFailed(detail):
            return "Entpacken fehlgeschlagen: \(detail)"
        case let .unexpectedPayload(detail):
            return "Unerwarteter Inhalt im Archiv: \(detail)"
        case let .handoffFailed(detail):
            return "Austausch konnte nicht gestartet werden: \(detail)"
        }
    }
}

/// Downloads a release, verifies it, and hands the bundle swap to a detached
/// helper script — a running app cannot replace its own bundle while it holds it.
enum UpdateInstaller {
    private static let session = URLSession(configuration: .ephemeral)

    /// Returns once the helper is running; the caller then terminates the app.
    static func install(
        release: AppRelease,
        phase: @MainActor @escaping (InstallPhase) -> Void
    ) async throws {
        guard let archive = release.archive else { throw InstallError.noArchive }
        guard let checksumURL = archive.checksumURL else { throw InstallError.noChecksum }

        let target = Bundle.main.bundleURL
        try verifyWritable(target)

        let staging = try makeStagingDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }

        await phase(.downloading)
        let downloaded = try await download(archive.downloadURL, into: staging, named: archive.name)

        await phase(.verifying)
        let expected = try await expectedDigest(from: checksumURL)
        guard try digest(of: downloaded) == expected else { throw InstallError.digestMismatch }

        await phase(.installing)
        let unpacked = staging.appendingPathComponent("unpacked", isDirectory: true)
        try run("/usr/bin/ditto", ["-x", "-k", downloaded.path, unpacked.path], as: InstallError.extractionFailed)
        let newBundle = try locateBundle(in: unpacked, expecting: release.version)
        try run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newBundle.path], as: InstallError.extractionFailed)

        // The helper outlives us, so it must own a copy that our defer cannot delete.
        let handoff = try makeStagingDirectory()
        let staged = handoff.appendingPathComponent(newBundle.lastPathComponent)
        try FileManager.default.moveItem(at: newBundle, to: staged)
        try startHandoff(newBundle: staged, target: target, workingDirectory: handoff)
    }

    private static func verifyWritable(_ bundle: URL) throws {
        let manager = FileManager.default
        let parent = bundle.deletingLastPathComponent()
        guard manager.isWritableFile(atPath: parent.path), manager.isWritableFile(atPath: bundle.path) else {
            throw InstallError.notWritable(parent.path)
        }
    }

    private static func makeStagingDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LimitCheckerUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func download(_ url: URL, into directory: URL, named name: String) async throws -> URL {
        do {
            let (temporary, response) = try await session.download(from: url)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw InstallError.downloadFailed("Status \(http.statusCode)")
            }
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.moveItem(at: temporary, to: destination)
            return destination
        } catch let error as InstallError {
            throw error
        } catch {
            throw InstallError.downloadFailed(error.localizedDescription)
        }
    }

    private static func expectedDigest(from url: URL) async throws -> String {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.unreadableChecksum
        }
        guard let text = String(data: data, encoding: .utf8),
              let field = text.split(whereSeparator: \.isWhitespace).first,
              field.count == 64,
              field.allSatisfy(\.isHexDigit)
        else {
            throw InstallError.unreadableChecksum
        }
        return field.lowercased()
    }

    private static func digest(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func locateBundle(in directory: URL, expecting version: SemanticVersion) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        guard let candidate = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.unexpectedPayload("keine App gefunden")
        }
        guard let bundle = Bundle(url: candidate) else {
            throw InstallError.unexpectedPayload("Bundle nicht lesbar")
        }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw InstallError.unexpectedPayload("fremde Bundle-ID \(bundle.bundleIdentifier ?? "?")")
        }
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let shipped = raw.flatMap(SemanticVersion.init), shipped == version else {
            throw InstallError.unexpectedPayload("Version \(raw ?? "?") statt \(version)")
        }
        // Catches a truncated or tampered bundle even under ad-hoc signing.
        try run("/usr/bin/codesign", ["--verify", "--strict", candidate.path], as: InstallError.unexpectedPayload)
        return candidate
    }

    private static func run(
        _ launchPath: String,
        _ arguments: [String],
        as wrap: (String) -> InstallError
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw wrap(error.localizedDescription)
        }
        let detail = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            throw wrap(trimmed.isEmpty ? "Status \(process.terminationStatus)" : trimmed)
        }
    }

    /// Waits for this process to exit, then swaps the bundle and relaunches.
    /// Restores the previous bundle if the copy fails, so a broken download can
    /// never leave the user without an app.
    private static func startHandoff(newBundle: URL, target: URL, workingDirectory: URL) throws {
        let script = workingDirectory.appendingPathComponent("install.sh")
        let backup = "\(target.path).backup-\(UUID().uuidString)"
        let contents = """
        #!/bin/sh
        set -u
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do
          sleep 0.2
        done
        if ! /bin/mv "\(target.path)" "\(backup)"; then
          exit 1
        fi
        if /usr/bin/ditto "\(newBundle.path)" "\(target.path)"; then
          /bin/rm -rf "\(backup)"
        else
          /bin/rm -rf "\(target.path)"
          /bin/mv "\(backup)" "\(target.path)"
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "\(target.path)" 2>/dev/null
        /usr/bin/open "\(target.path)"
        /bin/rm -rf "\(workingDirectory.path)"
        """
        do {
            try contents.write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path]
            try process.run()
        } catch {
            throw InstallError.handoffFailed(error.localizedDescription)
        }
    }
}
