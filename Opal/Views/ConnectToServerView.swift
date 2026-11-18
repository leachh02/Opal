//
//  ConnectToServerView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct ConnectToServerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState
    @StateObject var model = ServerDiscoveryModel()
    @State private var displayName = ""
    @State private var host = ""
    @State private var port = ""
    @State private var share = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isRegistered = false
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Server Details") {
                    field("Display Name", "Optional", text: $displayName)
                    field("Host", "e.g. 192.168.1.5", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    field("Share", "Required", text: $share)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    field("Port", "Optional", text: $port)
                        .keyboardType(.numberPad)
                }

                Section("Connect as") {
                    Picker("Connection Type", selection: $isRegistered) {
                        Text("Guest").tag(false)
                        Text("Registered User").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                if isRegistered {
                    Section("Credentials") {
                        field("Username", "Required", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                        HStack {
                            Text("Password")
                            SecureField("Optional", text: $password)
                                .multilineTextAlignment(.trailing)
                                .textContentType(.password)
                        }
                    }
                }

                if !model.saved.isEmpty {
                    Section("Saved Servers") {
                        ForEach(model.saved, id: \.id) { server in
                            Button {
                                fill(from: server)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(server.displayName)
                                    if let share = server.share {
                                        Text("\(server.server)/\(share)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .swipeActions {
                                Button("Remove", role: .destructive) {
                                    forget(server)
                                }
                            }
                        }
                    }
                }

                if !model.discovered.isEmpty {
                    Section("Discovered Servers") {
                        ForEach(model.discovered.sorted(by: { $0.name < $1.name }), id: \.self) { service in
                            Button(service.name) {
                                host = service.name
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isRegistered)
            .disabled(isConnecting)
            .navigationTitle("Connect to Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isConnecting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isConnecting {
                        ProgressView()
                    } else {
                        Button("Connect") {
                            Task { await connect() }
                        }
                        .disabled(!canConnect)
                    }
                }
            }
            .alert("Couldn't Connect", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if host.isEmpty, let settings = appState.settings {
                    fill(from: settings)
                }
            }
        }
    }

    private var trimmedHost: String { host.trimmingCharacters(in: .whitespaces) }
    private var trimmedShare: String { share.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
    private var portIsValid: Bool { port.isEmpty || Int(port).map { (1...65535).contains($0) } == true }

    private var canConnect: Bool {
        !trimmedHost.isEmpty && !trimmedShare.isEmpty && portIsValid && (!isRegistered || !username.isEmpty)
    }

    private func connect() async {
        let settings = ConnectionSettings(
            displayName: displayName.isEmpty ? nil : displayName,
            host: trimmedHost,
            port: Int(port),
            share: trimmedShare,
            username: isRegistered ? username : ""
        )
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await appState.connect(settings, password: isRegistered ? password : "")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fill(from settings: ConnectionSettings) {
        displayName = settings.displayName ?? ""
        host = settings.host
        port = settings.port.map(String.init) ?? ""
        share = settings.share
        username = settings.username
        isRegistered = !settings.isGuest
        password = savedPassword(host: settings.host, share: settings.share)
    }

    private func fill(from server: Server) {
        displayName = server.displayName == server.server ? "" : server.displayName
        host = server.server
        port = server.port.map(String.init) ?? ""
        share = server.share ?? ""
        username = server.username ?? ""
        isRegistered = server.username != nil
        password = savedPassword(host: server.server, share: share)
    }

    /// Removes a saved server, and clears the form if it was showing that server.
    private func forget(_ server: Server) {
        if trimmedHost == server.server && Int(port) == server.port && trimmedShare == server.share {
            displayName = ""
            host = ""
            port = ""
            share = ""
            username = ""
            password = ""
            isRegistered = false
        }
        appState.forget(server)
    }

    private func savedPassword(host: String, share: String) -> String {
        guard !share.isEmpty else { return "" }
        return CredentialStore.shared.load(server: host, securityDomain: share)?.password ?? ""
    }

    private func field(_ label: String, _ prompt: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            TextField(prompt, text: text)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    ConnectToServerView()
        .environmentObject(AppState())
}
