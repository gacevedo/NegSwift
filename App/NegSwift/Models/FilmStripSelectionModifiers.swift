//
//  FilmStripSelectionModifiers.swift
//  NegSwift
//

import AppKit
import Foundation

struct FilmStripSelectionModifiers: Equatable, Sendable {
    var command: Bool = false
    var shift: Bool = false

    static let plain = FilmStripSelectionModifiers()

    static func fromCurrentEvent() -> FilmStripSelectionModifiers {
        let flags = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        return FilmStripSelectionModifiers(
            command: flags.contains(.command),
            shift: flags.contains(.shift)
        )
    }
}
