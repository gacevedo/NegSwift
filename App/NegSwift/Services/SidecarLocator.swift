//
//  SidecarLocator.swift
//  NegSwift
//

import Foundation

/// NegPy edit sidecar path: ``<basename>.negpy`` beside the scan file.
enum SidecarLocator {
    static func url(forScanPath path: String) -> URL {
        let scanURL = URL(fileURLWithPath: path)
        let baseName = scanURL.deletingPathExtension().lastPathComponent
        return scanURL.deletingLastPathComponent().appendingPathComponent("\(baseName).negpy")
    }

    static func exists(forScanPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(forScanPath: path).path)
    }
}
