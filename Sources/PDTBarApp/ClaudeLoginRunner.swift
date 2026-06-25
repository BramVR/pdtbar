#if canImport(Darwin)
import Darwin
#endif
import Foundation

struct ClaudeLoginRunner {
    enum Phase {
        case requesting
        case waitingBrowser
    }

    struct Result {
        enum Outcome {
            case success
            case timedOut
            case failed(status: Int32)
            case missingBinary
            case launchFailed(String)
        }

        let outcome: Outcome
        let output: String
        let authLink: String?
    }

    static func run(
        timeout: TimeInterval = 120,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        onPhaseChange: @escaping @Sendable (Phase) -> Void
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.runBlocking(
                    timeout: timeout,
                    environment: environment,
                    onPhaseChange: onPhaseChange
                ))
            }
        }
    }

    private static func runBlocking(
        timeout: TimeInterval,
        environment: [String: String],
        onPhaseChange: @escaping @Sendable (Phase) -> Void
    ) -> Result {
        onPhaseChange(.requesting)
        do {
            let runResult = try self.runPTY(
                timeout: timeout,
                environment: environment,
                onPhaseChange: onPhaseChange
            )
            if runResult.exitStatus == 0 {
                return Result(
                    outcome: .success,
                    output: runResult.output,
                    authLink: self.firstLink(in: runResult.output)
                )
            }
            if let exitStatus = runResult.exitStatus {
                return Result(
                    outcome: .failed(status: exitStatus),
                    output: runResult.output,
                    authLink: self.firstLink(in: runResult.output)
                )
            }
            return Result(outcome: .timedOut, output: runResult.output, authLink: nil)
        } catch LoginError.binaryNotFound {
            return Result(outcome: .missingBinary, output: "", authLink: nil)
        } catch let LoginError.timedOut(text) {
            return Result(outcome: .timedOut, output: text, authLink: self.firstLink(in: text))
        } catch let LoginError.failed(status, text) {
            return Result(outcome: .failed(status: status), output: text, authLink: self.firstLink(in: text))
        } catch {
            return Result(outcome: .launchFailed(error.localizedDescription), output: "", authLink: nil)
        }
    }

    private enum LoginError: Error {
        case binaryNotFound
        case timedOut(text: String)
        case failed(status: Int32, text: String)
        case launchFailed(String)
    }

    private struct PTYRunResult {
        let output: String
        let exitStatus: Int32?
    }

    private static func runPTY(
        timeout: TimeInterval,
        environment: [String: String],
        onPhaseChange: @escaping @Sendable (Phase) -> Void
    ) throws -> PTYRunResult {
        let runner = TTYCommandRunner()
        let successSubstrings = ["Successfully logged in", "Login successful", "Logged in successfully"]
        var options = TTYCommandRunner.Options(
            rows: 50,
            cols: 160,
            timeout: timeout,
            baseEnvironment: environment
        )
        options.extraArgs = ["auth", "login"]
        options.stopOnURL = false
        options.sendOnSubstrings = Dictionary(uniqueKeysWithValues: successSubstrings.map { ($0, "\r") })
        options.sendEnterEvery = 1.0
        options.settleAfterStop = 0.35
        do {
            let result = try runner.run(
                binary: environment["PDTBAR_CLAUDE_BIN"]?.nilIfEmpty ?? "claude",
                send: "",
                options: options,
                onURLDetected: { onPhaseChange(.waitingBrowser) }
            )
            return PTYRunResult(
                output: result.text,
                exitStatus: result.terminationStatus
            )
        } catch TTYCommandRunner.Error.binaryNotFound {
            throw LoginError.binaryNotFound
        } catch TTYCommandRunner.Error.timedOut {
            throw LoginError.timedOut(text: "")
        } catch let TTYCommandRunner.Error.launchFailed(msg) {
            throw LoginError.launchFailed(msg)
        } catch {
            throw LoginError.launchFailed(error.localizedDescription)
        }
    }

    private static func firstLink(in text: String) -> String? {
        let pattern = #"https?://[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
              let range = Range(match.range, in: text) else { return nil }
        var url = String(text[range])
        while let last = url.unicodeScalars.last,
              CharacterSet(charactersIn: ".,;:)]}>\"'").contains(last)
        {
            url.unicodeScalars.removeLast()
        }
        return url
    }
}

private struct TTYProcessTreeTerminator {
    static func descendantPIDs(of rootPID: pid_t) -> [pid_t] {
        guard rootPID > 0 else { return [] }
        var seen: Set<pid_t> = [rootPID]
        var pending = currentChildPIDs(of: rootPID)
        var descendants: [pid_t] = []

        while let pid = pending.popLast() {
            guard pid > 0, seen.insert(pid).inserted else { continue }
            descendants.append(pid)
            pending.append(contentsOf: currentChildPIDs(of: pid))
        }

        return descendants
    }

    static func currentChildPIDs(of parentPID: pid_t) -> [pid_t] {
        guard parentPID > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: 128)
        let byteCount = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let childCount = proc_listchildpids(parentPID, &pids, byteCount)
        guard childCount > 0 else { return [] }
        return Array(pids.prefix(min(Int(childCount), pids.count))).filter { $0 > 0 }
    }

    static func terminateProcessTree(
        rootPID: pid_t,
        processGroup: pid_t?,
        signal: Int32,
        knownDescendants: [pid_t] = []
    ) {
        guard rootPID > 0 else { return }

        var seen: Set<pid_t> = [rootPID]
        let descendants = knownDescendants + self.descendantPIDs(of: rootPID)
        for pid in descendants where pid > 0 && seen.insert(pid).inserted {
            kill(pid, signal)
        }
        if let processGroup {
            kill(-processGroup, signal)
        }
        kill(rootPID, signal)
    }
}

private struct TTYCommandRunner {
    struct Result: Sendable {
        let text: String
        let terminationStatus: Int32?
    }

    struct Options: Sendable {
        var rows: UInt16 = 50
        var cols: UInt16 = 160
        var timeout: TimeInterval = 20.0
        var idleTimeout: TimeInterval?
        var workingDirectory: URL?
        var extraArgs: [String] = []
        var baseEnvironment: [String: String]?
        var initialDelay: TimeInterval = 0.4
        var sendEnterEvery: TimeInterval?
        var sendOnSubstrings: [String: String] = [:]
        var stopOnURL = false
        var stopOnSubstrings: [String] = []
        var settleAfterStop: TimeInterval = 0.25
    }

    enum Error: Swift.Error, LocalizedError, Sendable {
        case binaryNotFound(String)
        case launchFailed(String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case let .binaryNotFound(bin):
                "Missing CLI '\(bin)'. Install it or add it to PATH."
            case let .launchFailed(msg):
                "Failed to launch process: \(msg)"
            case .timedOut:
                "PTY command timed out."
            }
        }
    }

    private struct RollingBuffer {
        private let maxNeedle: Int
        private var tail = Data()

        init(maxNeedle: Int) {
            self.maxNeedle = max(0, maxNeedle)
        }

        mutating func append(_ data: Data) -> Data {
            guard !data.isEmpty else { return Data() }

            var combined = Data()
            combined.reserveCapacity(self.tail.count + data.count)
            combined.append(self.tail)
            combined.append(data)

            if self.maxNeedle > 1 {
                if combined.count >= self.maxNeedle - 1 {
                    self.tail = combined.suffix(self.maxNeedle - 1)
                } else {
                    self.tail = combined
                }
            } else {
                self.tail.removeAll(keepingCapacity: true)
            }

            return combined
        }
    }

    private enum DrainReadResult {
        case data(Data)
        case wouldBlock
        case closed
    }

    func run(
        binary: String,
        send script: String,
        options: Options = Options(),
        onURLDetected: (@Sendable () -> Void)? = nil
    ) throws -> Result {
        let resolved: String
        if binary.contains("/"), FileManager.default.isExecutableFile(atPath: binary) {
            resolved = binary
        } else if let hit = Self.which(binary, environment: options.baseEnvironment ?? ProcessInfo.processInfo.environment) {
            resolved = hit
        } else {
            throw Error.binaryNotFound(binary)
        }

        var primaryFD: Int32 = -1
        var secondaryFD: Int32 = -1
        var win = winsize(ws_row: options.rows, ws_col: options.cols, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&primaryFD, &secondaryFD, nil, nil, &win) == 0 else {
            throw Error.launchFailed("openpty failed")
        }
        _ = fcntl(primaryFD, F_SETFL, O_NONBLOCK)

        let primaryHandle = FileHandle(fileDescriptor: primaryFD, closeOnDealloc: true)
        let secondaryHandle = FileHandle(fileDescriptor: secondaryFD, closeOnDealloc: true)

        func writeAllToPrimary(_ data: Data) throws {
            try data.withUnsafeBytes { rawBytes in
                guard let baseAddress = rawBytes.baseAddress else { return }
                var offset = 0
                var retries = 0
                while offset < rawBytes.count {
                    let written = write(primaryFD, baseAddress.advanced(by: offset), rawBytes.count - offset)
                    if written > 0 {
                        offset += written
                        retries = 0
                        continue
                    }
                    if written == 0 { break }

                    let err = errno
                    if err == EAGAIN || err == EWOULDBLOCK {
                        retries += 1
                        if retries > 200 {
                            throw Error.launchFailed("write to PTY would block")
                        }
                        usleep(5000)
                        continue
                    }
                    throw Error.launchFailed("write to PTY failed: \(String(cString: strerror(err)))")
                }
            }
        }

        let baseEnv = options.baseEnvironment ?? ProcessInfo.processInfo.environment
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: resolved)
        proc.arguments = options.extraArgs
        proc.standardInput = secondaryHandle
        proc.standardOutput = secondaryHandle
        proc.standardError = secondaryHandle
        var env = Self.enrichedEnvironment(baseEnv: baseEnv, home: baseEnv["HOME"] ?? NSHomeDirectory())
        if let workingDirectory = options.workingDirectory {
            proc.currentDirectoryURL = workingDirectory
            env["PWD"] = workingDirectory.path
        }
        proc.environment = env

        var cleanedUp = false
        var didLaunch = false
        var processGroup: pid_t?
        func cleanup() {
            guard !cleanedUp else { return }

            if didLaunch, proc.isRunning {
                let exitData = Data("/exit\n".utf8)
                try? writeAllToPrimary(exitData)
            }

            try? primaryHandle.close()
            try? secondaryHandle.close()

            guard didLaunch else {
                cleanedUp = true
                return
            }

            let descendants = TTYProcessTreeTerminator.descendantPIDs(of: proc.processIdentifier)
            if proc.isRunning {
                proc.terminate()
            }
            TTYProcessTreeTerminator.terminateProcessTree(
                rootPID: proc.processIdentifier,
                processGroup: processGroup,
                signal: SIGTERM,
                knownDescendants: descendants
            )
            let waitDeadline = Date().addingTimeInterval(2.0)
            while proc.isRunning, Date() < waitDeadline {
                usleep(100_000)
            }
            if proc.isRunning {
                TTYProcessTreeTerminator.terminateProcessTree(
                    rootPID: proc.processIdentifier,
                    processGroup: processGroup,
                    signal: SIGKILL,
                    knownDescendants: descendants
                )
            } else {
                for pid in descendants where pid > 0 {
                    kill(pid, SIGKILL)
                }
            }
            if didLaunch {
                proc.waitUntilExit()
            }

            cleanedUp = true
        }

        defer { cleanup() }

        do {
            try proc.run()
            didLaunch = true
        } catch {
            throw Error.launchFailed(error.localizedDescription)
        }

        let pid = proc.processIdentifier
        if setpgid(pid, pid) == 0 {
            processGroup = pid
        }

        func send(_ text: String) throws {
            guard let data = text.data(using: .utf8) else { return }
            try writeAllToPrimary(data)
        }

        let deadline = Date().addingTimeInterval(options.timeout)
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)

        var buffer = Data()
        func readChunkResult() -> (data: Data, terminalRead: Int, errno: Int32) {
            var appended = Data()
            var terminalRead = 0
            var terminalErrno: Int32 = 0
            while true {
                var tmp = [UInt8](repeating: 0, count: 8192)
                errno = 0
                let n = read(primaryFD, &tmp, tmp.count)
                if n > 0 {
                    let slice = tmp.prefix(n)
                    buffer.append(contentsOf: slice)
                    appended.append(contentsOf: slice)
                    continue
                }
                terminalRead = Int(n)
                terminalErrno = errno
                break
            }
            return (appended, terminalRead, terminalErrno)
        }

        func readChunk() -> Data {
            readChunkResult().data
        }

        func readDrainChunk() -> DrainReadResult {
            let result = readChunkResult()
            return Self.drainReadResult(for: result.data, terminalRead: result.terminalRead, errno: result.errno)
        }

        let cursorQuery = Data([0x1B, 0x5B, 0x36, 0x6E])

        usleep(UInt32(options.initialDelay * 1_000_000))

        if !trimmed.isEmpty {
            try send(trimmed)
            try send("\r")
        }

        let stopNeedles = options.stopOnSubstrings.map { Data($0.utf8) }
        let sendNeedles = options.sendOnSubstrings.map {
            (needle: Data($0.key.utf8), needleString: $0.key, keys: Data($0.value.utf8))
        }
        let urlNeedles = [Data("https://".utf8), Data("http://".utf8)]
        let needleLengths =
            stopNeedles.map(\.count) +
            sendNeedles.map(\.needle.count) +
            urlNeedles.map(\.count) +
            [cursorQuery.count]
        let maxNeedle = needleLengths.max() ?? cursorQuery.count
        var scanBuffer = RollingBuffer(maxNeedle: maxNeedle)
        var nextCursorCheckAt = Date(timeIntervalSince1970: 0)
        var lastEnter = Date()
        var stoppedEarly = false
        var urlSeen = false
        var triggeredSends = Set<Data>()
        var recentText = ""
        var lastOutputAt = Date()

        func processChunk(_ newData: Data, allowSends: Bool, allowStop: Bool) -> Bool {
            guard !newData.isEmpty else { return false }

            lastOutputAt = Date()
            if let chunkText = String(bytes: newData, encoding: .utf8) {
                recentText += chunkText
                if recentText.count > 8192 {
                    recentText.removeFirst(recentText.count - 8192)
                }
            }

            let scanData = scanBuffer.append(newData)
            if Date() >= nextCursorCheckAt,
               scanData.range(of: cursorQuery) != nil
            {
                try? send("\u{1b}[1;1R")
                nextCursorCheckAt = Date().addingTimeInterval(1.0)
            }

            if allowSends, !sendNeedles.isEmpty {
                let recentTextCollapsed = recentText.replacingOccurrences(of: "\r", with: "")
                for item in sendNeedles where !triggeredSends.contains(item.needle) {
                    let matched = scanData.range(of: item.needle) != nil ||
                        recentText.contains(item.needleString) ||
                        recentTextCollapsed.contains(item.needleString)
                    if matched {
                        if let keysString = String(data: item.keys, encoding: .utf8) {
                            try? send(keysString)
                        } else {
                            try? writeAllToPrimary(item.keys)
                        }
                        triggeredSends.insert(item.needle)
                    }
                }
            }

            if urlNeedles.contains(where: { scanData.range(of: $0) != nil }) {
                if !urlSeen {
                    urlSeen = true
                    onURLDetected?()
                    try? send("\r")
                    lastEnter = Date()
                }
                if allowStop, options.stopOnURL {
                    return true
                }
            }

            if allowStop, !stopNeedles.isEmpty, stopNeedles.contains(where: { scanData.range(of: $0) != nil }) {
                return true
            }

            return false
        }

        while Date() < deadline {
            let readResult = readDrainChunk()
            let newData = switch readResult {
            case let .data(data):
                data
            case .wouldBlock, .closed:
                Data()
            }
            if processChunk(newData, allowSends: true, allowStop: true) {
                stoppedEarly = true
                break
            }
            if let idleTimeout = options.idleTimeout,
               !buffer.isEmpty,
               Date().timeIntervalSince(lastOutputAt) >= idleTimeout
            {
                stoppedEarly = true
                break
            }

            if !urlSeen, let every = options.sendEnterEvery, Date().timeIntervalSince(lastEnter) >= every {
                try? send("\r")
                lastEnter = Date()
            }

            if case .closed = readResult, !proc.isRunning { break }
            if !proc.isRunning { break }
            usleep(60000)
        }

        if stoppedEarly {
            let settle = max(0, min(options.settleAfterStop, deadline.timeIntervalSinceNow))
            if settle > 0 {
                let settleDeadline = Date().addingTimeInterval(settle)
                while Date() < settleDeadline {
                    let newData = readChunk()
                    let scanData = scanBuffer.append(newData)
                    if Date() >= nextCursorCheckAt,
                       !scanData.isEmpty,
                       scanData.range(of: cursorQuery) != nil
                    {
                        try? send("\u{1b}[1;1R")
                        nextCursorCheckAt = Date().addingTimeInterval(1.0)
                    }
                    usleep(50000)
                }
            }
        } else if !proc.isRunning {
            let drainFor = max(0, min(0.2, deadline.timeIntervalSinceNow))
            if drainFor > 0 {
                Self.drainRemainingOutput(
                    until: Date().addingTimeInterval(drainFor),
                    readChunk: readDrainChunk,
                    processChunk: { _ = processChunk($0, allowSends: false, allowStop: false) }
                )
            }
        }

        let terminationStatus = proc.isRunning ? nil : proc.terminationStatus
        let text = String(data: buffer, encoding: .utf8) ?? ""
        if text.isEmpty, let terminationStatus {
            return Result(text: text, terminationStatus: terminationStatus)
        }
        guard !text.isEmpty else { throw Error.timedOut }
        return Result(text: text, terminationStatus: terminationStatus)
    }

    private static func drainRemainingOutput(
        until drainDeadline: Date,
        readChunk: () -> DrainReadResult,
        processChunk: (Data) -> Void
    ) {
        while Date() < drainDeadline {
            switch readChunk() {
            case let .data(newData):
                processChunk(newData)
            case .wouldBlock:
                usleep(20000)
            case .closed:
                return
            }
        }
    }

    private static func drainReadResult(for data: Data, terminalRead: Int, errno err: Int32) -> DrainReadResult {
        if !data.isEmpty { return .data(data) }

        if terminalRead == 0 {
            return .closed
        }

        if terminalRead < 0 {
            if err == EAGAIN || err == EWOULDBLOCK || err == EINTR {
                return .wouldBlock
            }
            if err == EIO {
                return .closed
            }
        }

        return .closed
    }

    private static func enrichedEnvironment(
        baseEnv: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        var env = baseEnv
        env["PATH"] = executableSearchDirectories(environment: baseEnv).joined(separator: ":")
        if env["HOME"]?.isEmpty ?? true {
            env["HOME"] = home
        }
        if env["TERM"]?.isEmpty ?? true {
            env["TERM"] = "xterm-256color"
        }
        if env["COLORTERM"]?.isEmpty ?? true {
            env["COLORTERM"] = "truecolor"
        }
        if env["LANG"]?.isEmpty ?? true {
            env["LANG"] = "en_US.UTF-8"
        }
        return env
    }

    private static func which(_ executable: String, environment: [String: String]) -> String? {
        if executable.contains("/") {
            return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
        }
        for directory in executableSearchDirectories(environment: environment) {
            let candidate = "\(directory)/\(executable)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func executableSearchDirectories(environment: [String: String]) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let defaults = [
            "\(home)/.local/bin",
            "\(home)/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let pathDirectories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return (pathDirectories + defaults).filter { directory in
            seen.insert(directory).inserted
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        self.isEmpty ? nil : self
    }
}
