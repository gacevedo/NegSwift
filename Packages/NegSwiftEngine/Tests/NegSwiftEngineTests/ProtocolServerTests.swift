import Foundation
import Testing
@testable import NegSwiftEngine

struct ProtocolServerTests {
    @Test func pingAndInfo() throws {
        let server = ProtocolServer()
        let ping = server.handleMessage(#"{"id":"p1","method":"ping","params":{}}"#)
        #expect(ping["ok"] as? Bool == true)
        let result = ping["result"] as? [String: Any]
        #expect(result?["pong"] as? Bool == true)

        let info = server.handleMessage(#"{"id":1,"method":"info"}"#)
        let payload = info["result"] as? [String: Any]
        #expect(payload?["protocol_version"] as? String == "0.1")
        #expect(payload?["negpy_version"] as? String == "s10b-optical-dust")
        #expect(info["id"] as? Int == 1 || (info["id"] as? NSNumber)?.intValue == 1)
    }

    @Test func unknownMethodAndBadJSON() {
        let server = ProtocolServer()
        let unknown = server.handleMessage(#"{"id":"bad-1","method":"not_a_method"}"#)
        #expect(unknown["ok"] as? Bool == false)
        let error = unknown["error"] as? [String: Any]
        #expect(error?["code"] as? String == "INVALID_REQUEST")

        let malformed = server.handleMessage("{")
        #expect(malformed["ok"] as? Bool == false)
    }

    @Test func loadSaveResetViaProtocol() throws {
        let frame = try writeProtocolTIFF()
        defer {
            try? FileManager.default.removeItem(at: frame)
            try? FileManager.default.removeItem(at: SidecarStore.url(forScanPath: frame.path))
        }
        let server = ProtocolServer()
        let load = server.handleMessage(
            #"{"id":"load-1","method":"load_config","params":{"path":"\#(frame.path)"}}"#
        )
        let loaded = (load["result"] as? [String: Any])?["config"] as? [String: Any]
        #expect((load["result"] as? [String: Any])?["has_sidecar"] as? Bool == false)
        #expect((loaded?["grade"] as? NSNumber)?.doubleValue == 100)

        let saveLine = """
        {"id":"save-1","method":"save_config","params":{"path":"\(frame.path)","config":{"density":1.25,"wb_cyan":0.1}}}
        """
        let save = server.handleMessage(saveLine)
        #expect(save["ok"] as? Bool == true)
        let sidecar = (save["result"] as? [String: Any])?["sidecar_path"] as? String
        #expect(sidecar?.hasSuffix(".negpy") == true)

        let reload = server.handleMessage(
            #"{"id":"load-2","method":"load_config","params":{"path":"\#(frame.path)"}}"#
        )
        let config = (reload["result"] as? [String: Any])?["config"] as? [String: Any]
        #expect((config?["density"] as? NSNumber)?.doubleValue == 1.25)
        #expect((config?["wb_cyan"] as? NSNumber)?.doubleValue == 0.1)

        let reset = server.handleMessage(
            #"{"id":"reset-1","method":"reset_config","params":{"path":"\#(frame.path)"}}"#
        )
        #expect((reset["result"] as? [String: Any])?["sidecar_removed"] as? Bool == true)
    }

    @Test func renderMissingFileIsNotFound() {
        let server = ProtocolServer()
        let msg = server.handleMessage(
            #"{"id":"render-missing","method":"render","params":{"path":"/no/such/scan.tif"}}"#
        )
        #expect(msg["ok"] as? Bool == false)
        #expect((msg["error"] as? [String: Any])?["code"] as? String == "NOT_FOUND")
    }

    @Test func renderRejectsInvalidPreviewFormat() throws {
        let frame = try writeProtocolTIFF()
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let msg = server.handleMessage(
            #"{"id":"bad-fmt","method":"render","params":{"path":"\#(frame.path)","preview_format":"webp"}}"#
        )
        #expect((msg["error"] as? [String: Any])?["code"] as? String == "INVALID_REQUEST")
    }

    @Test func openReportsDimensions() throws {
        let frame = try writeProtocolTIFF()
        defer { try? FileManager.default.removeItem(at: frame) }
        let server = ProtocolServer()
        let msg = server.handleMessage(
            #"{"id":"open-1","method":"open","params":{"path":"\#(frame.path)"}}"#
        )
        let result = msg["result"] as? [String: Any]
        #expect(result?["width"] as? Int == 8 || (result?["width"] as? NSNumber)?.intValue == 8)
        #expect(result?["height"] as? Int == 8 || (result?["height"] as? NSNumber)?.intValue == 8)
        #expect(result?["has_sidecar"] as? Bool == false)
    }
}

func writeProtocolTIFF() throws -> URL {
    let samples = [UInt16](repeating: 40_000, count: 8 * 8 * 3)
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("negswift-s7-proto-\(UUID().uuidString).tif")
    try UncompressedTIFF.writeRGB16(width: 8, height: 8, samples: samples, to: url)
    return url
}
