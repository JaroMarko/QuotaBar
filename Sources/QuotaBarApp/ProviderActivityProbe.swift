import AppKit
import Darwin
import QuotaBarCore

@MainActor
enum ProviderActivityProbe {
    nonisolated static func bundleIDs(for provider: ProviderKind) -> [String] {
        switch provider {
        case .claude: ["com.anthropic.claudefordesktop"]
        case .codex: ["com.openai.codex", "com.openai.chat"]
        case .gemini: []
        }
    }

    static func isRunning(_ provider: ProviderKind) -> Bool? {
        if NSWorkspace.shared.runningApplications.contains(where: { bundleIDs(for: provider).contains($0.bundleIdentifier ?? "") }) {
            return true
        }
        // Read process names/UID/parent only, never arguments or environment.
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard count > 0, Int(count) < pids.count else { return nil }
        for pid in pids.prefix(Int(count)) where pid > 0 && pid != getpid() {
            var name = [CChar](repeating: 0, count: 1024)
            guard proc_name(pid, &name, UInt32(name.count)) > 0,
                  matchesCLIName(String(cString: name), provider: provider) else { continue }
            var info = proc_bsdinfo()
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { return nil }
            // The quota reader launches agy through expect. Its descendants are not user activity.
            if provider == .gemini {
                var ancestor = pid_t(info.pbi_ppid)
                while ancestor > 1 {
                    if ancestor == getpid() { break }
                    var parent = proc_bsdinfo()
                    guard proc_pidinfo(ancestor, PROC_PIDTBSDINFO, 0, &parent, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0 else { break }
                    ancestor = pid_t(parent.pbi_ppid)
                }
                if ancestor == getpid() { continue }
            }
            if eligibleProcess(uid: info.pbi_uid, parent: info.pbi_ppid, ownUID: getuid(), ownPID: getpid()) { return true }
        }
        return false
    }

    nonisolated static func matchesCLIName(_ name: String, provider: ProviderKind) -> Bool {
        switch provider {
        case .claude: name == "claude" || name == "claude-native"
        case .codex: name == "codex"
        case .gemini: name == "agy"
        }
    }

    nonisolated static func eligibleProcess(uid: uid_t, parent: UInt32, ownUID: uid_t, ownPID: pid_t) -> Bool {
        uid == ownUID && parent != UInt32(ownPID)
    }
}
