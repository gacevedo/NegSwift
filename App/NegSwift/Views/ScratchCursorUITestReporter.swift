//
//  ScratchCursorUITestReporter.swift
//  NegSwift
//

import SwiftUI

struct ScratchCursorUITestReporterView: View {
    @State private var systemCursorHidden = false

    var body: some View {
        Text(systemCursorHidden ? "hidden" : "visible")
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(systemCursorHidden ? "hidden" : "visible")
            .accessibilityIdentifier("negSwift.scratchSystemCursor")
            .onReceive(NotificationCenter.default.publisher(for: UITestSupport.scratchSystemCursorVisibilityChanged)) { notification in
                systemCursorHidden = notification.userInfo?["hidden"] as? Bool ?? false
            }
    }
}

struct CanvasZoomUITestReporterView: View {
    @State private var label = "Fit"

    var body: some View {
        Text(label)
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityIdentifier("negSwift.canvasZoomLabel")
            .onReceive(NotificationCenter.default.publisher(for: UITestSupport.canvasZoomLabelChanged)) { notification in
                label = notification.userInfo?["label"] as? String ?? label
            }
    }
}
