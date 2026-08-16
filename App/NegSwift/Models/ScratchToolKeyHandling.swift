//
//  ScratchToolKeyHandling.swift
//  NegSwift
//

import Foundation

enum ScratchToolKeyAction: Equatable {
    case finish
    case backspace
    case escape
}

enum ScratchToolKeyHandling {
    /// macOS key codes for scratch-tool shortcuts (Return, keypad Enter, Delete, Esc).
    static func action(forKeyCode keyCode: UInt16) -> ScratchToolKeyAction? {
        switch keyCode {
        case 36, 76:
            return .finish
        case 51:
            return .backspace
        case 53:
            return .escape
        default:
            return nil
        }
    }
}
