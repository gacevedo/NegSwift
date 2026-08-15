//
//  NegSwiftApp.swift
//  NegSwift
//

import SwiftUI

@main
struct NegSwiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var engineSession = EngineSession()
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView(engineSession: engineSession)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    await engineSession.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await engineSession.flushPendingSaves() }
                    }
                }
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NegSwift") {
                    showAbout = true
                }
            }
        }
    }
}
