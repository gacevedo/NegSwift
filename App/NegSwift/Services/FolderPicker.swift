//
//  FolderPicker.swift
//  NegSwift
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum FolderPicker {
    private static let scanTypes: [UTType] = [.tiff, .png, .jpeg, .heic, .rawImage]

    @MainActor
    static func chooseFolder(
        prompt: String = "Choose Folder",
        recentKind: RecentPathKind
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = prompt
            panel.prompt = prompt
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            if let start = RecentPathsStore.directoryURL(for: recentKind) {
                panel.directoryURL = start
            }
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                RecentPathsStore.remember(url, for: recentKind)
                continuation.resume(returning: url)
            }
        }
    }

    @MainActor
    static func chooseScanFile(prompt: String = "Open Scan") async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.title = prompt
            panel.prompt = prompt
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.allowedContentTypes = scanTypes
            if let start = RecentPathsStore.directoryURL(for: .openFileDirectory) {
                panel.directoryURL = start
            }
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    continuation.resume(returning: nil)
                    return
                }
                RecentPathsStore.remember(url, for: .openFileDirectory)
                continuation.resume(returning: url)
            }
        }
    }
}
