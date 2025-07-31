//
//  SelectVaultView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//
import SwiftUI
import SMBClient

struct SelectVaultView: View {
    let treeAccessor: TreeAccessor
    let path: String
    
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var files: [File] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var isObsidianVault = false

    var body: some View {
        List {
            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                NavigationLink {
                    if file.isDirectory {
                        SelectVaultView(treeAccessor: treeAccessor, path: fullPath(for: file))
                    }
                } label: {
                    Label(file.name, systemImage: file.isDirectory ? "folder" : "doc.text")
                }
            }
        }
        .navigationTitle(path.isEmpty ? "Choose Vault" : URL(fileURLWithPath: path).lastPathComponent)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Open") {
                    appState.treeAccessor = treeAccessor
                    appState.currentVaultPath = path
                }
                .disabled(!isValidVault)
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading...")
            } else if let error = error {
                Text(error)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .task {
            await loadDirectory()
        }
    }
    
    private var isValidVault: Bool {
        return isObsidianVault
        }

    private func loadDirectory() async {
        do {
            var items = try await treeAccessor.listDirectory(path: path)
            let isObsidianVault = items.contains { $0.name == ".obsidian" && $0.isDirectory }
            items = items
                .filter { $0.name != "." && $0.name != ".." && !$0.isHidden }
                .sorted {
                    if $0.isDirectory != $1.isDirectory {
                        return $0.isDirectory
                    } else {
                        return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    }
                }
            self.files = items
            self.isLoading = false
            self.isObsidianVault = isObsidianVault
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    private func fullPath(for file: File) -> String {
        return path.isEmpty ? file.name : "\(path)/\(file.name)"
    }
}
