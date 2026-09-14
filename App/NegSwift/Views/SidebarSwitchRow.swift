//
//  SidebarSwitchRow.swift
//  NegSwift
//

import SwiftUI

/// Compact switch row for the sidebar. A bare `Toggle` outside `Form` renders oversized on macOS.
struct SidebarSwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var help: String?
    var accessibilityIdentifier: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
            switchControl
        }
        .modifier(OptionalHelp(help: help))
    }

    @ViewBuilder
    private var switchControl: some View {
        if let accessibilityIdentifier {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .accessibilityIdentifier(accessibilityIdentifier)
        } else {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }
}

private struct OptionalHelp: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}
