//
//  ConnectToServerView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI
import SMBClient

struct ConnectToServerView: View {    
    @StateObject var model = ServerDiscoveryModel()
    @StateObject private var connectionService = SMBConnectionService()
    @State private var manualHost = ""
    @State private var port: String = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var selectedServer: Server?
    @State private var showVaultPicker = false

    var body: some View {
        VStack(spacing: 20) {
            List {
                if !model.discovered.isEmpty {
                    Section(header: Text("Discovered Servers")) {
                        ForEach(model.discovered.sorted(by: { $0.name < $1.name }), id: \.self) { service in
                            Button(service.name) {
                                self.manualHost = service.name
                            }
                        }
                    }
                }

                if !model.saved.isEmpty {
                    Section(header: Text("Saved Servers")) {
                        ForEach(model.saved, id: \.id) { server in
                            Button(server.displayName) {
                                selectedServer = server
                                manualHost = server.server
//                                username = server.username ?? ""
//                                password = server.password ?? ""
                            }
                        }
                    }
                }
            }

            Divider()

            Form {
                TextField("Host (e.g. 192.168.1.5)", text: $manualHost)
                TextField("Share", text: $share)
                TextField("Port (optional)", text: $port)
                    .keyboardType(.numberPad)
                
                TextField("Username", text: $username)
                SecureField("Password", text: $password)

                Button("Connect & Continue") {
                    Task {
                        await connectionService.connect(
                            host: manualHost,
                            port: nil,
                            username: username,
                            password: password,
                            share: share
                        )

                        if connectionService.isConnected {
                            let id = ID(UUID().uuidString)
                            ServerManager.shared.addServer(id: id, displayName: manualHost, server: manualHost, port: nil)
                            showVaultPicker = true
                        }
                    }
                }
                .disabled(manualHost.isEmpty || username.isEmpty || password.isEmpty || share.isEmpty)
            }
            .padding()

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
        }
        .navigationTitle("Connect to Server")
    }
}
