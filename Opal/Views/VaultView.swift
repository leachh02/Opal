//
//  VaultView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//

import SwiftUI
import SMBClient

struct VaultView: View {
    @EnvironmentObject var appState: AppState

    @State private var files: [File] = []
    @State private var currentPath: String = ""

    private var treeAccessor: TreeAccessor? {
        appState.treeAccessor
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(files, id: \.name) { file in
                    if file.isDirectory {
                        NavigationLink(destination: VaultFolderView(path: fullPath(for: file.name))) {
                            HStack {
                                Image(systemName: "folder")
                                Text(file.name)
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "doc")
                            VStack(alignment: .leading) {
                                Text(file.name)
                                Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
            }
            .navigationTitle(currentPath.isEmpty ? "Vault" : URL(fileURLWithPath: currentPath).lastPathComponent)
            .onAppear {
                currentPath = appState.currentVaultPath
                Task { await loadVaultContents() }
            }
        }
    }

    private func fullPath(for name: String) -> String {
        currentPath.isEmpty ? name : "\(currentPath)/\(name)"
    }

    private func loadVaultContents() async {
        guard let accessor = treeAccessor else { return }

        do {
            let dir = try await accessor.listDirectory(path: currentPath)
            let filtered = dir.filter { $0.name != "." && $0.name != ".." && !$0.isHidden }
            self.files = filtered.sorted {
                if $0.isDirectory && !$1.isDirectory { return true }
                if !$0.isDirectory && $1.isDirectory { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            print("Failed to list vault directory: \(error.localizedDescription)")
        }
    }
}
