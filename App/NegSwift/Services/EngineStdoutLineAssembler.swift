//
//  EngineStdoutLineAssembler.swift
//  NegSwift
//

import Foundation

/// Serializes stdout pipe chunks into complete NDJSON lines (order-preserving).
final class EngineStdoutLineAssembler: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.negswift.engine.stdout-lines")
    private var buffer = Data()
    var onLine: (@Sendable (Data) -> Void)?

    func reset() {
        queue.sync {
            buffer.removeAll(keepingCapacity: false)
        }
    }

    func append(_ chunk: Data) {
        queue.sync {
            buffer.append(chunk)
            drainBuffer()
        }
    }

    private func drainBuffer() {
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            var line = Data(buffer[..<newlineIndex])
            buffer.removeSubrange(..<newlineIndex.advanced(by: 1))
            if line.last == 0x0D {
                line.removeLast()
            }
            guard !line.isEmpty else { continue }
            onLine?(line)
        }
    }
}
