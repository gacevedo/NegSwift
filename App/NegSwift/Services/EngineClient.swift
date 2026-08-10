//
//  EngineClient.swift
//  NegSwift
//

import Foundation

struct RenderResult: Codable, Sendable {
    let width: Int
    let height: Int
    let pngBase64: String

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case pngBase64 = "png_base64"
    }

    var pngData: Data? {
        Data(base64Encoded: pngBase64)
    }
}

struct DiscoverAsset: Codable, Sendable {
    let path: String
    let name: String
}

struct DiscoverResult: Codable, Sendable {
    let assets: [DiscoverAsset]
}

struct EngineInfo: Codable, Sendable, Equatable {
    let protocolVersion: String?
    let negswiftVersion: String
    let negpyVersion: String
    let python: String
    let gpuAvailable: Bool
    let gpuBackend: String?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case negswiftVersion = "negswift_version"
        case negpyVersion = "negpy_version"
        case python
        case gpuAvailable = "gpu_available"
        case gpuBackend = "gpu_backend"
    }
}

struct EngineResponse<Result: Decodable>: Decodable {
    let id: String?
    let ok: Bool
    let result: Result?
    let error: EngineErrorPayload?
}

struct EngineErrorPayload: Decodable, Error {
    let code: String
    let message: String
}

enum EngineClientError: LocalizedError {
    case notRunning
    case invalidResponse
    case engine(EngineErrorPayload)

    var errorDescription: String? {
        switch self {
        case .notRunning:
            "Engine process is not running."
        case .invalidResponse:
            "Engine returned a response the app could not decode."
        case let .engine(payload):
            "[\(payload.code)] \(payload.message)"
        }
    }
}

/// NDJSON client over a long-lived `serve --stdio` process.
actor EngineClient {
    private let processOwner = EngineProcess()
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stdoutTask: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var lineBuffer = Data()

    func start() async throws {
        if processOwner.isRunning, stdin != nil, stdout != nil {
            return
        }
        let executable = try EngineLocator.executableURL()
        let pipes = try processOwner.start(executable: executable)
        stdin = pipes.stdin
        stdout = pipes.stdout
        startReading()
    }

    func stop() {
        stdoutTask?.cancel()
        stdoutTask = nil
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
        pending.removeAll()
        processOwner.stop()
        stdin = nil
        stdout = nil
        lineBuffer.removeAll()
    }

    func ping() async throws {
        let _: PingResult = try await call(method: "ping", params: EmptyParams())
    }

    func info() async throws -> EngineInfo {
        try await call(method: "info", params: EmptyParams())
    }

    func render(path: String, longEdgePx: Int? = nil) async throws -> RenderResult {
        try await call(method: "render", params: RenderParams(path: path, longEdgePx: longEdgePx))
    }

    func discover(paths: [String]) async throws -> DiscoverResult {
        try await call(method: "discover", params: DiscoverParams(paths: paths))
    }

    private struct EmptyParams: Encodable {}
    private struct PingResult: Decodable { let pong: Bool? }

    private struct DiscoverParams: Encodable {
        let paths: [String]
    }

    private struct RenderParams: Encodable {
        let path: String
        let longEdgePx: Int?
        let preferGpu: Bool = true

        enum CodingKeys: String, CodingKey {
            case path
            case longEdgePx = "long_edge_px"
            case preferGpu = "prefer_gpu"
        }
    }

    private func call<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params
    ) async throws -> Result {
        try await start()
        guard let stdin else { throw EngineClientError.notRunning }

        let id = UUID().uuidString
        let payload: [String: Any] = [
            "id": id,
            "method": method,
            "params": try params.asJSONObject(),
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var line = data
        line.append(0x0A)

        let responseData: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            do {
                try stdin.write(contentsOf: line)
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }

        let envelope = try JSONDecoder().decode(EngineResponse<Result>.self, from: responseData)
        if envelope.ok, let result = envelope.result {
            return result
        }
        if let error = envelope.error {
            throw EngineClientError.engine(error)
        }
        throw EngineClientError.invalidResponse
    }

    private func startReading() {
        guard let stdout else { return }
        stdoutTask?.cancel()
        stdoutTask = Task {
            do {
                for try await byte in stdout.bytes {
                    try Task.checkCancellation()
                    lineBuffer.append(byte)
                    if byte == 0x0A {
                        let line = lineBuffer
                        lineBuffer.removeAll(keepingCapacity: true)
                        handleLine(line)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                failAll(error)
            }
        }
    }

    private func handleLine(_ lineData: Data) {
        guard !lineData.isEmpty else { return }
        guard
            let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let id = object["id"] as? String,
            let continuation = pending.removeValue(forKey: id)
        else {
            return
        }
        continuation.resume(returning: lineData)
    }

    private func failAll(_ error: Error) {
        let waiters = pending
        pending.removeAll()
        waiters.values.forEach { $0.resume(throwing: error) }
    }
}

private extension Encodable {
    func asJSONObject() throws -> Any {
        let data = try JSONEncoder().encode(self)
        return try JSONSerialization.jsonObject(with: data)
    }
}
