//
//  ScanFrame.swift
//  NegSwift
//

import AppKit
import Foundation

struct ScanFrame: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let path: String
    let name: String
    var thumbnail: NSImage?
    var isLoadingThumbnail = false
    /// True when ``thumbnail`` is from a settled print (disk cache, canvas, or memo), not the cheap strip path.
    var hasProcessedThumbnail = false

    static func == (lhs: ScanFrame, rhs: ScanFrame) -> Bool {
        lhs.id == rhs.id
    }
}

enum FilmStripLayout {
    static let thumbnailLongEdge = 256
}
