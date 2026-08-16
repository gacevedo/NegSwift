//
//  SidebarSection.swift
//  NegSwift
//

import SwiftUI

struct SidebarSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }
}
