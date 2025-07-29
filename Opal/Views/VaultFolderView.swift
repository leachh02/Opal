//
//  VaultFolderView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//

import SwiftUI
import SMBClient

struct VaultFolderView: View {
    @EnvironmentObject var appState: AppState

    let path: String
    @State private var files: [File] = []

    var body: some View {
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
                        Text(file.name)
                    }
                }
            }
        }
        .navigationTitle(URL(fileURLWithPath: path).lastPathComponent)
        .onAppear {
            Task { await loadContents() }
        }
    }

    private func fullPath(for name: String) -> String {
        path.isEmpty ? name : "\(path)/\(name)"
    }

    private func loadContents() async {
        guard let accessor = appState.treeAccessor else { return }

        do {
            let dir = try await accessor.listDirectory(path: path)
            let filtered = dir.filter { $0.name != "." && $0.name != ".." && !$0.isHidden }
            self.files = filtered.sorted {
                if $0.isDirectory && !$1.isDirectory { return true }
                if !$0.isDirectory && $1.isDirectory { return false }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            print("Failed to list folder contents: \(error.localizedDescription)")
        }
    }
}
