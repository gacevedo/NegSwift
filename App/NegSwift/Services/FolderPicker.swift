//
//  FolderPicker.swift
//  NegSwift
//

import AppKit
import Foundation

enum FolderPicker {
    /// Folder chooser via ``NSOpenPanel`` — reliable on macOS; SwiftUI ``fileImporter`` often fails for folders.
    @MainActor
    static func chooseFolder(prompt: String = "Choose Folder") async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = prompt
            panel.prompt = prompt
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }
}
