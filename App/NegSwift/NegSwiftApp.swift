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
    @State private var commandBridge = MainWindowCommandBridge()

    init() {
        AppPreferencesStorage.migrateLegacyPreferencesIfNeeded()
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _engineSession = State(initialValue: EngineSession(preferences: preferences))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                engineSession: engineSession,
                showAbout: $showAbout,
                commandBridge: commandBridge
            )
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

            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    commandBridge.performOpenImport()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!commandBridge.canOpenImport)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Export…") {
                    commandBridge.performOpenExport()
                }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(!commandBridge.canOpenExport)
            }

            CommandMenu("View") {
                Button("Toggle Fit / 1:1") {
                    commandBridge.performToggleCanvasZoom()
                }
                .keyboardShortcut(.space, modifiers: [])
                .disabled(!commandBridge.canToggleCanvasZoom)

                Button("Toggle Crop Tool") {
                    commandBridge.performToggleCropTool()
                }
                .keyboardShortcut("c", modifiers: .shift)
                .disabled(!commandBridge.canToggleCropTool)

                Button("Toggle Scratch Tool") {
                    commandBridge.performToggleScratchTool()
                }
                .keyboardShortcut("s", modifiers: .shift)
                .disabled(!commandBridge.canToggleScratchTool)

                Button("Undo Last Heal") {
                    commandBridge.performUndoLastHeal()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!commandBridge.canUndoLastHeal)
            }
        }
        Settings {
            PreferencesView(preferences: preferences, session: engineSession)
        }
    }
}
