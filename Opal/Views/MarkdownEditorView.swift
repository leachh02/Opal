//
//  MarkdownEditorView.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//


import SwiftUI

struct MarkdownEditorView: View {
    let vault: Vault
    let path: String
    /// A `heading` or `^block-id` to scroll to once the note loads.
    var subpath: String?

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var index: NoteIndex

    @StateObject private var editor = MarkdownEditorController()

    @State private var isLoading = true
    @State private var loadError: String?
    @State private var errorMessage: String?
    @State private var savedText = ""
    /// The file's modification time when it was loaded or last saved, used to spot edits made elsewhere.
    @State private var lastKnownWriteTime: Date?
    @State private var isSaving = false
    @State private var hasConflict = false
    @State private var autosaveTask: Task<Void, Never>?
    @State private var linkedNote: NoteLink?
    /// The name of a `[[link]]` that was tapped but has no note yet.
    @State private var missingNote: String?

    private static let autosaveDelay: Duration = .seconds(2)

    private var hasUnsavedChanges: Bool { editor.text != savedText }

    var body: some View {
        ZStack {
            MarkdownWebEditor(controller: editor)
                .opacity(isLoading || loadError != nil ? 0 : 1)
            if isLoading {
                ProgressView("Loading...")
            } else if let loadError {
                ContentUnavailableView("Couldn't open note", systemImage: "exclamationmark.triangle", description: Text(loadError))
            }
        }
        .navigationTitle(((path as NSString).lastPathComponent as NSString).deletingPathExtension)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    editor.mode = editor.mode == .live ? .source : .live
                } label: {
                    Image(systemName: editor.mode == .live ? "chevron.left.forwardslash.chevron.right" : "eye")
                }
                .accessibilityLabel(editor.mode == .live ? "Show source" : "Show live preview")

                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(isLoading || !hasUnsavedChanges)
                }
            }
            ToolbarItem(placement: .bottomBar) {
                MarkdownFormattingBar(controller: editor)
                    .disabled(isLoading || loadError != nil)
            }
        }
        .task {
            editor.onOpenURL = { openURL($0) }
            editor.onOpenWikiLink = { target in Task { await open(wikiLink: target) } }
            await loadFile()
            if let subpath { editor.reveal(subpath: subpath) }
        }
        .onChange(of: index.files, initial: true) { pushLinkTargets() }
        .onChange(of: index.isLoaded) { pushLinkTargets() }
        .onChange(of: editor.text) {
            scheduleAutosave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await save() } }
        }
        .onDisappear {
            autosaveTask?.cancel()
            Task { await save() }
        }
        .navigationDestination(item: $linkedNote) { link in
            MarkdownEditorView(vault: vault, path: link.path, subpath: link.subpath)
        }
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Note changed on the server", isPresented: $hasConflict) {
            Button("Overwrite", role: .destructive) {
                Task { await save(overwritingServerChanges: true) }
            }
            Button("Discard my edits and reload") {
                Task { await loadFile() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note was edited somewhere else since you opened it.")
        }
        .alert(
            "“\(missingNote ?? "")” doesn't exist yet",
            isPresented: Binding(get: { missingNote != nil }, set: { if !$0 { missingNote = nil } }),
            presenting: missingNote
        ) { name in
            Button("Create Note") {
                Task { await createNote(named: name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Create it at the top of the vault?")
        }
    }

    private func loadFile() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let metadata = try await vault.store.metadata(path)
            let data = try await vault.store.read(path)
            guard let text = String(data: data, encoding: .utf8) else {
                loadError = "This file isn't UTF-8 text, so Opal can't edit it."
                return
            }
            savedText = text
            lastKnownWriteTime = metadata.modified
            editor.setContent(text)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        guard hasUnsavedChanges else { return }
        autosaveTask = Task {
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            await save()
        }
    }

    private func save(overwritingServerChanges: Bool = false) async {
        guard !isLoading, loadError == nil, !isSaving, !hasConflict || overwritingServerChanges else { return }
        let text = await editor.currentContent()
        guard text != savedText else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            if !overwritingServerChanges, let lastKnownWriteTime {
                let metadata = try await vault.store.metadata(path)
                if metadata.modified != lastKnownWriteTime {
                    hasConflict = true
                    return
                }
            }
            try await vault.store.write(Data(text.utf8), to: path)
            savedText = text
            lastKnownWriteTime = try? await vault.store.metadata(path).modified
        } catch {
            errorMessage = "Couldn't save: \(error.localizedDescription)"
            return
        }

        // Edits made while the upload was in flight still need saving.
        if editor.text != savedText { scheduleAutosave() }
    }

    private func pushLinkTargets() {
        guard index.isLoaded else { return }
        editor.setLinkTargets(index.linkTargets)
    }

    /// Opens a `[[target#subpath]]` link, or offers to create the note if there isn't one.
    private func open(wikiLink target: String) async {
        let parts = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        let subpath = parts.count > 1 ? String(parts[1]) : nil

        guard !name.isEmpty else {
            if let subpath { editor.reveal(subpath: subpath) }
            return
        }

        // Until the first index finishes, every link would look missing.
        if !index.isLoaded { await index.refresh() }

        var resolved = index.resolve(name, from: path)
        if resolved == nil {
            resolved = await findUnindexedNote(name)
        }
        guard let resolved else {
            missingNote = name
            // Re-index in the background rather than making the tap wait for a whole-vault listing.
            Task { await index.refresh() }
            return
        }

        guard FileKind(fileName: resolved) == .markdown else {
            errorMessage = "Opal can't open “\((resolved as NSString).lastPathComponent)” yet. Only Markdown notes can be opened for now."
            return
        }
        if resolved == path {
            if let subpath { editor.reveal(subpath: subpath) }
            return
        }
        await save()
        linkedNote = NoteLink(path: resolved, subpath: subpath)
    }

    /// Checks the places a note added since the last index is most likely to be: this
    /// note's folder and the top of the vault. Much cheaper than re-listing everything.
    private func findUnindexedNote(_ name: String) async -> String? {
        let fileName = NoteIndex.fileName(for: name)
        let candidates = [VaultPath.join([VaultPath.parent(of: path), fileName]), vault.path(fileName)]
        for candidate in Set(candidates).sorted() where (try? await vault.store.fileExists(candidate)) == true {
            index.insert(candidate)
            return candidate
        }
        return nil
    }

    /// Creates an empty note for a link with no target, where Obsidian puts new notes by default.
    private func createNote(named name: String) async {
        let newPath = vault.path(NoteIndex.fileName(for: name))
        do {
            // The index may be stale, so never overwrite a note that turns out to exist.
            if !(try await vault.store.fileExists(newPath)) {
                try await vault.store.write(Data(), to: newPath)
            }
        } catch {
            errorMessage = "Couldn't create “\(name)”: \(error.localizedDescription)"
            return
        }
        index.insert(newPath)
        await save()
        linkedNote = NoteLink(path: newPath, subpath: nil)
    }
}

/// Where a tapped `[[link]]` leads.
private struct NoteLink: Hashable {
    let path: String
    let subpath: String?
}
