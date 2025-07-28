//
//  VaultView.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//


import SwiftUI
import UniformTypeIdentifiers

struct VaultView: View {
    @State private var vaultURL: URL? = nil
    @State private var markdownFiles: [URL] = []
    @State private var selectedFile: URL? = nil
    @State private var markdownContent: String = ""
    @State private var showPicker = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationView {
            List {
                if vaultURL != nil {
                    Section(header: Text("Markdown Files")) {
                        ForEach(markdownFiles, id: \.self) { file in
                            Button(file.lastPathComponent) {
                                openFile(file)
                            }
                        }
                    }
                }

                Section {
                    Button("Open Vault Folder") {
                        showPicker = true
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Vault")
            .sheet(isPresented: $showPicker) {
                FolderPicker { url in
                    vaultURL = url
                    saveVaultBookmark(url)
                    loadMarkdownFiles()
                }
            }
            .onAppear {
                restoreVaultFromBookmark()
            }

            if selectedFile != nil {
                MarkdownEditorView(content: $markdownContent, onSave: {
                    saveCurrentFile()
                })
                    .navigationTitle(selectedFile?.lastPathComponent ?? "")
            } else {
                Text("Select a file to edit")
                    .foregroundColor(.secondary)
            }
        }
//        .alert(item: $alertMessage) { msg in
//            Alert(title: Text("Error"), message: Text(msg), dismissButton: .default(Text("OK")))
//        }
    }

    func loadMarkdownFiles() {
        guard let url = vaultURL else { return }
        do {
            let fm = FileManager.default
            let contents = try fm.subpathsOfDirectory(atPath: url.path)
            markdownFiles = contents
                .filter { $0.hasSuffix(".md") }
                .map { url.appendingPathComponent($0) }
        } catch {
            alertMessage = "Failed to read vault: \(error.localizedDescription)"
        }
    }

    func openFile(_ url: URL) {
        selectedFile = url
        do {
            markdownContent = try String(contentsOf: url)
        } catch {
            alertMessage = "Failed to open file: \(error.localizedDescription)"
        }
    }

    func saveCurrentFile() {
        guard let url = selectedFile else { return }
        do {
            try markdownContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            alertMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
    
    func saveVaultBookmark(_ url: URL) {
        do {
            let data = try url.bookmarkData( includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: "vaultBookmark")
        } catch {
            print("Failed to save bookmark: \(error)")
        }
    }

    func restoreVaultFromBookmark() {
        guard let data = UserDefaults.standard.data(forKey: "vaultBookmark") else { return }

        var isStale = false
        do {
            let restoredURL = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
            if restoredURL.startAccessingSecurityScopedResource() {
                vaultURL = restoredURL
                loadMarkdownFiles()
            }
        } catch {
            print("Failed to restore bookmark: \(error)")
        }
    }
}

func buildVaultTree(at url: URL) -> [VaultItem] {
    var items: [VaultItem] = []
    let fm = FileManager.default

    guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
        return []
    }

    for entry in contents {
        let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false

        if isDir {
            let subItems = buildVaultTree(at: entry)
            items.append(.folder(name: entry.lastPathComponent, contents: subItems))
        } else if entry.pathExtension == "md" {
            items.append(.file(name: entry.lastPathComponent, url: entry))
        }
    }

    return items.sorted { $0.name.lowercased() < $1.name.lowercased() }
}


#Preview {
    VaultView()
}
