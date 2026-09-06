import Foundation
import NegSwiftEngine

@main
struct NegSwiftEngineCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            exit(1)
        }
        do {
            switch command {
            case "info":
                try runInfo()
            case "render":
                try runRender(Array(args.dropFirst()))
            case "decode":
                try runDecode(Array(args.dropFirst()))
            case "detect":
                try runDetect(Array(args.dropFirst()))
            case "oetf-ramp":
                try runOETFRamp(Array(args.dropFirst()))
            case "serve":
                try runServe(Array(args.dropFirst()))
            case "-h", "--help":
                printUsage()
            default:
                FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
                printUsage()
                exit(1)
            }
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func printUsage() {
        let text = """
        usage: negswift-engine-swift <command>

        Commands:
          info
          render --path PATH --out PNG [--out-f32 FILE] [--long-edge N]
                 [--density D] [--grade G]
                 [--shadow-density D] [--highlight-density D]
                 [--shadow-grade G] [--highlight-grade G]
                 [--wb-cyan C] [--wb-magenta M] [--wb-yellow Y]
                 [--crop-preview-full]
                 [--config-json FILE]
          decode --path PATH --out-f32 FILE
          detect --path PATH
          oetf-ramp --out-dir DIR [--width N] [--height N]
          serve --stdio

        S8: Lab defaults (sat / sharpen 0.25 / skin 0.5). serve --stdio speaks the Python NDJSON contract.
        """
        print(text)
    }

    private static func runInfo() throws {
        let payload = NativePipeline().infoJSON()
        try writeJSON(payload)
    }

    private static func runRender(_ args: [String]) throws {
        let parsed = try parseRender(args)
        var config = PrintConfig.s4aPin
        if let jsonPath = parsed.configJSON {
            let data = try Data(contentsOf: URL(fileURLWithPath: jsonPath))
            let obj = try JSONSerialization.jsonObject(with: data)
            guard let dict = obj as? [String: Any] else {
                throw CLIError.usage("--config-json must be a JSON object")
            }
            config = config.merging(dict)
        }
        if let density = parsed.density { config.density = density }
        if let grade = parsed.grade { config.grade = grade }
        if let v = parsed.shadowDensity { config.shadowDensity = v }
        if let v = parsed.highlightDensity { config.highlightDensity = v }
        if let v = parsed.shadowGrade { config.shadowGrade = v }
        if let v = parsed.highlightGrade { config.highlightGrade = v }
        if let v = parsed.wbCyan { config.wbCyan = v }
        if let v = parsed.wbMagenta { config.wbMagenta = v }
        if let v = parsed.wbYellow { config.wbYellow = v }
        if parsed.cropPreviewFull { config.applyPixelCrop = false }
        guard let path = parsed.path, let out = parsed.out else {
            throw CLIError.usage("render requires --path and --out")
        }
        let pipeline = NativePipeline()
        let (width, height) = try pipeline.renderPNG(
            path: path,
            longEdgePx: parsed.longEdge,
            config: config,
            to: URL(fileURLWithPath: out)
        )
        if let outF32 = parsed.outF32 {
            _ = try pipeline.writePrintF32(
                path: path,
                longEdgePx: parsed.longEdge,
                config: config,
                to: URL(fileURLWithPath: outF32)
            )
        }
        try writeJSON([
            "width": width,
            "height": height,
            "out": out,
            "print": true,
        ])
    }

    private static func runDecode(_ args: [String]) throws {
        var path: String?
        var outF32: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--path":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--path") }
                path = args[i]
            case "--out-f32":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out-f32") }
                outF32 = args[i]
            default:
                throw CLIError.unknownFlag(args[i])
            }
            i += 1
        }
        guard let path, let outF32 else {
            throw CLIError.usage("decode requires --path and --out-f32")
        }
        let (width, height) = try NativePipeline().writeLinearF32(
            path: path,
            to: URL(fileURLWithPath: outF32)
        )
        try writeJSON([
            "width": width,
            "height": height,
            "out": outF32,
        ])
    }

    private static func runDetect(_ args: [String]) throws {
        var path: String?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--path":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--path") }
                path = args[i]
            default:
                throw CLIError.unknownFlag(args[i])
            }
            i += 1
        }
        guard let path else {
            throw CLIError.usage("detect requires --path")
        }
        let mode = try NativePipeline().detectProcessMode(path: path)
        try writeJSON([
            "skipped": false,
            "detected_mode": mode.rawValue,
            "process_mode": mode.liteMode.rawValue,
        ])
    }

    private static func runServe(_ args: [String]) throws {
        guard args.contains("--stdio") else {
            throw CLIError.usage("serve requires --stdio")
        }
        ProtocolServer().serveStdio()
    }

    private static func runOETFRamp(_ args: [String]) throws {
        var outDir: String?
        var width = 512
        var height = 64
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--out-dir":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out-dir") }
                outDir = args[i]
            case "--width":
                i += 1
                guard i < args.count, let value = Int(args[i]), value > 0 else {
                    throw CLIError.missingValue("--width")
                }
                width = value
            case "--height":
                i += 1
                guard i < args.count, let value = Int(args[i]), value > 0 else {
                    throw CLIError.missingValue("--height")
                }
                height = value
            default:
                throw CLIError.unknownFlag(args[i])
            }
            i += 1
        }
        guard let outDir else {
            throw CLIError.usage("oetf-ramp requires --out-dir")
        }
        let directory = URL(fileURLWithPath: outDir, isDirectory: true)
        try NativePipeline().writeOETFRampPNGs(to: directory, width: width, height: height)
        try writeJSON([
            "linear": directory.appendingPathComponent("oetf-linear.png").path,
            "encoded": directory.appendingPathComponent("oetf-encoded.png").path,
            "width": width,
            "height": height,
        ])
    }

    private static func parseRender(_ args: [String]) throws -> RenderArgs {
        var parsed = RenderArgs()
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--path":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--path") }
                parsed.path = args[i]
            case "--out":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out") }
                parsed.out = args[i]
            case "--out-f32":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out-f32") }
                parsed.outF32 = args[i]
            case "--long-edge":
                i += 1
                guard i < args.count, let value = Int(args[i]) else {
                    throw CLIError.missingValue("--long-edge")
                }
                parsed.longEdge = value
            case "--density":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--density")
                }
                parsed.density = value
            case "--grade":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--grade")
                }
                parsed.grade = value
            case "--shadow-density":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--shadow-density")
                }
                parsed.shadowDensity = value
            case "--highlight-density":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--highlight-density")
                }
                parsed.highlightDensity = value
            case "--shadow-grade":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--shadow-grade")
                }
                parsed.shadowGrade = value
            case "--highlight-grade":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--highlight-grade")
                }
                parsed.highlightGrade = value
            case "--wb-cyan":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--wb-cyan")
                }
                parsed.wbCyan = value
            case "--wb-magenta":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--wb-magenta")
                }
                parsed.wbMagenta = value
            case "--wb-yellow":
                i += 1
                guard i < args.count, let value = Float(args[i]) else {
                    throw CLIError.missingValue("--wb-yellow")
                }
                parsed.wbYellow = value
            case "--crop-preview-full":
                parsed.cropPreviewFull = true
            case "--config-json":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--config-json") }
                parsed.configJSON = args[i]
            default:
                throw CLIError.unknownFlag(args[i])
            }
            i += 1
        }
        guard parsed.path != nil, parsed.out != nil else {
            throw CLIError.usage("render requires --path and --out")
        }
        return parsed
    }

    private struct RenderArgs {
        var path: String?
        var out: String?
        var outF32: String?
        var longEdge: Int?
        var density: Float?
        var grade: Float?
        var shadowDensity: Float?
        var highlightDensity: Float?
        var shadowGrade: Float?
        var highlightGrade: Float?
        var wbCyan: Float?
        var wbMagenta: Float?
        var wbYellow: Float?
        var cropPreviewFull = false
        var configJSON: String?
    }

    private static func parsePathOut(_ args: [String]) throws -> (path: String, out: String, longEdge: Int?) {
        var path: String?
        var out: String?
        var longEdge: Int?
        var i = 0
        while i < args.count {
            switch args[i] {
            case "--path":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--path") }
                path = args[i]
            case "--out":
                i += 1
                guard i < args.count else { throw CLIError.missingValue("--out") }
                out = args[i]
            case "--long-edge":
                i += 1
                guard i < args.count, let value = Int(args[i]) else {
                    throw CLIError.missingValue("--long-edge")
                }
                longEdge = value
            default:
                throw CLIError.unknownFlag(args[i])
            }
            i += 1
        }
        guard let path, let out else {
            throw CLIError.usage("render requires --path and --out")
        }
        return (path, out, longEdge)
    }

    private static func writeJSON(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}

enum CLIError: Error, LocalizedError {
    case missingValue(String)
    case unknownFlag(String)
    case usage(String)

    var errorDescription: String? {
        switch self {
        case let .missingValue(flag):
            "Missing value for \(flag)"
        case let .unknownFlag(flag):
            "Unknown flag: \(flag)"
        case let .usage(message):
            message
        }
    }
}
