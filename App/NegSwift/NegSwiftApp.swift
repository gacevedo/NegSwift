//
//  NegSwiftApp.swift
//  NegSwift
//

import SwiftUI

@main
struct NegSwiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var preferences = AppPreferences()
    @State private var engineSession: EngineSession
    @State private var showAbout = false

    init() {
        AppPreferencesStorage.migrateLegacyPreferencesIfNeeded()
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _engineSession = State(initialValue: EngineSession(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(engineSession: engineSession, showAbout: $showAbout)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    AppMetadata.syncApplicationIcon()
                }
                .task {
                    await engineSession.start()
                    await UITestSupport.runAutomation(session: engineSession)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        Task { await engineSession.flushPendingSaves() }
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About NegSwift") {
                    showAbout = true
                }
            }
        }
        Settings {
            PreferencesView(preferences: preferences, session: engineSession)
        }
    }
}
