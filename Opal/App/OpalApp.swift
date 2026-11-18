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

    init() {
        // Unless kept in Settings, downloaded images and files only last until the app is next opened.
        if StoragePreferences.clearsDownloadsOnLaunch() {
            FileCache.clearAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
