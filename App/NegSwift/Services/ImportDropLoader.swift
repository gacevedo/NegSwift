//
//  ImportDropLoader.swift
//  NegSwift
//

import Foundation
import UniformTypeIdentifiers

enum ImportDropLoader {
    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var collected: [URL] = []
        for provider in providers {
            if let url = await url(from: provider) {
                collected.append(url)
            }
        }
        return collected
    }

    private static func url(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
