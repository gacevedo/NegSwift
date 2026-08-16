//
//  ImportDropTarget.swift
//  NegSwift
//

import SwiftUI
import UniformTypeIdentifiers

private struct ImportDropTargetModifier: ViewModifier {
    @Bindable var session: EngineSession
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .onDrop(of: ScanImportTypes.dropTypes, isTargeted: $isTargeted) { providers in
                guard session.engineReady else { return false }
                Task {
                    let urls = await ImportDropLoader.urls(from: providers)
                    await session.importDroppedURLs(urls)
                }
                return true
            }
            .overlay {
                if isTargeted, session.engineReady {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(10)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }
}

extension View {
    func importDropTarget(session: EngineSession, isTargeted: Binding<Bool>) -> some View {
        modifier(ImportDropTargetModifier(session: session, isTargeted: isTargeted))
    }
}
