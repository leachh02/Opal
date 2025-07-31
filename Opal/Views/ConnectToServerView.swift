//
//  ConnectToServerView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI
import SMBClient

struct ConnectToServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject var model = ServerDiscoveryModel()
    @StateObject private var connectionService = SMBConnectionService()
    @State private var displayName = ""
    @State private var host = ""
    @State private var port = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistered = false
    @State private var selectedServer: Server?
    @State private var showVaultPicker = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection Form
                Form {
                    Section("Server Details") {
                        HStack {
                            Text("Display Name")
                                .foregroundColor(.primary)
                            TextField("Optional", text: $displayName)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Host")
                                .foregroundColor(.primary)
                            TextField("e.g. 192.168.1.5", text: $host)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Share")
                                .foregroundColor(.primary)
                            TextField("Required", text: $share)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("Port")
                                .foregroundColor(.primary)
                            TextField("Optional", text: $port)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                        }
                    }
                    
                    Section("Connect as") {
                        Picker("Connection Type", selection: $isRegistered) {
                                Text("Guest").tag(false)
                                Text("Registered User").tag(true)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    
                    if isRegistered{
                        Section("Credentials") {
                            HStack {
                                Text("Username")
                                    .foregroundColor(.primary)
                                TextField("Required", text: $username)
                                    .multilineTextAlignment(.trailing)
                            }
                            HStack {
                                Text("Password")
                                    .foregroundColor(.primary)
                                SecureField("Optional", text: $password)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    
                    List {
                        if !model.discovered.isEmpty {
                            Section("Discovered Servers") {
                                ForEach(model.discovered.sorted(by: { $0.name < $1.name }), id: \.self) { service in
                                    Button(service.name) {
                                        self.host = service.name
                                    }
                                }
                            }
                        }
                        
                        if !model.saved.isEmpty {
                            Section("Saved Servers") {
                                ForEach(model.saved, id: \.id) { server in
                                    Button(server.displayName) {
                                        selectedServer = server
                                        displayName = server.displayName
                                        host = server.server
                                    }
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: isRegistered)
            }
            .navigationTitle("Connect to Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing){
                    Button("Connect") {
                        Task {
                            appState.displayName = displayName.isEmpty ? nil : displayName
                            appState.host = host
                            appState.share = share
                            appState.port = port.isEmpty ? nil : port
                            appState.username = username
                            appState.password = password
                            await appState.connect(isRegistered: isRegistered)
                                
                            if appState.isLoggedIn {
                                let id = ID(UUID().uuidString)
                                ServerManager.shared.addServer(id: id, displayName: displayName, server: host, port: nil)
                                showVaultPicker = true
                            } else {
                                // Handle connection failure
                                errorMessage = connectionService.error ?? "Failed to connect to server. Please check your credentials and network connection."
                                showErrorAlert = true
                            }
                        }
                    }
                    .disabled(host.isEmpty || share.isEmpty || isRegistered && username.isEmpty)
                }
            }
            .alert("Connection Error", isPresented: $showErrorAlert) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .navigationDestination(isPresented: $showVaultPicker) {
                if let accessor = appState.treeAccessor {
                    SelectVaultView(treeAccessor: accessor, path: "")
                } else {
                    EmptyView()
                }
            }
        }
    }
}
    
#Preview {
    ConnectToServerView()
}



