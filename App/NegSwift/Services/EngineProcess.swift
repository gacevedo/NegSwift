//
//  EngineProcess.swift
//  NegSwift
//

import Foundation
import os

/// Owns the `negswift-engine serve --stdio` subprocess and its pipes.
final class EngineProcess: @unchecked Sendable {
    private let log = Logger(subsystem: "com.gabrielacevedo.NegSwift", category: "EngineProcess")
    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return process?.isRunning ?? false
    }

    func start(executable: URL) throws -> (stdin: FileHandle, stdout: FileHandle) {
        lock.lock()
        defer { lock.unlock() }

        if let process, process.isRunning, let stdinHandle, let stdoutHandle {
            return (stdinHandle, stdoutHandle)
        }

        stopLocked()

        let proc = Process()
        proc.executableURL = executable
        proc.arguments = ["serve", "--stdio"]
        proc.currentDirectoryURL = executable.deletingLastPathComponent().deletingLastPathComponent()

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardInput = stdinPipe
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    self?.log.debug("engine stderr: \(trimmed, privacy: .public)")
                }
            }
        }

        proc.terminationHandler = { [weak self] finished in
            self?.log.info("engine exited status \(finished.terminationStatus)")
        }

        try proc.run()

        let stdin = stdinPipe.fileHandleForWriting
        let stdout = stdoutPipe.fileHandleForReading
        process = proc
        stdinHandle = stdin
        stdoutHandle = stdout
        log.info("engine started pid \(proc.processIdentifier)")
        return (stdin, stdout)
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        if let process, process.isRunning {
            process.terminate()
        }
        try? stdinHandle?.close()
        try? stdoutHandle?.close()
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
    }
}
