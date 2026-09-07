import Foundation

/// NDJSON request/response matching `docs/ENGINE_PROTOCOL.md`.
public struct ProtocolServer: Sendable {
    public static let previewFormats: Set<String> = ["png", "jpeg"]
    public static let defaultJPEGQuality = 90
    public static let scanExtensions: Set<String> = ScanFormat.scanExtensions

    public init() {}

    public func handleLine(_ raw: String) -> String {
        let payload = handleMessage(raw)
        let data = (try? ConfigJSON.jsonData(payload)) ?? fallbackErrorJSON()
        return String(data: data, encoding: .utf8) ?? #"{"ok":false,"error":{"code":"INTERNAL","message":"encode"}}"#
    }

    public func handleMessage(_ raw: String) -> [String: Any] {
        var reqID: Any = NSNull()
        do {
            guard let data = raw.data(using: .utf8) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "Malformed JSON")
            }
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let msg = obj as? [String: Any] else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "Request must be a JSON object")
            }
            if let id = msg["id"] {
                reqID = id
            }
            guard let method = msg["method"] as? String else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "Missing or invalid method")
            }
            let params: [String: Any]
            if let rawParams = msg["params"] {
                if let dict = rawParams as? [String: Any] {
                    params = dict
                } else if rawParams is NSNull {
                    params = [:]
                } else {
                    throw ProtocolFailure(code: "INVALID_REQUEST", message: "params must be an object")
                }
            } else {
                params = [:]
            }
            let result = try dispatch(method: method, params: params)
            return ["id": reqID, "ok": true, "result": result]
        } catch let failure as ProtocolFailure {
            return errorPayload(id: reqID, code: failure.code, message: failure.message)
        } catch let error as LinearDecodeError {
            return errorPayload(id: reqID, code: Self.mapDecode(error).code, message: error.localizedDescription)
        } catch is SidecarStoreError {
            return errorPayload(id: reqID, code: "SAVE_FAILED", message: "Sidecar write error")
        } catch {
            if error is CocoaError {
                return errorPayload(id: reqID, code: "LOAD_FAILED", message: error.localizedDescription)
            }
            return errorPayload(id: reqID, code: "INTERNAL", message: error.localizedDescription)
        }
    }

    public func serveStdio() {
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            FileHandle.standardOutput.write(Data((handleLine(trimmed) + "\n").utf8))
            fflush(stdout)
        }
    }

    public func dispatch(method: String, params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "ping":
            ["pong": true]
        case "info":
            NativePipeline().infoJSON()
        case "open":
            try cmdOpen(params)
        case "discover":
            try cmdDiscover(params)
        case "load_config":
            try cmdLoadConfig(params)
        case "save_config":
            try cmdSaveConfig(params)
        case "reset_config":
            try cmdResetConfig(params)
        case "detect_process_mode":
            try cmdDetect(params)
        case "render":
            try cmdRender(params)
        case "cancel":
            try cmdCancel(params)
        case "append_heal_stroke":
            try cmdAppendHeal(params)
        case "undo_last_heal":
            try cmdUndoHeal(params)
        case "export":
            try cmdExport(params)
        default:
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "Unknown method: \(method)")
        }
    }

    private func cmdOpen(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        if params["include_splash"] != nil {
            guard ConfigJSON.isJSONBool(params["include_splash"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.include_splash must be a boolean")
            }
        }
        if params["config"] != nil {
            guard params["config"] is [String: Any] || params["config"] is NSNull else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.config must be an object")
            }
        }
        try requireExistingFile(path)
        let includeSplash = ConfigJSON.boolValue(params["include_splash"]) ?? false
        let dims = NativePipeline().probeSource(at: path) ?? (1, 1)
        var result: [String: Any] = [
            "path": path,
            "hash": Self.fileToken(path),
            "width": dims.width,
            "height": dims.height,
            "has_sidecar": SidecarStore.exists(forScanPath: path),
        ]
        if includeSplash, let splash = NativePipeline().splashJPEG(path: path) {
            result["splash_width"] = splash.width
            result["splash_height"] = splash.height
            result["splash_jpeg_base64"] = splash.jpeg.base64EncodedString()
        }
        var overrides: [String: Any] = [:]
        if let dict = params["config"] as? [String: Any] {
            overrides = dict
        }
        let base = try SidecarStore.baseFlat(forScanPath: path)
        let flat = ConfigJSON.merge(base, overrides)
        let printConfig = PrintConfig.s8Pin.merging(flat)
        if Autocrop.isArmed(printConfig), printConfig.cropRect == nil {
            let preview = try NativePipeline().decode(
                path: path,
                maxLongEdge: Autocrop.detectResolution,
                analysisOversample: true
            )
            if let rect = Autocrop.resolveRect(preview, config: printConfig) {
                result["suggested_crop_rect"] = rect.arrayValue
                result["crop_detect_key"] = Autocrop.detectionKey(printConfig)
            }
        }
        return result
    }

    private func cmdDiscover(_ params: [String: Any]) throws -> [String: Any] {
        guard let paths = params["paths"] as? [Any], !paths.isEmpty,
              paths.allSatisfy({ $0 is String })
        else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.paths must be a non-empty string array")
        }
        var assets: [[String: String]] = []
        for path in paths.compactMap({ $0 as? String }) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                for name in names {
                    let full = (path as NSString).appendingPathComponent(name)
                    if Self.isSupportedScan(full) {
                        assets.append(["path": full, "name": name])
                    }
                }
            } else if Self.isSupportedScan(path) {
                assets.append(["path": path, "name": (path as NSString).lastPathComponent])
            }
        }
        let unique = Dictionary(assets.map { ($0["path"] ?? "", $0) }, uniquingKeysWith: { first, _ in first })
        let sorted = unique.values.sorted {
            ($0["name"] ?? "").localizedCaseInsensitiveCompare($1["name"] ?? "") == .orderedAscending
        }
        return ["assets": sorted]
    }

    private func cmdLoadConfig(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        let loaded = try SidecarStore.load(path: path)
        return ["config": loaded.config, "has_sidecar": loaded.hasSidecar]
    }

    private func cmdSaveConfig(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        var overrides: [String: Any]?
        if let config = params["config"] {
            if config is NSNull {
                overrides = nil
            } else if let dict = config as? [String: Any] {
                overrides = dict
            } else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.config must be an object")
            }
        }
        do {
            let sidecar = try SidecarStore.save(path: path, overrides: overrides)
            return ["sidecar_path": sidecar]
        } catch {
            throw ProtocolFailure(code: "SAVE_FAILED", message: error.localizedDescription)
        }
    }

    private func cmdResetConfig(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        do {
            let removed = try SidecarStore.reset(path: path)
            return ["sidecar_removed": removed]
        } catch {
            throw ProtocolFailure(code: "RESET_FAILED", message: error.localizedDescription)
        }
    }

    private func cmdDetect(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        var force = false
        if let raw = params["force"] {
            guard ConfigJSON.isJSONBool(raw) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.force must be a boolean")
            }
            force = ConfigJSON.boolValue(raw) ?? false
        }
        if !force, SidecarStore.exists(forScanPath: path) {
            return ["skipped": true, "reason": "has_sidecar"]
        }
        try requireExistingFile(path)
        let mode = try NativePipeline().detectProcessMode(path: path)
        return [
            "skipped": false,
            "detected_mode": mode.rawValue,
            "process_mode": mode.liteMode.rawValue,
        ]
    }

    private func cmdRender(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        var overrides: [String: Any] = [:]
        if let config = params["config"] {
            if config is NSNull {
                overrides = [:]
            } else if let dict = config as? [String: Any] {
                overrides = dict
            } else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.config must be an object")
            }
        }
        var longEdge: Int?
        if params["long_edge_px"] != nil {
            guard let value = ConfigJSON.intValue(params["long_edge_px"]) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.long_edge_px must be an integer")
            }
            longEdge = value
        }
        if params["prefer_gpu"] != nil {
            guard ConfigJSON.isJSONBool(params["prefer_gpu"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.prefer_gpu must be a boolean")
            }
        }
        var cropPreviewFull = false
        if params["crop_preview_full"] != nil {
            guard ConfigJSON.isJSONBool(params["crop_preview_full"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.crop_preview_full must be a boolean")
            }
            cropPreviewFull = ConfigJSON.boolValue(params["crop_preview_full"]) ?? false
        }
        var fastPreview = false
        if params["fast_preview"] != nil {
            guard ConfigJSON.isJSONBool(params["fast_preview"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.fast_preview must be a boolean")
            }
            fastPreview = ConfigJSON.boolValue(params["fast_preview"]) ?? false
        }
        var draftPreview = false
        if params["draft_preview"] != nil {
            guard ConfigJSON.isJSONBool(params["draft_preview"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.draft_preview must be a boolean")
            }
            draftPreview = ConfigJSON.boolValue(params["draft_preview"]) ?? false
        }
        var previewFormat = "png"
        if let raw = params["preview_format"] {
            guard let fmt = raw as? String, Self.previewFormats.contains(fmt) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.preview_format must be 'png' or 'jpeg'")
            }
            previewFormat = fmt
        }
        var jpegQuality = Self.defaultJPEGQuality
        if params["jpeg_quality"] != nil {
            guard let value = ConfigJSON.intValue(params["jpeg_quality"]), (1 ... 100).contains(value) else {
                throw ProtocolFailure(
                    code: "INVALID_REQUEST",
                    message: "params.jpeg_quality must be an integer from 1 to 100"
                )
            }
            jpegQuality = value
        }

        try requireExistingFile(path)
        let base = try SidecarStore.baseFlat(forScanPath: path)
        let flat = ConfigJSON.merge(base, overrides)
        var printConfig = PrintConfig.s8Pin.merging(flat)
        printConfig.applyPixelCrop = !cropPreviewFull
        let processMode = WorkspaceFlatConfig.processMode(from: flat)
        if fastPreview {
            return try cmdCheapThumb(
                path: path,
                longEdge: longEdge,
                processMode: processMode,
                printConfig: printConfig,
                previewFormat: previewFormat,
                jpegQuality: jpegQuality
            )
        }
        do {
            let printed = try NativePipeline().renderPrintDetailed(
                path: path,
                longEdgePx: longEdge,
                processMode: processMode,
                config: printConfig,
                previewPass: draftPreview ? .draft : .settled
            )
            let buffer = printed.buffer
            let data: Data
            if previewFormat == "jpeg" {
                data = try ImageCoding.jpegDataFromWorkingSpace(
                    buffer,
                    quality: Double(jpegQuality) / 100
                )
            } else {
                data = try ImageCoding.pngDataFromWorkingSpace(buffer)
            }
            var metrics: [String: Any] = [:]
            if let resolved = printed.resolvedAutocrop {
                metrics["autocrop_resolved_rect"] = resolved.arrayValue
                metrics["autocrop_resolved_key"] = resolved.key
            }
            if cropPreviewFull, let crop = printed.cropRect {
                metrics["detected_crop_rect"] = crop.arrayValue
            }
            var result: [String: Any] = [
                "width": buffer.width,
                "height": buffer.height,
                "preview_format": previewFormat,
                "metrics": metrics,
            ]
            let encoded = data.base64EncodedString()
            if previewFormat == "jpeg" {
                result["jpeg_base64"] = encoded
            } else {
                result["png_base64"] = encoded
            }
            return result
        } catch let error as LinearDecodeError {
            throw ProtocolFailure(code: Self.mapDecode(error).code, message: error.localizedDescription)
        } catch {
            throw ProtocolFailure(code: "RENDER_FAILED", message: error.localizedDescription)
        }
    }

    private func cmdCheapThumb(
        path: String,
        longEdge: Int?,
        processMode: FilmProcessMode?,
        printConfig: PrintConfig,
        previewFormat: String,
        jpegQuality: Int
    ) throws -> [String: Any] {
        do {
            let buffer = try NativePipeline().cheapThumb(
                path: path,
                longEdgePx: longEdge ?? 256,
                processMode: processMode,
                config: printConfig
            )
            let data: Data
            if previewFormat == "jpeg" {
                data = try ImageCoding.jpegData(from: buffer, quality: Double(jpegQuality) / 100)
            } else {
                data = try ImageCoding.pngData(from: buffer)
            }
            var result: [String: Any] = [
                "width": buffer.width,
                "height": buffer.height,
                "preview_format": previewFormat,
                "metrics": [String: Any](),
            ]
            let encoded = data.base64EncodedString()
            if previewFormat == "jpeg" {
                result["jpeg_base64"] = encoded
            } else {
                result["png_base64"] = encoded
            }
            return result
        } catch let error as LinearDecodeError {
            throw ProtocolFailure(code: Self.mapDecode(error).code, message: error.localizedDescription)
        } catch {
            throw ProtocolFailure(code: "RENDER_FAILED", message: error.localizedDescription)
        }
    }

    private func cmdExport(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        guard let destDir = params["dest_dir"] as? String, !destDir.isEmpty else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.dest_dir is required")
        }
        let overrides = try optionalObject(params["config"], name: "config") ?? [:]
        var exportDict: [String: Any]?
        if params["export"] != nil {
            exportDict = try optionalObject(params["export"], name: "export")
        }
        if params["prefer_gpu"] != nil {
            guard ConfigJSON.isJSONBool(params["prefer_gpu"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.prefer_gpu must be a boolean")
            }
        }
        var overwrite = false
        if params["overwrite"] != nil {
            guard ConfigJSON.isJSONBool(params["overwrite"]!) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.overwrite must be a boolean")
            }
            overwrite = ConfigJSON.boolValue(params["overwrite"]) ?? false
        }
        try requireExistingFile(path)
        var settings = try NativeExportSettings.parse(exportDict)
        settings.overwrite = overwrite
        let base = try SidecarStore.baseFlat(forScanPath: path)
        let flat = ConfigJSON.merge(base, overrides)
        let printConfig = PrintConfig.s8Pin.merging(flat)
        let processMode = WorkspaceFlatConfig.processMode(from: flat)
        do {
            let result = try NativePipeline().export(
                path: path,
                destDir: destDir,
                processMode: processMode,
                config: printConfig,
                settings: settings
            )
            return [
                "output_path": result.url.path,
                "width": result.width,
                "height": result.height,
                "format": result.format,
            ]
        } catch let error as LinearDecodeError {
            throw ProtocolFailure(code: Self.mapDecode(error).code, message: error.localizedDescription)
        } catch let failure as ProtocolFailure {
            throw failure
        } catch {
            throw ProtocolFailure(code: "EXPORT_FAILED", message: error.localizedDescription)
        }
    }

    private func cmdCancel(_ params: [String: Any]) throws -> [String: Any] {
        guard let jobID = params["job_id"] as? String, !jobID.isEmpty else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.job_id is required")
        }
        return ["cancelled": false]
    }

    private func cmdAppendHeal(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        guard let rawPoints = params["points"] as? [Any], !rawPoints.isEmpty else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.points must be a non-empty array")
        }
        var points: [[Double]] = []
        for item in rawPoints {
            guard let pair = item as? [Any], pair.count == 2,
                  let x = ConfigJSON.doubleValue(pair[0]),
                  let y = ConfigJSON.doubleValue(pair[1])
            else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "each point must be [nx, ny]")
            }
            points.append([x, y])
        }
        var brush: Double?
        if params["brush_size"] != nil {
            guard let value = ConfigJSON.doubleValue(params["brush_size"]) else {
                throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.brush_size must be a number")
            }
            brush = value
        }
        let overrides = try optionalObject(params["config"], name: "config")
        return try HealStore.appendStroke(
            path: path,
            points: points,
            brushSize: brush,
            configOverrides: overrides
        )
    }

    private func cmdUndoHeal(_ params: [String: Any]) throws -> [String: Any] {
        let path = try requiredPath(params)
        let overrides = try optionalObject(params["config"], name: "config")
        return try HealStore.undoLast(path: path, configOverrides: overrides)
    }

    private func requiredPath(_ params: [String: Any]) throws -> String {
        guard let path = params["path"] as? String, !path.isEmpty else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.path is required")
        }
        return path
    }

    private func requireExistingFile(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ProtocolFailure(code: "NOT_FOUND", message: "Scan not found: \(path)")
        }
    }

    private func optionalObject(_ value: Any?, name: String) throws -> [String: Any]? {
        guard let value, !(value is NSNull) else { return nil }
        guard let dict = value as? [String: Any] else {
            throw ProtocolFailure(code: "INVALID_REQUEST", message: "params.\(name) must be an object")
        }
        return dict
    }

    private func errorPayload(id: Any, code: String, message: String) -> [String: Any] {
        [
            "id": id,
            "ok": false,
            "error": ["code": code, "message": message],
        ]
    }

    private func fallbackErrorJSON() -> Data {
        Data(#"{"ok":false,"error":{"code":"INTERNAL","message":"encode"}}"#.utf8)
    }

    private static func isSupportedScan(_ path: String) -> Bool {
        ScanFormat.isSupportedScan(path)
    }

    private static func fileToken(_ path: String) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let size = attrs?[.size] as? NSNumber ?? 0
        let modified = attrs?[.modificationDate] as? Date ?? .distantPast
        return "s7-\(size.intValue)-\(Int(modified.timeIntervalSince1970))"
    }

    fileprivate static func mapDecode(_ error: LinearDecodeError) -> ProtocolFailure {
        switch error {
        case .fileNotFound:
            ProtocolFailure(code: "NOT_FOUND", message: error.localizedDescription)
        case .unsupported, .decodeFailed, .rawUnavailable, .rawDecodeFailed:
            ProtocolFailure(code: "LOAD_FAILED", message: error.localizedDescription)
        }
    }
}
