//
//  ScratchCursor.swift
//  NegSwift
//

import AppKit

enum ScratchCursor {
    private static var isCrosshair = false

    static func setCrosshair(_ enabled: Bool) {
        guard enabled != isCrosshair else { return }
        isCrosshair = enabled
        (enabled ? NSCursor.crosshair : NSCursor.arrow).set()
    }

    static func reset() {
        NSCursor.unhide()
        UITestSupport.reportScratchSystemCursorHidden(false)
        guard isCrosshair else { return }
        isCrosshair = false
        NSCursor.arrow.set()
    }
}
