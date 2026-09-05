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
          render --path PATH --out PNG [--long-edge N]
          decode --path PATH --out-f32 FILE
          detect --path PATH

        S1: render shows unprocessed linear pixels (orange mask still orange).
        """
        print(text)
    }

    private static func runInfo() throws {
        let payload = NativePipeline().infoJSON()
        try writeJSON(payload)
    }

    private static func runRender(_ args: [String]) throws {
        let parsed = try parsePathOut(args)
        let (width, height) = try NativePipeline().renderPNG(
            path: parsed.path,
            longEdgePx: parsed.longEdge,
            to: URL(fileURLWithPath: parsed.out)
        )
        try writeJSON([
            "width": width,
            "height": height,
            "out": parsed.out,
            "linear": true,
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
