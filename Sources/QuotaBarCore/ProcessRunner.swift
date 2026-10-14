import Darwin
import Foundation

struct ProcessResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum ProcessRunnerError: Error {
    case timedOut
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        standardInput: Data? = nil,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let completion = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = inputPipe
        process.terminationHandler = { _ in completion.signal() }

        try process.run()
        if let standardInput {
            inputPipe.fileHandleForWriting.write(standardInput)
        }
        try? inputPipe.fileHandleForWriting.close()

        if completion.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
            }
            throw ProcessRunnerError.timedOut
        }

        return ProcessResult(
            stdout: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            stderr: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            exitCode: process.terminationStatus
        )
    }
}

enum ExecutableLocator {
    static func find(_ name: String) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]

        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}
