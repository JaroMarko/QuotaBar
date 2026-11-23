import Foundation
import CryptoKit

public struct GeminiAntigravityUsageProvider: UsageProvider {
    public let kind = ProviderKind.gemini
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        guard let cli = ExecutableLocator.find("agy") else { throw ProviderError.executableMissing("agy") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuotaBar-agy-workspace")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw ProviderError.unavailable("Antigravity quota workspace must be empty.")
        }
        guard let helper = Bundle.main.url(forResource: "agy-quota", withExtension: "exp") ?? Bundle.module.url(forResource: "agy-quota", withExtension: "exp") else { throw ProviderError.unavailable("Antigravity quota helper is missing.") }
        let result: ProcessResult
        do {
            result = try ProcessRunner.run(executable: URL(fileURLWithPath: "/usr/bin/expect"),
                arguments: ["-N", "-n", "-f", helper.path, cli.path, directory.path], timeout: 32)
        } catch ProcessRunnerError.timedOut { throw ProviderError.timedOut("agy /usage") }
        switch result.exitCode {
        case 0: return try Self.parse(String(decoding: result.stdout, as: UTF8.self))
        case 3: throw ProviderError.notSignedIn("agy")
        case 4: throw ProviderError.timedOut("agy /usage")
        default: throw ProviderError.invalidResponse("agy /usage")
        }
    }

    public static func parse(_ output: String, now: Date = Date()) throws -> UsageSnapshot {
        let plain = output.replacingOccurrences(of: #"\x1B\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
        let lines = plain.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let invalid = ProviderError.invalidResponse("agy /usage")
        var group: String?
        var accountID: String?
        var windows: [UsageWindow] = []
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("Account: ") {
                let identity = String(line.dropFirst(9)).lowercased()
                if identity.wholeMatch(of: #/[^\s@]+@[^\s@]+\.[^\s@]+/#) != nil {
                    accountID = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                }
            }
            if line == line.uppercased(), line.first?.isLetter == true {
                group = line.hasPrefix("GEMINI ") || line == "GEMINI" ? line : nil
                continue
            }
            guard let group, line.hasSuffix("Limit Remaining") || line.hasSuffix(" Limit") else { continue }
            guard index + 1 < lines.count,
                  let match = lines[index + 1].wholeMatch(of: #/\[[█░ ]+\]\s+([0-9]+(?:\.[0-9]+)?)%/#),
                  let remaining = Double(match.1), (0...100).contains(remaining) else { throw invalid }
            let name = line.lowercased().hasPrefix(group.lowercased() + " ") ? line : group.capitalized + " · " + line
            let id = (group + " " + line).lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
            guard !windows.contains(where: { $0.id == id }) else { throw invalid }
            var reset: Date?
            if index + 2 < lines.count, lines[index + 2].hasPrefix("Refreshes in ") {
                let duration = lines[index + 2].dropFirst(13)
                var minutes = 0
                for part in duration.split(separator: " ") {
                    guard let n = Int(part.dropLast()), (0...525600).contains(n) else { throw invalid }
                    switch part.last {
                    case "h": minutes += n * 60
                    case "m": minutes += n
                    case "d": minutes += n * 1440
                    default: throw invalid
                    }
                }
                reset = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 60) * 60 + Double(minutes * 60))
            }
            let duration = line.contains("Weekly") ? 10080 : line.contains("Five Hour") ? 300 : nil
            windows.append(UsageWindow(id: id, name: name, usedPercent: 100 - remaining, resetsAt: reset, durationMinutes: duration))
        }
        guard !windows.isEmpty else { throw invalid }
        return UsageSnapshot(provider: .gemini, plan: nil, windows: windows, fetchedAt: now,
                             source: "Antigravity CLI /usage", accountID: accountID)
    }
}
