//
//  VaultView.swift
//  Opal
//

import SwiftUI

/// The open vault: a folder browser that pushes folders, notes and other files.
struct VaultView: View {
    let vault: Vault

    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            FolderView(vault: vault, path: vault.root)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Menu {
                            Button("Switch Vault", systemImage: "folder.badge.gearshape") {
                                appState.closeVault()
                            }
                            Button("Disconnect", systemImage: "eject", role: .destructive) {
                                Task { await appState.disconnect() }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Vault options")
                    }
                }
                .navigationDestination(for: VaultItem.self) { item in
                    destination(for: item)
                }
        }
    }

    @ViewBuilder
    private func destination(for item: VaultItem) -> some View {
        switch item.kind {
        case .folder:
            FolderView(vault: vault, path: item.path)
        case .markdown:
            MarkdownEditorView(vault: vault, path: item.path)
        default:
            UnsupportedFileView(item: item)
        }
    }
}

struct FolderView: View {
    let vault: Vault
    let path: String

    @State private var items: [VaultItem]?
    @State private var error: String?

    var body: some View {
        List(items ?? []) { item in
            FileRow(item: item)
        }
        .overlay {
            if let error {
                ContentUnavailableView {
                    Label("Couldn't load folder", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else if items == nil {
                ProgressView("Loading...")
            } else if items?.isEmpty == true {
                ContentUnavailableView("Empty Folder", systemImage: "folder")
            }
        }
        .navigationTitle(title)
        .refreshable { await load() }
        .task { await load() }
    }

    private var title: String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "Vault" : name
    }

    private func load() async {
        do {
            items = try await vault.store.list(path).sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

/// A list row without the trailing chevron, like the Notes app.
private struct FileRow: View {
    let item: VaultItem

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationLink(value: item) { EmptyView() }
                .opacity(0)
            HStack(spacing: 12) {
                Image(systemName: item.kind.systemImage)
                    .foregroundStyle(item.kind == .folder ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                    if !item.isDirectory {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Notes show without their `.md`, as in Obsidian.
    private var displayName: String {
        item.kind == .markdown ? (item.name as NSString).deletingPathExtension : item.name
    }

    private var subtitle: String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)
        return "\(item.modified.formatted(.relative(presentation: .named))) · \(size)"
    }
}

struct UnsupportedFileView: View {
    let item: VaultItem

    var body: some View {
        ContentUnavailableView(
            "Can't Open This File Yet",
            systemImage: item.kind.systemImage,
            description: Text("Opal can only open Markdown notes for now. Support for images, PDFs and media is coming.")
        )
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
