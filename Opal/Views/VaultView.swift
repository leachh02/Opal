//
//  VaultView.swift
//  Opal
//

import SwiftUI

/// The open vault: a folder browser that pushes folders, notes and other files.
struct VaultView: View {
    let vault: Vault

    @EnvironmentObject var appState: AppState
    @StateObject private var index: NoteIndex

    init(vault: Vault) {
        self.vault = vault
        _index = StateObject(wrappedValue: NoteIndex(vault: vault))
    }

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
        .environmentObject(index)
        .task {
            MarkdownEditorController.prepareSpare()
            await index.refresh()
        }
        .alert(
            "Some links weren't updated",
            isPresented: Binding(get: { !index.failedLinkUpdates.isEmpty }, set: { if !$0 { index.failedLinkUpdates = [] } })
        ) {
            Button("OK") {}
        } message: {
            let names = index.failedLinkUpdates.map { VaultPath.name(of: ($0 as NSString).deletingPathExtension) }
            Text("Opal couldn't update links in \(names.joined(separator: ", ")). They may still use the old name.")
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

    @EnvironmentObject private var index: NoteIndex
    @State private var items: [VaultItem]?
    @State private var error: String?

    @State private var naming: Naming?
    @State private var draftName = ""
    @State private var moving: VaultItem?
    @State private var trashing: VaultItem?
    @State private var openedNote: VaultItem?
    /// What's happening while an operation runs, shown over the list.
    @State private var busy: String?
    @State private var alert: (title: String, message: String)?

    /// What the name prompt is for.
    private enum Naming: Identifiable {
        case newNote, newFolder, rename(VaultItem)

        var id: String {
            switch self {
            case .newNote: "note"
            case .newFolder: "folder"
            case .rename(let item): "rename " + item.path
            }
        }
    }

    private var files: VaultFiles { VaultFiles(vault: vault, index: index) }

    var body: some View {
        List(items ?? []) { item in
            FileRow(item: item)
                .contextMenu {
                    // Another move before the links catch up would rewrite them from the wrong starting point.
                    Group {
                        Button("Rename", systemImage: "pencil") { startRenaming(item) }
                        Button("Move", systemImage: "folder") { moving = item }
                        Button("Delete", systemImage: "trash", role: .destructive) { trashing = item }
                    }
                    .disabled(index.linkUpdate != nil)
                }
                .swipeActions {
                    if index.linkUpdate == nil {
                        Button("Delete", systemImage: "trash", role: .destructive) { trashing = item }
                        Button("Move", systemImage: "folder") { moving = item }
                            .tint(.indigo)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if let update = index.linkUpdate {
                Label {
                    Text("Updating links… \(update.done) of \(update.total)")
                } icon: {
                    ProgressView()
                }
                .font(.footnote)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 8)
            }
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
        .overlay {
            if let busy {
                ProgressView(busy)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .disabled(busy != nil)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note", systemImage: "square.and.pencil") { startNaming(.newNote) }
                    Button("New Folder", systemImage: "folder.badge.plus") { startNaming(.newFolder) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New")
            }
        }
        .refreshable {
            await load()
            await index.refresh()
        }
        .task { await load() }
        .navigationDestination(item: $openedNote) { note in
            MarkdownEditorView(vault: vault, path: note.path)
        }
        .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } }), presenting: naming) { naming in
            TextField("Name", text: $draftName)
            Button(namingAction(naming)) {
                Task { await finishNaming(naming) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete “\(trashing.map(displayName) ?? "")”?",
            isPresented: Binding(get: { trashing != nil }, set: { if !$0 { trashing = nil } }),
            titleVisibility: .visible,
            presenting: trashing
        ) { item in
            Button("Delete", role: .destructive) {
                Task { await trash(item) }
            }
        } message: { item in
            Text(item.isDirectory
                 ? "The folder and everything in it will be moved to the vault's .trash folder."
                 : "It will be moved to the vault's .trash folder.")
        }
        .sheet(item: $moving) { item in
            MoveItemView(item: item, vaultRoot: vault.root) { folder in
                moving = nil
                Task { await move(item, into: folder) }
            }
            .environmentObject(index)
        }
        .alert(alert?.title ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK") {}
        } message: {
            Text(alert?.message ?? "")
        }
    }

    private var title: String {
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? "Vault" : name
    }

    private var namingTitle: String {
        switch naming {
        case .newNote: "New Note"
        case .newFolder: "New Folder"
        case .rename(let item): "Rename “\(displayName(item))”"
        case nil: ""
        }
    }

    private func namingAction(_ naming: Naming) -> String {
        if case .rename = naming { return "Rename" }
        return "Create"
    }

    private func displayName(_ item: VaultItem) -> String {
        item.kind == .markdown ? (item.name as NSString).deletingPathExtension : item.name
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

    // MARK: Operations

    private func startNaming(_ purpose: Naming) {
        draftName = ""
        naming = purpose
    }

    private func startRenaming(_ item: VaultItem) {
        draftName = displayName(item)
        naming = .rename(item)
    }

    private func finishNaming(_ purpose: Naming) async {
        switch purpose {
        case .newNote:
            await run("Creating…") {
                let notePath = try await files.createNote(named: draftName, in: path)
                await load()
                openedNote = items?.first { $0.path == notePath }
            }
        case .newFolder:
            await run("Creating…") {
                _ = try await files.createFolder(named: draftName, in: path)
                await load()
            }
        case .rename(let item):
            await run("Renaming…") {
                try await files.rename(item, to: draftName)
                await load()
            }
        }
    }

    private func move(_ item: VaultItem, into folder: String) async {
        await run("Moving…") {
            try await files.move(item, into: folder)
            await load()
        }
    }

    private func trash(_ item: VaultItem) async {
        await run("Deleting…") {
            try await files.trash(item)
            await load()
        }
    }

    private func run(_ message: String, _ operation: () async throws -> Void) async {
        busy = message
        defer { busy = nil }
        do {
            try await operation()
        } catch {
            alert = ("Couldn't do that", error.localizedDescription)
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
