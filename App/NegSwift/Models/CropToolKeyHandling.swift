//
//  CropToolKeyHandling.swift
//  NegSwift
//

import Foundation

enum CropToolKeyHandling {
    /// macOS key codes for applying the crop (Return, keypad Enter).
    static func isApplyKey(_ keyCode: UInt16) -> Bool {
        keyCode == 36 || keyCode == 76
    }
}
