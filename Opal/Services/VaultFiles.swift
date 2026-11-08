//
//  VaultFiles.swift
//  Opal
//
//  Creating, renaming, moving and deleting files in a vault, keeping the
//  note index and other notes' links up to date as Obsidian does.
//

import Foundation

@MainActor
struct VaultFiles {
    let vault: Vault
    let index: NoteIndex

    enum Failure: LocalizedError {
        case emptyName
        case invalidCharacters(String)
        case hiddenName
        case alreadyExists(String)
        case intoItself

        var errorDescription: String? {
            switch self {
            case .emptyName: "Enter a name."
            case .invalidCharacters(let characters): "Names can't contain \(characters)."
            case .hiddenName: "Names can't start with a dot, since that hides them."
            case .alreadyExists(let name): "There's already something called “\(name)” there."
            case .intoItself: "A folder can't be moved inside itself."
            }
        }
    }

    /// Where deleted files go: Obsidian's own trash folder, so they can be recovered.
    var trashFolder: String { vault.path(".trash") }

    // MARK: Creating

    /// Creates an empty note and returns its path.
    func createNote(named name: String, in folder: String) async throws -> String {
        let fileName = LinkResolver.noteFileName(for: try Self.validated(name))
        let path = VaultPath.join([folder, fileName])
        if try await vault.store.fileExists(path) { throw Failure.alreadyExists(fileName) }
        try await vault.store.write(Data(), to: path)
        index.insert(path)
        return path
    }

    func createFolder(named name: String, in folder: String) async throws -> String {
        let folderName = try Self.validated(name)
        let path = VaultPath.join([folder, folderName])
        if try await vault.store.fileExists(path) { throw Failure.alreadyExists(folderName) }
        try await vault.store.createFolder(path)
        index.insert(path, isDirectory: true)
        return path
    }

    // MARK: Renaming and moving

    /// Renames a file or folder. Notes keep their `.md` without it being typed.
    func rename(_ item: VaultItem, to name: String) async throws {
        var newName = try Self.validated(name)
        if item.kind == .markdown { newName = LinkResolver.noteFileName(for: newName) }
        let destination = VaultPath.join([VaultPath.parent(of: item.path), newName])
        try await relocate(item, to: destination)
    }

    func move(_ item: VaultItem, into folder: String) async throws {
        if item.isDirectory, folder == item.path || folder.hasPrefix(item.path + "/") { throw Failure.intoItself }
        try await relocate(item, to: VaultPath.join([folder, item.name]))
    }

    /// Moves the item, then updates links to it in the background. Further
    /// renames and moves should wait until `index.linkUpdate` is nil again.
    private func relocate(_ item: VaultItem, to destination: String) async throws {
        guard destination != item.path else { return }
        // A change of case only ("note" → "Note") finds the item itself on case-insensitive servers.
        if destination.lowercased() != item.path.lowercased(), try await vault.store.fileExists(destination) {
            throw Failure.alreadyExists(VaultPath.name(of: destination))
        }

        // Links are rewritten by comparing where they pointed before the move with where they point after.
        if !index.isLoaded { await index.refresh() }
        let filesBefore = index.files
        let from = index.relativePath(item.path)
        let to = index.relativePath(destination)
        var moves: [String: String] = [:]
        for file in filesBefore where file == from || file.hasPrefix(from + "/") {
            moves[file] = to + file.dropFirst(from.count)
        }

        try await vault.store.move(item.path, to: destination)
        index.move(item.path, to: destination)
        // The folder chosen for new notes follows a rename or move.
        var settings = VaultSettings.load(for: vault)
        if settings.newNoteFolder == from || settings.newNoteFolder.hasPrefix(from + "/") {
            settings.newNoteFolder = to + settings.newNoteFolder.dropFirst(from.count)
            settings.save(for: vault)
        }

        guard !moves.isEmpty else { return }
        let rewriter = LinkRewriter(filesBefore: filesBefore, moves: moves)
        let movedBack = Dictionary(uniqueKeysWithValues: moves.map { ($1, $0) })
        // Only notes whose known links would change, and any not read yet, need opening.
        let notes = index.files.filter { note in
            guard FileKind(fileName: note) == .markdown else { return false }
            guard let targets = index.linkTargets(in: vault.path(note)) else { return true }
            return rewriter.wouldChange(linkTargets: targets, oldPath: movedBack[note] ?? note, newPath: note)
        }
        guard !notes.isEmpty else { return }
        index.linkUpdate = (0, notes.count)
        Task { await updateLinks(in: notes, rewriter: rewriter, movedBack: movedBack) }
    }

    /// Rewrites the links a move broke. A note that can't be read or saved is
    /// reported rather than stopping the rest.
    private func updateLinks(in notes: [String], rewriter: LinkRewriter, movedBack: [String: String]) async {
        for (done, note) in notes.enumerated() {
            index.linkUpdate = (done, notes.count)
            let path = vault.path(note)
            do {
                guard let text = String(data: try await vault.store.read(path), encoding: .utf8),
                      let rewritten = rewriter.rewrite(text, oldPath: movedBack[note] ?? note, newPath: note)
                else { continue }
                try await vault.store.write(Data(rewritten.utf8), to: path)
                index.noteSaved(path, text: rewritten, modified: try? await vault.store.metadata(path).modified)
            } catch {
                index.failedLinkUpdates.append(note)
            }
        }
        index.linkUpdate = nil
    }

    // MARK: Deleting

    /// Moves a file or folder to the vault's `.trash` folder. Links to it are left as they are.
    func trash(_ item: VaultItem) async throws {
        if !(try await vault.store.fileExists(trashFolder)) {
            try await vault.store.createFolder(trashFolder)
        }
        let destination = try await availablePath(for: item.name, in: trashFolder)
        try await vault.store.move(item.path, to: destination)
        index.remove(item.path)
    }

    /// `name`, or `name 2`, `name 3`… if that's taken, keeping the extension.
    private func availablePath(for name: String, in folder: String) async throws -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = VaultPath.join([folder, name])
        var number = 2
        while try await vault.store.fileExists(candidate) {
            let numbered = "\(base) \(number)"
            candidate = VaultPath.join([folder, ext.isEmpty ? numbered : "\(numbered).\(ext)"])
            number += 1
        }
        return candidate
    }

    // MARK: Names

    /// Characters SMB servers reject, plus ones that break `[[links]]`.
    private static let forbidden = Array(#"\/:*?"<>|#^[]"#)

    static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.emptyName }
        guard !trimmed.hasPrefix(".") else { throw Failure.hiddenName }
        let used = forbidden.filter { trimmed.contains($0) }
        guard used.isEmpty else { throw Failure.invalidCharacters(used.map(String.init).joined(separator: " ")) }
        return trimmed
    }
}
