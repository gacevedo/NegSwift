//
//  EngineSession.swift
//  NegSwift
//

import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class EngineSession {
    enum State: Equatable {
        case idle
        case starting
        case ready(EngineInfo)
        case failed(String)
        case previewUnavailable
    }

    private(set) var state: State = .idle
    private(set) var previewImage: NSImage?
    private(set) var isRenderingPreview = false
    private(set) var previewError: String?
    private(set) var currentPath: String?

    private let client = EngineClient()

    var engineReady: Bool {
        if case .ready = state { return true }
        return false
    }

    func start() async {
        if ProcessInfoPreview.isRunningForPreviews {
            state = .previewUnavailable
            return
        }
        guard case .idle = state else { return }
        state = .starting
        do {
            let info = try await client.info()
            state = .ready(info)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restart() async {
        await client.stop()
        state = .idle
        previewImage = nil
        previewError = nil
        currentPath = nil
        await start()
    }

    func stop() async {
        await client.stop()
        state = .idle
        previewImage = nil
        previewError = nil
        currentPath = nil
    }

    func noteImportError(_ message: String) {
        previewError = message
    }

    func renderFile(at url: URL) async {
        guard engineReady else { return }

        let gotAccess = url.startAccessingSecurityScopedResource()
        defer {
            if gotAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        isRenderingPreview = true
        previewError = nil
        defer { isRenderingPreview = false }

        do {
            let result = try await client.render(path: url.path)
            guard let data = result.pngData, let image = NSImage(data: data) else {
                previewError = "Engine returned an invalid PNG."
                return
            }
            previewImage = image
            currentPath = url.path
        } catch {
            previewError = error.localizedDescription
        }
    }

    #if DEBUG
    static var preview: EngineSession {
        let session = EngineSession()
        session.state = .ready(
            EngineInfo(
                protocolVersion: "0.1",
                negswiftVersion: "0.1.0",
                negpyVersion: "preview",
                python: "—",
                gpuAvailable: false,
                gpuBackend: nil
            )
        )
        return session
    }
    #endif
}
