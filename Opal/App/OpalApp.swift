//
//  OpalApp.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//

import SwiftUI

@main
struct OpalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
