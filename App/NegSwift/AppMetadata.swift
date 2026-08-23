//
//  AppMetadata.swift
//  NegSwift
//

import AppKit
import Foundation

enum AppMetadata {
    static let authorName = "Gabriel Acevedo"
    static let authorURL = URL(string: "https://gabrielacevedo.com")!
    static let negSwiftSourceURL = URL(string: "https://github.com/gacevedo/NegSwift")!
    static let negPySourceURL = URL(string: "https://github.com/marcinz606/NegPy")!

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Asset-catalog icons populate ``AppIcon.icns`` in the bundle but not ``NSApp/applicationIconImage``.
    static var appIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url),
           image.isValid
        {
            return image
        }
        if let image = NSImage(named: "AppIcon"), image.isValid {
            return image
        }
        let workspaceIcon = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        if workspaceIcon.isValid {
            return workspaceIcon
        }
        return NSApp?.applicationIconImage
    }

    static func syncApplicationIcon() {
        guard let app = NSApp else { return }
        guard app.applicationIconImage == nil, let icon = appIcon else { return }
        app.applicationIconImage = icon
    }

    static var copyrightLine: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © 2026 Gabriel Acevedo."
    }

    static func legalFileURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Legal")
            ?? Bundle.main.url(forResource: name, withExtension: nil)
    }
}
