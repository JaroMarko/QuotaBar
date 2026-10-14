import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
}

public enum ProcessRunnerError: Error { case timedOut, inputTooLarge }

// Drain both pipes while the child runs: waiting before reading can deadlock
// on a full pipe. Retain at most 1 MiB; still drain additional bytes.
final class PipeCapture: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var bytes = Data()
    private var cancelled = false
    private var didFinish = false
    private let finished = DispatchSemaphore(value: 0)

    init(_ handle: FileHandle) {
        self.handle = handle
        DispatchQueue.global(qos: .utility).async { self.readLoop() }
    }

    private func readLoop() {
        defer { finished.signal() }
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            lock.lock(); let stop = cancelled; lock.unlock()
            if stop { return }
            var fd = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&fd, 1, 50)
            if ready == 0 { continue }
            if ready < 0 { if errno == EINTR { continue }; return }
            let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
            if count <= 0 { if count < 0 && errno == EINTR { continue }; return }
            lock.lock()
            let retained = min(count, max(0, 1_048_576 - bytes.count))
            bytes.append(contentsOf: buffer.prefix(retained))
            lock.unlock()
        }
    }

    func finish() -> Data {
        lock.lock()
        if didFinish { let result = bytes; lock.unlock(); return result }
        didFinish = true
        lock.unlock()
        if finished.wait(timeout: .now() + 0.5) == .timedOut {
            lock.lock(); cancelled = true; lock.unlock()
            _ = finished.wait(timeout: .now() + 0.2)
        }
        lock.lock(); defer { lock.unlock() }
        return bytes
    }
}

public enum ProcessRunner {
    public static func run(executable: URL, arguments: [String], standardInput: Data? = nil,
                           timeout: TimeInterval) throws -> ProcessResult {
        guard (standardInput?.count ?? 0) <= 4096 else { throw ProcessRunnerError.inputTooLarge }
        let process = Process()
        let output = Pipe(), error = Pipe(), input = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output; process.standardError = error; process.standardInput = input
        process.terminationHandler = { _ in completion.signal() }
        try process.run()
        let outCapture = PipeCapture(output.fileHandleForReading)
        let errCapture = PipeCapture(error.fileHandleForReading)
        defer {
            terminate(process)
            try? input.fileHandleForWriting.close()
            _ = outCapture.finish(); _ = errCapture.finish()
        }
        // Inputs in this app are small RPC/credential probes, never user content.
        if let standardInput { try input.fileHandleForWriting.write(contentsOf: standardInput) }
        try? input.fileHandleForWriting.close()
        if completion.wait(timeout: .now() + timeout) == .timedOut {
            terminate(process)
            throw ProcessRunnerError.timedOut
        }
        return ProcessResult(stdout: outCapture.finish(), stderr: errCapture.finish(),
                             exitCode: process.terminationStatus)
    }

    static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.3)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
}

public enum ExecutableLocator {
    public static func find(_ name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let directories = ["/opt/homebrew/bin", "\(home)/.local/bin", "/usr/local/bin", "/usr/bin"]
            + path.split(separator: ":").map(String.init)
        var candidates = directories.map { "\($0)/\(name)" }
        if name == "codex" { candidates.append("/Applications/Codex.app/Contents/Resources/codex") }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }
}
