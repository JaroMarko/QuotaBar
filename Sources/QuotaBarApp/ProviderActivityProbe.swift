import AppKit
import Darwin
import QuotaBarCore

@MainActor
enum ProviderActivityProbe {
    nonisolated static func bundleIDs(for provider: ProviderKind) -> [String] {
        provider == .claude ? ["com.anthropic.claudefordesktop"] : ["com.openai.codex", "com.openai.chat"]
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
            if eligibleProcess(uid: info.pbi_uid, parent: info.pbi_ppid, ownUID: getuid(), ownPID: getpid()) { return true }
        }
        return false
    }

    nonisolated static func matchesCLIName(_ name: String, provider: ProviderKind) -> Bool {
        provider == .claude ? (name == "claude" || name == "claude-native") : name == "codex"
    }

    nonisolated static func eligibleProcess(uid: uid_t, parent: UInt32, ownUID: uid_t, ownPID: pid_t) -> Bool {
        uid == ownUID && parent != UInt32(ownPID)
    }
}
