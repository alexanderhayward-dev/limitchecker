import Darwin
import Foundation

@_silgen_name("fork")
private func systemFork() -> pid_t

struct LimitWindow: Codable {
    let name: String
    let percentUsed: Int
    let percentLeft: Int
    let resets: String

    enum CodingKeys: String, CodingKey {
        case name
        case percentUsed = "percent_used"
        case percentLeft = "percent_left"
        case resets
    }
}

struct ServiceUsage: Codable {
    let service: String
    let ok: Bool
    let windows: [LimitWindow]
    let error: String?
    let rawExcerpt: String?

    enum CodingKeys: String, CodingKey {
        case service, ok, windows, error
        case rawExcerpt = "raw_excerpt"
    }

    static func failure(service: String, error: String, raw: String? = nil) -> ServiceUsage {
        ServiceUsage(service: service, ok: false, windows: [], error: error, rawExcerpt: raw)
    }
}

struct ProbePayload: Codable {
    let generatedAt: String
    let results: [ServiceUsage]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case results
    }
}

enum Terminal {
    static func clean(_ data: Data) -> String {
        let scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var result = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.value == 0x1B {
                index += 1
                guard index < scalars.count else { break }
                let kind = scalars[index].value
                index += 1
                if kind == 0x5B { // CSI
                    while index < scalars.count {
                        let value = scalars[index].value
                        index += 1
                        if (0x40...0x7E).contains(value) { break }
                    }
                } else if kind == 0x5D { // OSC
                    while index < scalars.count {
                        if scalars[index].value == 0x07 {
                            index += 1
                            break
                        }
                        if scalars[index].value == 0x1B,
                           index + 1 < scalars.count,
                           scalars[index + 1].value == 0x5C {
                            index += 2
                            break
                        }
                        index += 1
                    }
                } else if [0x50, 0x58, 0x5E, 0x5F].contains(kind) { // DCS, SOS, PM, APC
                    while index + 1 < scalars.count {
                        if scalars[index].value == 0x1B, scalars[index + 1].value == 0x5C {
                            index += 2
                            break
                        }
                        index += 1
                    }
                }
                continue
            }
            if scalar.value >= 0x20 || scalar.value == 0x0A {
                result.append(scalar)
            } else if scalar.value == 0x0D {
                result.append("\n")
            }
            index += 1
        }
        let text = String(result)
        return text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
    }

    static func compact(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression).lowercased()
    }

    static func collapsed(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum UsageFailure {
    static func authenticationMessage(service: String, output: String) -> String? {
        let compact = Terminal.compact(output)
        let indicators = [
            "notloggedin", "loginrequired", "pleaselogin", "signintocontinue",
            "authenticationrequired", "runclaudelogin", "runcodexlogin",
        ]
        guard indicators.contains(where: { compact.contains($0) }) else { return nil }
        return "\(service) ist nicht angemeldet. Öffne \(service) im Terminal und melde dich an."
    }

    static func unrecognizedDataMessage(service: String, command: String, output: String) -> String {
        authenticationMessage(service: service, output: output)
            ?? "\(service) hat keine erkennbaren Nutzungsdaten geliefert. Prüfe \(command) im Terminal."
    }

    static func unresponsiveMessage(service: String, command: String, output: String, ended: Bool) -> String {
        authenticationMessage(service: service, output: output)
            ?? (ended
                ? "\(service) wurde beendet, bevor Nutzungsdaten geladen werden konnten. Prüfe \(command) im Terminal."
                : "\(service) hat nicht rechtzeitig reagiert. Prüfe \(command) im Terminal.")
    }
}

struct DialogHandler {
    let prompt: String
    let response: [[UInt8]]
}

#if false
enum PtyRunner {
    static func run(
        command: [String],
        slashCommand: String,
        readyPrompt: String,
        dialogs: [DialogHandler],
        timeout: TimeInterval = 28
    ) throws -> String {
        let workingDirectory = try probeDirectory()
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: 42, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            throw ProbeError.message("Pseudo-Terminal konnte nicht erstellt werden.")
        }
        let pid = systemFork()
        guard pid >= 0 else { throw ProbeError.message("Pseudo-Terminal konnte nicht erstellt werden.") }

        if pid == 0 {
            close(master)
            _ = setsid()
            _ = ioctl(slave, TIOCSCTTY, 0)
            _ = dup2(slave, STDIN_FILENO)
            _ = dup2(slave, STDOUT_FILENO)
            _ = dup2(slave, STDERR_FILENO)
            if slave > STDERR_FILENO { close(slave) }
            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)
            setenv("NO_COLOR", "", 1)
            _ = chdir(workingDirectory.path)

            var argv = command.map { strdup($0) }
            argv.append(nil)
            argv.withUnsafeMutableBufferPointer { buffer in
                execvp(buffer[0]!, buffer.baseAddress)
            }
            _exit(127)
        }

        close(slave)

        let flags = fcntl(master, F_GETFL)
        _ = fcntl(master, F_SETFL, flags | O_NONBLOCK)
        defer {
            send("\u{001B}/exit\r", to: master)
            terminateProcessGroup(pid)
            var status: Int32 = 0
            let deadline = Date.now.addingTimeInterval(1)
            while Date.now < deadline && waitpid(pid, &status, WNOHANG) == 0 {
                usleep(50_000)
            }
            if waitpid(pid, &status, WNOHANG) == 0 {
                _ = kill(-pid, SIGKILL)
                _ = kill(pid, SIGKILL)
                _ = waitpid(pid, &status, 0)
            }
            close(master)
        }

        var plainOutput = ""
        var sentCommand = false
        var readyAt: Date?
        var activeDialog: (prompt: String, seenAt: Date)?
        var handledDialogs = Set<String>()
        let startedAt = Date.now
        var lastDataAt = startedAt

        while Date.now.timeIntervalSince(startedAt) < timeout {
            var buffer = [UInt8](repeating: 0, count: 65_536)
            let count = buffer.withUnsafeMutableBufferPointer { pointer in
                Darwin.read(master, pointer.baseAddress, pointer.count)
            }
            if count > 0 {
                let chunk = Data(buffer.prefix(Int(count)))
                plainOutput.append(Terminal.clean(chunk))
                if plainOutput.utf8.count > 256_000 {
                    plainOutput = String(plainOutput.suffix(128_000))
                }
                lastDataAt = .now
            }

            let plain = plainOutput
            let compact = Terminal.compact(plain)
            if let dialog = dialogs.first(where: {
                !handledDialogs.contains($0.prompt) && compact.contains(Terminal.compact($0.prompt))
            }) {
                if activeDialog?.prompt != dialog.prompt {
                    activeDialog = (dialog.prompt, .now)
                } else if let seenAt = activeDialog?.seenAt, Date.now.timeIntervalSince(seenAt) >= 0.8 {
                    for response in dialog.response {
                        send(response, to: master)
                        usleep(800_000)
                    }
                    handledDialogs.insert(dialog.prompt)
                    activeDialog = nil
                    readyAt = nil
                }
            } else if !sentCommand && plain.contains(readyPrompt) {
                if readyAt == nil {
                    readyAt = .now
                } else if let readyAt, Date.now.timeIntervalSince(readyAt) >= 2 {
                    send(slashCommand, to: master)
                    usleep(800_000)
                    send("\r", to: master)
                    sentCommand = true
                }
            }

            if sentCommand && Date.now.timeIntervalSince(lastDataAt) > 8 {
                break
            }
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                break
            }
            usleep(100_000)
        }
        return plainOutput
    }

    private static func probeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("LimitChecker/ProbeContext", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func send(_ text: String, to fd: Int32) {
        send(Array(text.utf8), to: fd)
    }

    private static func send(_ bytes: [UInt8], to fd: Int32) {
        bytes.withUnsafeBytes { pointer in
            _ = Darwin.write(fd, pointer.baseAddress, pointer.count)
        }
    }

    private static func terminateProcessGroup(_ pid: pid_t) {
        if kill(-pid, SIGTERM) != 0 {
            _ = kill(pid, SIGTERM)
        }
    }
}

#endif

enum ProbeError: Error {
    case message(String)
}

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var chunks: [Data] = []

    func append(_ data: Data) {
        lock.lock()
        chunks.append(data)
        lock.unlock()
    }

    func take() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        let captured = chunks
        chunks.removeAll(keepingCapacity: true)
        return captured
    }
}

private final class ProbeResults: @unchecked Sendable {
    private let lock = NSLock()
    private var claudeResult: ServiceUsage?
    private var codexResult: ServiceUsage?

    func setClaude(_ result: ServiceUsage) {
        lock.lock()
        claudeResult = result
        lock.unlock()
    }

    func setCodex(_ result: ServiceUsage) {
        lock.lock()
        codexResult = result
        lock.unlock()
    }

    func values() -> [ServiceUsage] {
        lock.lock()
        defer { lock.unlock() }
        return [claudeResult!, codexResult!]
    }
}

enum ScriptRunner {
    static func run(
        service: String,
        command: [String],
        slashCommand: String,
        readyPrompt: String,
        dialogs: [DialogHandler],
        timeout: TimeInterval = 28,
        silenceTimeout: TimeInterval = 8
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        let commandLine = "stty rows 42 cols 120; exec " + command.map(shellQuote).joined(separator: " ")
        process.arguments = ["-q", "/dev/null", "/bin/sh", "-lc", commandLine]
        process.currentDirectoryURL = try probeDirectory()
        process.environment = ProcessInfo.processInfo.environment.merging([
            "TERM": "xterm-256color",
            "COLORTERM": "truecolor",
            "NO_COLOR": "",
        ], uniquingKeysWith: { _, new in new })

        let input = Pipe()
        let output = Pipe()
        let collector = OutputCollector()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { collector.append(data) }
        }

        try process.run()
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            input.fileHandleForWriting.closeFile()
            if process.isRunning {
                process.terminate()
                let deadline = Date.now.addingTimeInterval(1)
                while process.isRunning && Date.now < deadline { usleep(50_000) }
                if process.isRunning { _ = kill(process.processIdentifier, SIGKILL) }
            }
        }

        var plainOutput = ""
        var sentCommand = false
        var readyAt: Date?
        var activeDialog: (prompt: String, seenAt: Date)?
        var handledDialogs = Set<String>()
        let startedAt = Date.now
        var lastDataAt = startedAt

        func send(_ string: String) {
            input.fileHandleForWriting.write(Data(string.utf8))
        }

        while Date.now.timeIntervalSince(startedAt) < timeout {
            let chunks = collector.take()
            if !chunks.isEmpty {
                for chunk in chunks { plainOutput.append(Terminal.clean(chunk)) }
                if plainOutput.utf8.count > 256_000 {
                    plainOutput = String(plainOutput.suffix(128_000))
                }
                lastDataAt = .now
            }

            let compact = Terminal.compact(plainOutput)
            if let dialog = dialogs.first(where: {
                !handledDialogs.contains($0.prompt) && compact.contains(Terminal.compact($0.prompt))
            }) {
                if activeDialog?.prompt != dialog.prompt {
                    activeDialog = (dialog.prompt, .now)
                } else if let seenAt = activeDialog?.seenAt, Date.now.timeIntervalSince(seenAt) >= 0.8 {
                    for response in dialog.response {
                        input.fileHandleForWriting.write(Data(response))
                        usleep(800_000)
                    }
                    handledDialogs.insert(dialog.prompt)
                    activeDialog = nil
                    readyAt = nil
                }
            } else if !sentCommand && plainOutput.contains(readyPrompt) {
                if readyAt == nil {
                    readyAt = .now
                } else if let readyAt, Date.now.timeIntervalSince(readyAt) >= 2 {
                    send(slashCommand)
                    usleep(800_000)
                    send("\r")
                    sentCommand = true
                }
            }

            if sentCommand && Date.now.timeIntervalSince(lastDataAt) > silenceTimeout { break }
            if !process.isRunning { break }
            usleep(100_000)
        }
        for chunk in collector.take() { plainOutput.append(Terminal.clean(chunk)) }
        if !sentCommand {
            throw ProbeError.message(
                UsageFailure.unresponsiveMessage(
                    service: service,
                    command: slashCommand,
                    output: plainOutput,
                    ended: !process.isRunning
                )
            )
        }
        return plainOutput
    }

    private static func probeDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("LimitChecker/ProbeContext", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'") + "'"
    }
}

enum Executables {
    static func claude() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return find([
            "\(home)/.local/bin/claude",
            "\(home)/.local/share/claude/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ], named: "claude")
    }

    static func codex() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return find([
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ], named: "codex")
    }

    private static func find(_ candidates: [String], named name: String) -> String? {
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for entry in pathEntries {
            let candidate = "\(entry)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

enum Parsers {
    static func claude(_ text: String) -> ServiceUsage {
        let clean = Terminal.collapsed(text)
        var windows: [LimitWindow] = []
        if let match = firstMatch(
            #"(?s)Current session\s+.*?(\d{1,3})%\s*used\s+Resets\s+(.+?)(?=\nCurrent week|\nWhat's|\z)"#,
            in: clean
        ), let used = Int(match[1]) {
            let percentUsed = boundedPercentage(used)
            windows.append(LimitWindow(name: "Current session", percentUsed: percentUsed, percentLeft: 100 - percentUsed, resets: match[2]))
        }
        if let match = firstMatch(
            #"(?s)Current week(?: \(all models\))?\s+.*?(\d{1,3})%\s*used\s+Resets\s+(.+?)(?=\n\+|\nWhat's|\z)"#,
            in: clean
        ), let used = Int(match[1]) {
            let percentUsed = boundedPercentage(used)
            windows.append(LimitWindow(name: "Current week", percentUsed: percentUsed, percentLeft: 100 - percentUsed, resets: match[2]))
        }
        return windows.isEmpty
            ? .failure(
                service: "claude",
                error: UsageFailure.unrecognizedDataMessage(service: "Claude Code", command: "/usage", output: clean),
                raw: String(clean.suffix(2_000))
            )
            : ServiceUsage(service: "claude", ok: true, windows: windows, error: nil, rawExcerpt: nil)
    }

    static func codex(_ text: String) -> ServiceUsage {
        let clean = Terminal.collapsed(text)
        var windows: [LimitWindow] = []
        if let match = firstMatch(#"(?i)5h limit:\s+(?:\[[^\]]+\]\s+)?(\d{1,3})%\s+left\s+\(resets\s+([^)]+)\)"#, in: clean), let left = Int(match[1]) {
            let percentLeft = boundedPercentage(left)
            windows.append(LimitWindow(name: "5h limit", percentUsed: 100 - percentLeft, percentLeft: percentLeft, resets: match[2]))
        }
        if let match = firstMatch(#"(?i)Weekly limit:\s+(?:\[[^\]]+\]\s+)?(\d{1,3})%\s+left\s+\(resets\s+([^)]+)\)"#, in: clean), let left = Int(match[1]) {
            let percentLeft = boundedPercentage(left)
            windows.append(LimitWindow(name: "Weekly limit", percentUsed: 100 - percentLeft, percentLeft: percentLeft, resets: match[2]))
        }
        return windows.isEmpty
            ? .failure(
                service: "codex",
                error: UsageFailure.unrecognizedDataMessage(service: "Codex", command: "/status", output: clean),
                raw: String(clean.suffix(2_000))
            )
            : ServiceUsage(service: "codex", ok: true, windows: windows, error: nil, rawExcerpt: nil)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func boundedPercentage(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

func probeClaude() -> ServiceUsage {
    guard let executable = Executables.claude() else {
        return .failure(service: "claude", error: "Claude Code CLI wurde nicht gefunden. Installiere Claude Code und melde dich darin an.")
    }
    do {
        let text = try ScriptRunner.run(
            service: "Claude Code",
            command: [executable],
            slashCommand: "/usage",
            readyPrompt: "Claude Code",
            dialogs: [DialogHandler(prompt: "Quick safety check", response: [Array("\u{001B}[B".utf8), Array("\r".utf8)])],
            silenceTimeout: 8
        )
        return Parsers.claude(text)
    } catch ProbeError.message(let message) {
        return .failure(service: "claude", error: message)
    } catch {
        return .failure(service: "claude", error: "Claude Code konnte nicht gestartet werden: \(error)")
    }
}

func probeCodex() -> ServiceUsage {
    guard let executable = Executables.codex() else {
        return .failure(service: "codex", error: "Codex CLI wurde nicht gefunden. Installiere die ChatGPT-App oder Codex CLI und melde dich darin an.")
    }
    do {
        let text = try ScriptRunner.run(
            service: "Codex",
            command: [executable, "--no-alt-screen"],
            slashCommand: "/status",
            readyPrompt: "Ask Codex to do anything",
            dialogs: [
                DialogHandler(prompt: "Do you trust", response: [Array("\r".utf8)]),
                DialogHandler(prompt: "Hooks need review", response: [Array("\u{001B}[B".utf8), Array("\u{001B}[B".utf8), Array("\r".utf8)]),
            ]
        )
        return Parsers.codex(text)
    } catch ProbeError.message(let message) {
        return .failure(service: "codex", error: message)
    } catch {
        return .failure(service: "codex", error: "Codex konnte nicht gestartet werden: \(error)")
    }
}

func argumentValue(_ name: String) -> String? {
    let arguments = CommandLine.arguments
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func liveResults(for requestedService: String) -> [ServiceUsage] {
    switch requestedService {
    case "claude": return [probeClaude()]
    case "codex": return [probeCodex()]
    default:
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "local.limitchecker.probe", attributes: .concurrent)
        let collected = ProbeResults()
        group.enter()
        queue.async { collected.setClaude(probeClaude()); group.leave() }
        group.enter()
        queue.async { collected.setCodex(probeCodex()); group.leave() }
        group.wait()
        return collected.values()
    }
}

func writePayload(_ results: [ServiceUsage]) {
    let formatter = ISO8601DateFormatter()
    let payload = ProbePayload(generatedAt: formatter.string(from: .now), results: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try! encoder.encode(payload)
    FileHandle.standardOutput.write(data)
}

if let parseService = argumentValue("--parse-output") {
    let text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    switch parseService {
    case "claude": writePayload([Parsers.claude(text)])
    case "codex": writePayload([Parsers.codex(text)])
    default: writePayload([.failure(service: parseService, error: "Unbekannter Testdienst.")])
    }
} else {
    writePayload(liveResults(for: argumentValue("--service") ?? "all"))
}
