//
//  VaultPickerView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//
import SwiftUI
import SMBClient

struct VaultPickerView: View {
    let treeAccessor: TreeAccessor
    let path: String

    @State private var files: [File] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        List {
            ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                NavigationLink {
                    if file.isDirectory {
                        VaultPickerView(treeAccessor: treeAccessor, path: fullPath(for: file))
                    } else {
//                        MarkdownEditorView(treeAccessor: treeAccessor, path: fullPath(for: file))
                    }
                } label: {
                    Label(file.name, systemImage: file.isDirectory ? "folder" : "doc.text")
                }
            }
        }
        .navigationTitle(path.isEmpty ? "Vault" : URL(fileURLWithPath: path).lastPathComponent)
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

    private func loadDirectory() async {
        do {
            var items = try await treeAccessor.listDirectory(path: path)
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
        } catch {
            self.error = error.localizedDescription
            self.isLoading = false
        }
    }

    private func fullPath(for file: File) -> String {
        return path.isEmpty ? file.name : "\(path)/\(file.name)"
    }
}
