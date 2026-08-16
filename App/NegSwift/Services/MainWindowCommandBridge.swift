//
//  MainWindowCommandBridge.swift
//  NegSwift
//

import Foundation
import Observation

@Observable
@MainActor
final class MainWindowCommandBridge {
    var canOpenImport = false
    var canOpenExport = false
    var canToggleCanvasZoom = false

    var openImport: (() -> Void)?
    var openExport: (() -> Void)?
    var toggleCanvasZoom: (() -> Void)?

    func performOpenImport() {
        openImport?()
    }

    func performOpenExport() {
        openExport?()
    }

    func performToggleCanvasZoom() {
        toggleCanvasZoom?()
    }
}
