//
//  RootView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OpalEditorDemo") {
            EditorDemoView()
        } else {
            content
        }
        #else
        content
        #endif
    }

    private var content: some View {
        Group {
            if let vault = appState.vault {
                VaultView(vault: vault)
                    .id(vault.root)
            } else if let store = appState.store {
                NavigationStack {
                    SelectVaultView(store: store, path: "")
                }
            } else {
                LandingView()
            }
        }
        .task {
            await appState.reconnect()
        }
    }
}
