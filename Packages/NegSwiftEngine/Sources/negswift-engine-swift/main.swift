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

        S0 stub: render writes a gray PNG. No look claim.
        """
        print(text)
    }

    private static func runInfo() throws {
        let payload = NativePipeline().infoJSON()
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func runRender(_ args: [String]) throws {
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
        let (width, height) = try NativePipeline().renderPNG(
            path: path,
            longEdgePx: longEdge,
            to: URL(fileURLWithPath: out)
        )
        let report: [String: Any] = [
            "width": width,
            "height": height,
            "out": out,
            "stub": true,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
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
