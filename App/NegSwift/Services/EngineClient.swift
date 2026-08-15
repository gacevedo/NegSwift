//
//  EngineClient.swift
//  NegSwift
//

import Foundation

struct SaveConfigResult: Codable, Sendable {
    let sidecarPath: String

    enum CodingKeys: String, CodingKey {
        case sidecarPath = "sidecar_path"
    }
}

struct LoadConfigResult: Codable, Sendable {
    let config: [String: JSONValue]
}

/// Loose JSON value for flat WorkspaceConfig payloads from the engine.
enum JSONValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .int(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var anyValue: Any {
        switch self {
        case let .string(value):
            value
        case let .int(value):
            value
        case let .double(value):
            value
        case let .bool(value):
            value
        case let .object(value):
            value.mapValues(\.anyValue)
        case let .array(value):
            value.map(\.anyValue)
        case .null:
            NSNull()
        }
    }
}

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
    private var activePreviewJobID: String?
    private var activeThumbnailJobID: String?
    private var activeExportJobID: String?

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

    func render(
        path: String,
        longEdgePx: Int? = nil,
        config: FrameEditState? = nil,
        cropPreviewFull: Bool = false
    ) async throws -> RenderResult {
        let isThumbnail = longEdgePx != nil && !cropPreviewFull
        if isThumbnail {
            if let previous = activeThumbnailJobID {
                try? await cancel(jobID: previous)
            }
        } else if let previous = activePreviewJobID {
            try? await cancel(jobID: previous)
        }
        let jobID = UUID().uuidString
        if isThumbnail {
            activeThumbnailJobID = jobID
        } else {
            activePreviewJobID = jobID
        }
        defer {
            if isThumbnail {
                if activeThumbnailJobID == jobID {
                    activeThumbnailJobID = nil
                }
            } else if activePreviewJobID == jobID {
                activePreviewJobID = nil
            }
        }
        do {
            return try await call(
                method: "render",
                params: RenderParams(
                    path: path,
                    longEdgePx: longEdgePx,
                    config: config,
                    cropPreviewFull: cropPreviewFull
                ),
                id: jobID
            )
        } catch EngineClientError.engine(let payload) where payload.code == "CANCELLED" {
            throw CancellationError()
        }
    }

    func loadConfig(path: String) async throws -> LoadConfigResult {
        try await call(method: "load_config", params: LoadConfigParams(path: path))
    }

    func saveConfig(path: String, config: FrameEditState) async throws -> SaveConfigResult {
        try await call(method: "save_config", params: SaveConfigParams(path: path, config: config))
    }

    func discover(paths: [String]) async throws -> DiscoverResult {
        try await call(method: "discover", params: DiscoverParams(paths: paths))
    }

    func export(
        path: String,
        destDir: String,
        config: FrameEditState,
        export settings: ExportSettings
    ) async throws -> ExportResult {
        let jobID = UUID().uuidString
        activeExportJobID = jobID
        defer {
            if activeExportJobID == jobID {
                activeExportJobID = nil
            }
        }
        do {
            return try await call(
                method: "export",
                params: ExportParams(
                    path: path,
                    destDir: destDir,
                    config: config,
                    export: ExportWireSettings(settings: settings)
                ),
                id: jobID
            )
        } catch EngineClientError.engine(let payload) where payload.code == "CANCELLED" {
            throw CancellationError()
        }
    }

    func cancel(jobID: String) async throws {
        failPendingRequest(jobID: jobID)
        let _: CancelResult = try await call(
            method: "cancel",
            params: CancelParams(jobID: jobID),
            id: UUID().uuidString
        )
    }

    private func failPendingRequest(jobID: String) {
        if let continuation = pending.removeValue(forKey: jobID) {
            continuation.resume(throwing: CancellationError())
        }
    }

    private struct ExportWireSettings: Encodable {
        let exportFmt: String
        let exportColorSpace: String
        let exportResolutionMode: String
        let jpegQuality: Int?

        enum CodingKeys: String, CodingKey {
            case exportFmt = "export_fmt"
            case exportColorSpace = "export_color_space"
            case exportResolutionMode = "export_resolution_mode"
            case jpegQuality = "jpeg_quality"
        }

        init(settings: ExportSettings) {
            exportFmt = settings.format.rawValue
            exportColorSpace = settings.colorSpace
            exportResolutionMode = "original"
            jpegQuality = settings.format == .jpeg ? settings.jpegQuality : nil
        }
    }

    private struct ExportParams: Encodable {
        let path: String
        let destDir: String
        let preferGpu: Bool = true
        let overwrite: Bool = false
        let config: FrameEditState
        let export: ExportWireSettings

        enum CodingKeys: String, CodingKey {
            case path
            case destDir = "dest_dir"
            case preferGpu = "prefer_gpu"
            case overwrite
            case config
            case export
        }
    }

    private struct EmptyParams: Encodable {}
    private struct PingResult: Decodable { let pong: Bool? }
    private struct CancelResult: Decodable { let cancelled: Bool }
    private struct CancelParams: Encodable {
        let jobID: String

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
        }
    }

    private struct DiscoverParams: Encodable {
        let paths: [String]
    }

    private struct LoadConfigParams: Encodable {
        let path: String
    }

    private struct SaveConfigParams: Encodable {
        let path: String
        let config: FrameEditState
    }

    private struct RenderParams: Encodable {
        let path: String
        let longEdgePx: Int?
        let preferGpu: Bool = true
        let config: FrameEditState?
        let cropPreviewFull: Bool

        enum CodingKeys: String, CodingKey {
            case path
            case longEdgePx = "long_edge_px"
            case preferGpu = "prefer_gpu"
            case config
            case cropPreviewFull = "crop_preview_full"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(longEdgePx, forKey: .longEdgePx)
            try container.encode(preferGpu, forKey: .preferGpu)
            try container.encode(cropPreviewFull, forKey: .cropPreviewFull)
            if let config {
                try container.encode(config, forKey: .config)
            }
        }
    }

    private func call<Params: Encodable, Result: Decodable>(
        method: String,
        params: Params,
        id: String = UUID().uuidString
    ) async throws -> Result {
        try await start()
        guard let stdin else { throw EngineClientError.notRunning }

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
