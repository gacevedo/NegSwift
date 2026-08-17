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
    var canToggleCropTool = false
    var canToggleScratchTool = false
    var canUndoLastHeal = false

    var openImport: (() -> Void)?
    var openExport: (() -> Void)?
    var toggleCanvasZoom: (() -> Void)?
    var toggleCropTool: (() -> Void)?
    var toggleScratchTool: (() -> Void)?
    var undoLastHeal: (() -> Void)?

    func performOpenImport() {
        openImport?()
    }

    func performOpenExport() {
        openExport?()
    }

    func performToggleCanvasZoom() {
        toggleCanvasZoom?()
    }

    func performToggleCropTool() {
        toggleCropTool?()
    }

    func performToggleScratchTool() {
        toggleScratchTool?()
    }

    func performUndoLastHeal() {
        undoLastHeal?()
    }
}
