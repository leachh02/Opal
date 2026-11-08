//
//  MoveItemView.swift
//  Opal
//

import SwiftUI

/// Picks the folder to move a file or folder into, from every folder in the vault.
struct MoveItemView: View {
    let item: VaultItem
    let vaultRoot: String
    let onMove: (String) -> Void

    @EnvironmentObject private var index: NoteIndex

    var body: some View {
        // The item's current folder, and for a folder the folder itself and everything inside it, can't be chosen.
        let current = index.relativePath(VaultPath.parent(of: item.path))
        let itself = index.relativePath(item.path)
        FolderPickerView(title: "Move “\(displayName)”", vaultRoot: vaultRoot, onPick: onMove) { folder in
            folder != current && !(item.isDirectory && (folder == itself || folder.hasPrefix(itself + "/")))
        }
    }

    private var displayName: String {
        item.kind == .markdown ? (item.name as NSString).deletingPathExtension : item.name
    }
}

/// Picks a folder in the vault, shown as a tree with the vault at the top.
struct FolderPickerView: View {
    let title: String
    let vaultRoot: String
    /// The chosen folder's full path.
    let onPick: (String) -> Void
    /// Whether a folder, relative to the vault (`""` is the vault itself), can be chosen.
    var isAllowed: (String) -> Bool = { _ in true }

    @EnvironmentObject private var index: NoteIndex
    @Environment(\.dismiss) private var dismiss

    private struct Destination: Identifiable {
        let path: String
        let name: String
        let depth: Int
        let isAllowed: Bool
        var id: String { path }
    }

    var body: some View {
        NavigationStack {
            List(destinations) { destination in
                Button {
                    onPick(destination.path)
                } label: {
                    Label(destination.name, systemImage: destination.depth == 0 ? "archivebox" : "folder")
                        .padding(.leading, CGFloat(max(destination.depth - 1, 0)) * 16)
                }
                .disabled(!destination.isAllowed)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// The vault, then its folders in tree order.
    private var destinations: [Destination] {
        let vaultName = VaultPath.name(of: vaultRoot)
        return [Destination(path: vaultRoot, name: vaultName.isEmpty ? "Vault" : vaultName, depth: 0, isAllowed: isAllowed(""))]
            + index.folders.map { folder in
                Destination(
                    path: VaultPath.join([vaultRoot, folder]),
                    name: VaultPath.name(of: folder),
                    depth: folder.split(separator: "/").count,
                    isAllowed: isAllowed(folder)
                )
            }
    }
}
