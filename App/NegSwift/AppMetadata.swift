//
//  AppMetadata.swift
//  NegSwift
//

import Foundation

enum AppMetadata {
    static let authorName = "Gabriel Acevedo"
    static let authorURL = URL(string: "https://gabrielacevedo.com")!
    static let negSwiftSourceURL = URL(string: "https://github.com/gacevedo/NegSwift")!
    static let negPySourceURL = URL(string: "https://github.com/marcinz606/NegPy")!

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    static var copyrightLine: String {
        Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
            ?? "Copyright © 2026 Gabriel Acevedo. Licensed under GPL-3.0."
    }

    static func legalFileURL(named name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Legal")
            ?? Bundle.main.url(forResource: name, withExtension: nil)
    }
}
