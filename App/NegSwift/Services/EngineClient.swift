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

struct ResetConfigResult: Codable, Sendable {
    let sidecarRemoved: Bool

    enum CodingKeys: String, CodingKey {
        case sidecarRemoved = "sidecar_removed"
    }
}

struct LoadConfigResult: Codable, Sendable {
    let config: [String: JSONValue]
}

struct DetectProcessModeResult: Codable, Sendable {
    let skipped: Bool
    let reason: String?
    let detectedMode: String?
    let processMode: String?

    enum CodingKeys: String, CodingKey {
        case skipped
        case reason
        case detectedMode = "detected_mode"
        case processMode = "process_mode"
    }
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

/// Preview image encoding for engine `render` IPC (M12 Phase 4).
enum PreviewTransportFormat: String, Encodable, Sendable {
    case png
    case jpeg
}

struct RenderMetrics: Codable, Sendable {
    let detectedCropRect: [Double]?

    enum CodingKeys: String, CodingKey {
        case detectedCropRect = "detected_crop_rect"
    }
}

struct RenderResult: Codable, Sendable {
    let width: Int
    let height: Int
    let previewFormat: String?
    let pngBase64: String?
    let jpegBase64: String?
    let metrics: RenderMetrics?

    enum CodingKeys: String, CodingKey {
        case width
        case height
        case previewFormat = "preview_format"
        case pngBase64 = "png_base64"
        case jpegBase64 = "jpeg_base64"
        case metrics
    }

    var imageBase64: String? {
        if previewFormat == PreviewTransportFormat.jpeg.rawValue || jpegBase64 != nil && pngBase64 == nil {
            return jpegBase64
        }
        return pngBase64 ?? jpegBase64
    }

    var imageData: Data? {
        guard let imageBase64 else { return nil }
        return Data(base64Encoded: imageBase64)
    }

    /// Legacy accessor — PNG responses only.
    var pngData: Data? {
        guard let pngBase64 else { return nil }
        return Data(base64Encoded: pngBase64)
    }
}

struct DiscoverAsset: Codable, Sendable {
    let path: String
    let name: String
}

struct DiscoverResult: Codable, Sendable {
    let assets: [DiscoverAsset]
}

struct AppendHealStrokeResult: Codable, Sendable {
    let manualHealStrokes: [HealStroke]
    let strokeIndex: Int

    enum CodingKeys: String, CodingKey {
        case manualHealStrokes = "manual_heal_strokes"
        case strokeIndex = "stroke_index"
    }
}

struct UndoLastHealResult: Codable, Sendable {
    let manualHealStrokes: [HealStroke]
    let removed: String?

    enum CodingKeys: String, CodingKey {
        case manualHealStrokes = "manual_heal_strokes"
        case removed
    }
}

struct OpenResult: Codable, Sendable {
    let path: String
    let hash: String
    let width: Int
    let height: Int
    let hasSidecar: Bool

    enum CodingKeys: String, CodingKey {
        case path
        case hash
        case width
        case height
        case hasSidecar = "has_sidecar"
    }
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
    nonisolated private let stdoutAssembler = EngineStdoutLineAssembler()
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var pending: [String: CheckedContinuation<Data, Error>] = [:]
    private var activePreviewJobID: String?
    private var activeStripThumbnailJobIDs: Set<String> = []
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
        stdout?.readabilityHandler = nil
        stdoutAssembler.onLine = nil
        stdoutAssembler.reset()
        pending.values.forEach { $0.resume(throwing: CancellationError()) }
        pending.removeAll()
        activePreviewJobID = nil
        activeStripThumbnailJobIDs.removeAll()
        processOwner.stop()
        stdin = nil
        stdout = nil
    }

    func ping() async throws {
        let _: PingResult = try await call(method: "ping", params: EmptyParams())
    }

    func info() async throws -> EngineInfo {
        try await call(method: "info", params: EmptyParams())
    }

    func open(path: String) async throws -> OpenResult {
        try await call(method: "open", params: OpenParams(path: path))
    }

    func render(
        path: String,
        longEdgePx: Int? = nil,
        preferGPU: Bool = true,
        config: FrameEditState? = nil,
        cropPreviewFull: Bool = false,
        stripThumbnail: Bool = false,
        previewFormat: PreviewTransportFormat = .jpeg,
        jpegQuality: Int = PreviewRenderSettings.previewJPEGQuality
    ) async throws -> RenderResult {
        if !stripThumbnail {
            if let previous = activePreviewJobID {
                try? await cancel(jobID: previous)
            }
            for thumbID in activeStripThumbnailJobIDs {
                try? await cancel(jobID: thumbID)
            }
            activeStripThumbnailJobIDs.removeAll()
        }
        let jobID = UUID().uuidString
        if stripThumbnail {
            activeStripThumbnailJobIDs.insert(jobID)
        } else {
            activePreviewJobID = jobID
        }
        defer {
            if stripThumbnail {
                activeStripThumbnailJobIDs.remove(jobID)
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
                    preferGpu: preferGPU,
                    config: config,
                    cropPreviewFull: cropPreviewFull,
                    previewFormat: previewFormat,
                    jpegQuality: jpegQuality
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

    func detectProcessMode(path: String, force: Bool = false) async throws -> DetectProcessModeResult {
        try await call(
            method: "detect_process_mode",
            params: DetectProcessModeParams(path: path, force: force)
        )
    }

    func saveConfig(path: String, config: FrameEditState) async throws -> SaveConfigResult {
        try await call(method: "save_config", params: SaveConfigParams(path: path, config: config))
    }

    func resetConfig(path: String) async throws -> ResetConfigResult {
        try await call(method: "reset_config", params: LoadConfigParams(path: path))
    }

    func appendHealStroke(
        path: String,
        points: [[Double]],
        brushSize: Int,
        config: FrameEditState
    ) async throws -> AppendHealStrokeResult {
        try await call(
            method: "append_heal_stroke",
            params: AppendHealStrokeParams(
                path: path,
                points: points,
                brushSize: brushSize,
                config: config
            )
        )
    }

    func undoLastHeal(path: String, config: FrameEditState) async throws -> UndoLastHealResult {
        try await call(
            method: "undo_last_heal",
            params: UndoLastHealParams(path: path, config: config)
        )
    }

    func discover(paths: [String]) async throws -> DiscoverResult {
        try await call(method: "discover", params: DiscoverParams(paths: paths))
    }

    func export(
        path: String,
        destDir: String,
        config: FrameEditState,
        export settings: ExportSettings,
        preferGPU: Bool = true
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
                    preferGpu: preferGPU,
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
        let preferGpu: Bool
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

    private struct OpenParams: Encodable {
        let path: String
    }

    private struct LoadConfigParams: Encodable {
        let path: String
    }

    private struct DetectProcessModeParams: Encodable {
        let path: String
        let force: Bool
    }

    private struct SaveConfigParams: Encodable {
        let path: String
        let config: FrameEditState
    }

    private struct AppendHealStrokeParams: Encodable {
        let path: String
        let points: [[Double]]
        let brushSize: Int
        let config: FrameEditState

        enum CodingKeys: String, CodingKey {
            case path
            case points
            case brushSize = "brush_size"
            case config
        }
    }

    private struct UndoLastHealParams: Encodable {
        let path: String
        let config: FrameEditState
    }

    private struct RenderParams: Encodable {
        let path: String
        let longEdgePx: Int?
        let preferGpu: Bool
        let config: FrameEditState?
        let cropPreviewFull: Bool
        let previewFormat: PreviewTransportFormat
        let jpegQuality: Int

        enum CodingKeys: String, CodingKey {
            case path
            case longEdgePx = "long_edge_px"
            case preferGpu = "prefer_gpu"
            case config
            case cropPreviewFull = "crop_preview_full"
            case previewFormat = "preview_format"
            case jpegQuality = "jpeg_quality"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encodeIfPresent(longEdgePx, forKey: .longEdgePx)
            try container.encode(preferGpu, forKey: .preferGpu)
            try container.encode(cropPreviewFull, forKey: .cropPreviewFull)
            try container.encode(previewFormat, forKey: .previewFormat)
            if previewFormat == .jpeg {
                try container.encode(jpegQuality, forKey: .jpegQuality)
            }
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
        stdoutAssembler.onLine = { line in
            Task { await self.handleCompleteStdoutLine(line) }
        }
        stdout.readabilityHandler = { [assembler = stdoutAssembler] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            assembler.append(chunk)
        }
    }

    private func handleCompleteStdoutLine(_ lineData: Data) {
        handleLine(lineData)
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
