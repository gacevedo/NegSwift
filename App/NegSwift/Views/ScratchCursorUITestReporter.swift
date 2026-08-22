//
//  ScratchCursorUITestReporter.swift
//  NegSwift
//

import SwiftUI

@MainActor
enum ScratchCursorUITestReporter {
    static let notification = Notification.Name("negSwift.scratchSystemCursorVisibilityChanged")

    static func setSystemCursorHidden(_ hidden: Bool) {
        guard UITestSupport.isActive else { return }
        NotificationCenter.default.post(
            name: notification,
            object: nil,
            userInfo: ["hidden": hidden]
        )
    }
}

struct ScratchCursorUITestReporterView: View {
    @State private var systemCursorHidden = false

    var body: some View {
        Text(systemCursorHidden ? "hidden" : "visible")
            .accessibilityIdentifier("negSwift.scratchSystemCursor")
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .onReceive(NotificationCenter.default.publisher(for: ScratchCursorUITestReporter.notification)) { notification in
                systemCursorHidden = notification.userInfo?["hidden"] as? Bool ?? false
            }
    }
}
