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
        Group {
            if appState.vaultSelected {
                VaultView()
            } else {
                LandingView()
            }
        }
        .onAppear {
            Task {
                await appState.attemptAutoLogin()
            }
        }
    }
}
