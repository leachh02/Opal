//
//  LandingView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct LandingView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Welcome to Opal")
                    .font(.largeTitle)

                NavigationLink("Connect to Server", destination: ConnectToServerView())
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
