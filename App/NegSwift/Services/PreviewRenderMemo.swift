//
//  PreviewRenderMemo.swift
//  NegSwift
//

import AppKit
import CryptoKit
import Foundation

/// Last displayed canvas preview per scan path — instant navigate-back when edits match.
struct PreviewRenderMemo {
    struct Entry {
        let fingerprint: String
        let image: NSImage
        let pixelSize: CGSize
    }

    private var entries: [String: Entry] = [:]
    private var order: [String] = []
    private let maxEntries: Int

    init(maxEntries: Int = 8) {
        self.maxEntries = max(2, maxEntries)
    }

    mutating func get(path: String, fingerprint: String) -> Entry? {
        guard let entry = entries[path], entry.fingerprint == fingerprint else { return nil }
        if let index = order.firstIndex(of: path) {
            order.remove(at: index)
            order.append(path)
        }
        return entry
    }

    mutating func store(path: String, fingerprint: String, image: NSImage, pixelSize: CGSize) {
        guard !path.isEmpty, !fingerprint.isEmpty else { return }
        entries[path] = Entry(fingerprint: fingerprint, image: image, pixelSize: pixelSize)
        if let index = order.firstIndex(of: path) {
            order.remove(at: index)
        }
        order.append(path)
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            entries.removeValue(forKey: evicted)
        }
    }

    mutating func invalidate(path: String) {
        entries.removeValue(forKey: path)
        order.removeAll { $0 == path }
    }

    mutating func clear() {
        entries.removeAll()
        order.removeAll()
    }
}

enum PreviewMemoFingerprint {
    static func make(
        pipelineConfig: FrameEditState,
        settings: PreviewRenderSettings,
        cropPreviewFull: Bool
    ) -> String {
        struct Identity: Encodable {
            let config: FrameEditState
            let longEdgePx: Int
            let preferGPU: Bool
            let cropPreviewFull: Bool
        }
        let identity = Identity(
            config: pipelineConfig,
            longEdgePx: settings.longEdgePx,
            preferGPU: settings.preferGPU,
            cropPreviewFull: cropPreviewFull
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(identity) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
