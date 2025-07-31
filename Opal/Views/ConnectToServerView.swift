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
    @State private var useCustomPort = false
    
    // temp to be deleted
    var savedServers = [
        Server(id: ID(UUID().uuidString), displayName: "Synergy", server: "100.123.147.118", port: nil)
    ]

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
                    
                    // Server Lists
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
                
                
//                 Hidden NavigationLink for navigation
                NavigationLink(
                    destination: {
                        if let accessor = connectionService.treeAccessor {
                            AnyView(VaultPickerView(treeAccessor: accessor, path: ""))
                        } else {
                            AnyView(EmptyView())
                        }
                    }(),
                    isActive: $showVaultPicker
                ) {
                    EmptyView()
                }
                .hidden()
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
                            await connectionService.connect(
                                host: host,
                                port: nil,
                                username: username,
                                password: password,
                                share: share
                            )
                            
                            if connectionService.isConnected {
                                let id = ID(UUID().uuidString)
                                ServerManager.shared.addServer(id: id, displayName: displayName, server: host, port: nil)
                                showVaultPicker = true
                            }
                        }
                    }
                    .disabled(host.isEmpty || share.isEmpty || isRegistered && (username.isEmpty || password.isEmpty))
                }
            }
//            .navigationDestination(isPresented: $showVaultPicker, destination: {
//                if let accessor = connectionService.treeAccessor {
//                    AnyView(VaultPickerView(treeAccessor: accessor, path: ""))
//                }
//            }())
        }
    }
}

#Preview {
    ConnectToServerView()
}



