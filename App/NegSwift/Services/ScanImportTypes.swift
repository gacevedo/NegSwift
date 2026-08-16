//
//  ScanImportTypes.swift
//  NegSwift
//

import UniformTypeIdentifiers

enum ScanImportTypes {
    static let scanTypes: [UTType] = [.tiff, .png, .jpeg, .heic, .rawImage]

    /// Accept any file URL; folders and scans are classified after drop.
    static let dropTypes: [UTType] = [.fileURL]
}
