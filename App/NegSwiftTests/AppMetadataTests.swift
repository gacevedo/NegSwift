//
//  AppMetadataTests.swift
//  NegSwiftTests
//

import Foundation
import Testing
@testable import NegSwift

struct AppMetadataTests {
    @Test func appVersionIsNonEmpty() {
        #expect(!AppMetadata.appVersion.isEmpty)
    }

    @Test @MainActor func appIconLoadsFromHostBundle() {
        #expect(AppMetadata.appIcon != nil)
    }

    @Test @MainActor func syncApplicationIconIsSafeWhenAlreadySet() {
        AppMetadata.syncApplicationIcon()
        #expect(AppMetadata.appIcon != nil)
    }
}
