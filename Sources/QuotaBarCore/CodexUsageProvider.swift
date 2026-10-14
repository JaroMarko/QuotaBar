import Darwin
import Foundation

public struct CodexUsageProvider: UsageProvider {
    public let kind = ProviderKind.codex
    private let executable: URL?
    private let timeout: TimeInterval

    public init() {
        executable = ExecutableLocator.find("codex")
        timeout = 10
    }

    public init(executable: URL?, timeout: TimeInterval = 10) {
        self.executable = executable
        self.timeout = timeout
    }

    public func fetch() async throws -> UsageSnapshot {
        guard let executable else { throw ProviderError.executableMissing("Codex CLI") }
        let timeout = timeout

        return try await Task.detached(priority: .utility) {
            do {
                return try CodexRPCSession.fetch(executable: executable, timeout: timeout)
            } catch CodexRPCError.timedOut {
                throw ProviderError.timedOut("Codex")
            } catch CodexRPCError.closed {
                throw ProviderError.unavailable("Codex CLI stopped before returning limits. Check its version and login.")
            } catch CodexRPCError.invalidResponse {
                throw ProviderError.invalidResponse("Codex")
            }
        }.value
    }
}

private enum CodexRPCError: Error {
    case timedOut
    case closed
    case invalidResponse
}

private enum CodexRPCSession {
    static func fetch(executable: URL, timeout: TimeInterval) throws -> UsageSnapshot {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()

        process.executableURL = executable
        process.arguments = ["-s", "read-only", "-a", "never", "-c", "analytics.enabled=false", "app-server", "--stdio"]
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe

        try process.run()
        let errors = PipeCapture(errorPipe.fileHandleForReading)
        defer {
            try? inputPipe.fileHandleForWriting.close()
            ProcessRunner.terminate(process)
            _ = errors.finish()
        }

        let reader = JSONLineReader(handle: outputPipe.fileHandleForReading)
        try send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "QuotaBar", "version": "1.3.4"],
                "capabilities": ["experimentalApi": false]
            ]
        ], to: inputPipe.fileHandleForWriting)
        let initialized = try reader.readResponse(id: 1, timeout: timeout)
        guard initialized["error"] == nil else { throw CodexRPCError.invalidResponse }
        try send(["method": "initialized"], to: inputPipe.fileHandleForWriting)

        try send(
            ["id": 2, "method": "account/read", "params": ["refreshToken": false]],
            to: inputPipe.fileHandleForWriting
        )
        let accountResponse = try reader.readResponse(id: 2, timeout: timeout)

        try send(
            ["id": 3, "method": "account/rateLimits/read", "params": NSNull()],
            to: inputPipe.fileHandleForWriting
        )
        let rateResponse = try reader.readResponse(id: 3, timeout: timeout)

        if let error = rateResponse["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? ""
            if message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("auth") {
                throw ProviderError.notSignedIn("codex login")
            }
            throw ProviderError.unavailable("Codex usage is currently unavailable.")
        }

        guard let rateResult = rateResponse["result"] as? [String: Any] else {
            throw CodexRPCError.invalidResponse
        }
        guard accountResponse["error"] == nil else { throw ProviderError.notSignedIn("codex login") }
        let accountResult = accountResponse["result"] as? [String: Any]
        return try CodexUsageDecoder.decode(rateLimitResult: rateResult, accountResult: accountResult, now: Date())
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }
}

private final class JSONLineReader {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func readResponse(id: Int, timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            while let line = nextLine() {
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if (object["id"] as? NSNumber)?.intValue == id { return object }
            }

            let remaining = max(0, deadline.timeIntervalSinceNow)
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let milliseconds = Int32(min(remaining * 1_000, Double(Int32.max)))
            let status = Darwin.poll(&descriptor, 1, milliseconds)
            if status == 0 { throw CodexRPCError.timedOut }
            if status < 0 { throw CodexRPCError.closed }

            var bytes = [UInt8](repeating: 0, count: 65_536)
            let count = Darwin.read(handle.fileDescriptor, &bytes, bytes.count)
            if count < 0 && errno == EINTR { continue }
            if count <= 0 { throw CodexRPCError.closed }
            buffer.append(contentsOf: bytes.prefix(count))
            if buffer.count > 1_048_576 { throw CodexRPCError.invalidResponse }
        }
        throw CodexRPCError.timedOut
    }

    private func nextLine() -> Data? {
        guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = Data(buffer[..<newline])
        buffer.removeSubrange(...newline)
        return line
    }
}

public enum CodexUsageDecoder {
    public static func decodeRPCStream(_ data: Data, now: Date) throws -> UsageSnapshot {
        let lines = data.split(separator: 0x0A)
        var accountResult: [String: Any]?
        var rateLimitResult: [String: Any]?

        for line in lines {
            guard
                let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                let id = (object["id"] as? NSNumber)?.intValue,
                let result = object["result"] as? [String: Any]
            else { continue }

            if id == 2 { accountResult = result }
            if id == 3 { rateLimitResult = result }
        }

        guard let rateLimitResult else { throw ProviderError.invalidResponse("Codex") }
        return try decode(rateLimitResult: rateLimitResult, accountResult: accountResult, now: now)
    }

    public static func decode(
        rateLimitResult: [String: Any],
        accountResult: [String: Any]?,
        now: Date
    ) throws -> UsageSnapshot {
        guard let main = rateLimitResult["rateLimits"] as? [String: Any] else {
            throw ProviderError.invalidResponse("Codex")
        }

        var plan = ((accountResult?["account"] as? [String: Any])?["planType"] as? String)
            ?? (main["planType"] as? String)
        plan = plan.map(prettyPlan)

        var decodedWindows = windows(from: main, prefix: "codex", fallbackTitle: nil)
        if let additional = rateLimitResult["rateLimitsByLimitId"] as? [String: Any] {
            for key in additional.keys.sorted() {
                guard let snapshot = additional[key] as? [String: Any] else { continue }
                let limitID = (snapshot["limitId"] as? String) ?? key
                if limitID == (main["limitId"] as? String) { continue }
                let title = (snapshot["limitName"] as? String) ?? humanized(key)
                decodedWindows.append(contentsOf: windows(from: snapshot, prefix: "codex-\(key)", fallbackTitle: title))
            }
        }

        guard !decodedWindows.isEmpty else { throw ProviderError.invalidResponse("Codex") }
        let account = accountResult?["account"] as? [String: Any]
        return UsageSnapshot(provider: .codex, plan: plan, windows: decodedWindows, fetchedAt: now,
                             source: "Codex CLI RPC", account: account?["email"] as? String)
    }

    private static func windows(
        from snapshot: [String: Any],
        prefix: String,
        fallbackTitle: String?
    ) -> [UsageWindow] {
        var result: [UsageWindow] = []
        if let primary = snapshot["primary"] as? [String: Any],
           let window = makeWindow(primary, id: "\(prefix)-primary", fallbackTitle: fallbackTitle) {
            result.append(window)
        }
        if let secondary = snapshot["secondary"] as? [String: Any],
           let window = makeWindow(secondary, id: "\(prefix)-secondary", fallbackTitle: fallbackTitle) {
            result.append(window)
        }
        return result
    }

    private static func makeWindow(
        _ dictionary: [String: Any],
        id: String,
        fallbackTitle: String?
    ) -> UsageWindow? {
        guard let used = (dictionary["usedPercent"] as? NSNumber)?.doubleValue, used.isFinite else { return nil }
        let minutes = (dictionary["windowDurationMins"] as? NSNumber)?.intValue
        let resetSeconds = (dictionary["resetsAt"] as? NSNumber)?.doubleValue
        let baseName = windowName(minutes: minutes)
        let name = fallbackTitle.map { "\($0) · \(baseName)" } ?? baseName
        return UsageWindow(
            id: id,
            name: name,
            usedPercent: used,
            resetsAt: resetSeconds.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil },
            durationMinutes: minutes
        )
    }

    private static func windowName(minutes: Int?) -> String {
        guard let minutes else { return "Usage window" }
        if (240...360).contains(minutes) { return "5-hour session" }
        if (9_000...11_000).contains(minutes) { return "Weekly" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)-day" }
        if minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return "\(minutes)-minute"
    }

    private static func prettyPlan(_ value: String) -> String {
        value.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    private static func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalized
    }
}
