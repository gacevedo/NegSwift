//
//  NegSwiftApp.swift
//  NegSwift
//

import SwiftUI

@main
struct NegSwiftApp: App {
    @State private var engineSession = EngineSession()

    var body: some Scene {
        WindowGroup {
            ContentView(engineSession: engineSession)
                .task {
                    await engineSession.start()
                }
        }
    }
}
