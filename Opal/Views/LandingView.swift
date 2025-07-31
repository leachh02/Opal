//
//  LandingView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct LandingView: View {
    @State private var showConnectSheet = false
    var body: some View {
        VStack() {
            Text("Welcome to Opal")
                .font(.largeTitle)

            Button("Connect to Server"){
                showConnectSheet = true
            }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $showConnectSheet) {
                    ConnectToServerView()
                        .interactiveDismissDisabled(true)
                }
        }
        .padding()
    }
}

#Preview {
    LandingView()
}
