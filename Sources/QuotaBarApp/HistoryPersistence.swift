import Foundation
import QuotaBarCore

actor HistoryPersistence {
    private let url: URL
    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuotaBar/history.json")
    }

    func load() throws -> UsageHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return UsageHistory() }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size < 10_000_000 else { throw CocoaError(.fileReadTooLarge) }
        var history = try JSONDecoder().decode(UsageHistory.self, from: Data(contentsOf: url))
        history.prune(now: Date())
        return history
    }

    func save(_ history: UsageHistory) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(history).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
