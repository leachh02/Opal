//
//  SelectVaultView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//
import SwiftUI

struct SelectVaultView: View {
    let store: any VaultStore
    let path: String

    @EnvironmentObject var appState: AppState

    @State private var folders: [VaultItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isObsidianVault = false

    var body: some View {
        List {
            if isObsidianVault {
                Section {
                    Label("This folder is an Obsidian vault", systemImage: "checkmark.seal")
                        .foregroundStyle(.tint)
                }
            }
            Section {
                ForEach(folders) { folder in
                    NavigationLink {
                        SelectVaultView(store: store, path: folder.path)
                    } label: {
                        Label(folder.name, systemImage: "folder")
                    }
                }
            } footer: {
                if !isLoading && error == nil && !isObsidianVault {
                    Text("Open a folder that contains an .obsidian folder.")
                }
            }
        }
        .navigationTitle(path.isEmpty ? "Choose Vault" : URL(fileURLWithPath: path).lastPathComponent)
        .toolbar {
            if path.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Disconnect") {
                        Task { await appState.disconnect() }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Open") {
                    appState.openVault(at: path)
                }
                .disabled(!isObsidianVault)
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading...")
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't load folder", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await loadDirectory() } }
                }
            }
        }
        .task {
            await loadDirectory()
        }
    }

    private func loadDirectory() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let items = try await store.list(path, includeHidden: true)
            isObsidianVault = items.contains { $0.name == ".obsidian" && $0.isDirectory }
            folders = items
                .filter { $0.isDirectory && !$0.name.hasPrefix(".") }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
