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

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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
    @State private var linkedNotePath: String?

    private static let autosaveDelay: Duration = .seconds(2)

    private var hasUnsavedChanges: Bool { editor.text != savedText }
    private var folder: String { VaultPath.parent(of: path) }

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
        }
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
        .navigationDestination(item: $linkedNotePath) { linkedPath in
            MarkdownEditorView(vault: vault, path: linkedPath)
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
            return
        }

        await loadNoteNames()
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

    /// Note names for `[[` autocomplete. For now only the current folder is indexed.
    private func loadNoteNames() async {
        guard let items = try? await vault.store.list(folder) else { return }
        let names = items
            .filter { $0.kind == .markdown }
            .map { ($0.name as NSString).deletingPathExtension }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        editor.setNoteNames(names)
    }

    /// Resolves `[[target]]` against the current folder, then the vault root.
    private func open(wikiLink target: String) async {
        let name = target.split(separator: "#", maxSplits: 1).first.map(String.init) ?? target
        guard !name.isEmpty else { return }
        let fileName = (name as NSString).pathExtension.isEmpty ? name + ".md" : name

        let candidates = [folder, vault.root].map { VaultPath.join([$0, fileName]) }
        for candidate in candidates {
            if (try? await vault.store.fileExists(candidate)) == true {
                await save()
                linkedNotePath = candidate
                return
            }
        }
        errorMessage = "Couldn't find “\(name)” in this folder or at the top of the vault."
    }
}
