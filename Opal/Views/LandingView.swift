//
//  LandingView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct LandingView: View {
    @EnvironmentObject var appState: AppState
    @State private var showConnectSheet = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to Opal")
                .font(.largeTitle)

            if let settings = appState.settings {
                switch appState.status {
                case .connecting:
                    ProgressView("Connecting to \(settings.title)…")
                case .failed(let message):
                    VStack(spacing: 12) {
                        Label("Couldn't connect to \(settings.title)", systemImage: "exclamationmark.triangle")
                            .font(.headline)
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Try Again") {
                            Task { await appState.reconnect() }
                        }
                        .buttonStyle(.bordered)
                    }
                case .disconnected, .connected:
                    Button("Reconnect to \(settings.title)") {
                        Task { await appState.reconnect() }
                    }
                    .buttonStyle(.bordered)
                }
            }

            Button("Connect to Server") {
                showConnectSheet = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.status == .connecting)
        }
        .padding()
        .sheet(isPresented: $showConnectSheet) {
            ConnectToServerView()
                .interactiveDismissDisabled(true)
        }
    }
}

#Preview {
    LandingView()
        .environmentObject(AppState())
}
