//
//  NoteIndex.swift
//  Opal
//
//  Every file in the open vault, so `[[links]]` resolve and autocomplete
//  across all folders the way they do in Obsidian, and what each note links
//  to, so a rename only has to read the notes that link to what moved.
//

import Foundation

@MainActor
final class NoteIndex: ObservableObject {
    /// A file `[[` autocomplete can link to.
    struct LinkTarget: Equatable {
        /// What autocomplete shows: the note's name, or a file's full name.
        let name: String
        /// What goes between the brackets: the name, or a path when the name is shared.
        let link: String
        /// The folder it is in, relative to the vault, to tell same-named files apart.
        let folder: String
    }

    let vault: Vault

    /// Vault-relative paths of every file, excluding hidden folders such as `.obsidian`.
    @Published private(set) var files: [String] = []
    /// Vault-relative paths of every folder, not including the vault itself.
    @Published private(set) var folders: [String] = []
    @Published private(set) var isLoaded = false

    /// How far the links in other notes are through being updated after a rename or move.
    @Published var linkUpdate: (done: Int, total: Int)?
    /// Notes whose links couldn't be updated, until they've been shown.
    @Published var failedLinkUpdates: [String] = []

    private var refreshing: Task<Void, Never>?
    private var modifiedTimes: [String: Date] = [:]

    /// The link targets in a note, and the modified time of the version they were read from.
    private struct NoteLinks: Codable {
        var modified: Date?
        var targets: [String]
    }

    /// Every note's links, read once and then only again when the note changes.
    /// Saved on the device so reopening the vault doesn't read every note again.
    private var noteLinks: [String: NoteLinks] = [:]
    private var scanning: Task<Void, Never>?
    private var saving: Task<Void, Never>?

    init(vault: Vault) {
        self.vault = vault
        loadNoteLinks()
    }

    /// Re-lists the whole vault. Calls made while a refresh is running wait for it.
    func refresh() async {
        if let refreshing { return await refreshing.value }
        let task = Task { await crawl() }
        refreshing = task
        await task.value
        refreshing = nil

        scanning?.cancel()
        scanning = Task { await scanLinks() }
    }

    private func crawl() async {
        var foundFiles: [String] = []
        var foundFolders: [String] = []
        var foundTimes: [String: Date] = [:]
        var pending = [vault.root]
        while let folder = pending.popLast() {
            // A folder that can't be listed is skipped rather than failing the whole index.
            guard let items = try? await vault.store.list(folder) else { continue }
            for item in items {
                if item.isDirectory {
                    pending.append(item.path)
                    foundFolders.append(relativePath(item.path))
                } else {
                    let relative = relativePath(item.path)
                    foundFiles.append(relative)
                    foundTimes[relative] = item.modified
                }
            }
        }
        modifiedTimes = foundTimes
        files = Self.sorted(foundFiles)
        folders = Self.sorted(foundFolders)
        isLoaded = true
    }

    // MARK: Keeping up with changes made in the app

    /// Adds a file or folder created by the app, without waiting for the next refresh.
    func insert(_ path: String, isDirectory: Bool = false) {
        let relative = relativePath(path)
        if isDirectory {
            if !folders.contains(relative) { folders = Self.sorted(folders + [relative]) }
        } else {
            if !files.contains(relative) { files = Self.sorted(files + [relative]) }
        }
    }

    /// Forgets a file or folder, and everything inside a folder.
    func remove(_ path: String) {
        let relative = relativePath(path)
        let inside = { (candidate: String) in candidate == relative || candidate.hasPrefix(relative + "/") }
        files.removeAll(where: inside)
        folders.removeAll(where: inside)
        noteLinks = noteLinks.filter { !inside($0.key) }
        scheduleSave()
    }

    /// Records a move or rename of a file or folder.
    func move(_ path: String, to destination: String) {
        let from = relativePath(path)
        let to = relativePath(destination)
        let relocate = { (candidate: String) -> String in
            if candidate == from { return to }
            if candidate.hasPrefix(from + "/") { return to + candidate.dropFirst(from.count) }
            return candidate
        }
        files = Self.sorted(files.map(relocate))
        folders = Self.sorted(folders.map(relocate))
        noteLinks = Dictionary(noteLinks.map { (relocate($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        modifiedTimes = Dictionary(modifiedTimes.map { (relocate($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
        scheduleSave()
    }

    // MARK: What notes link to

    /// The link targets in a note, or nil if it hasn't been read yet.
    func linkTargets(in note: String) -> [String]? {
        noteLinks[relativePath(note)]?.targets
    }

    /// Records a note's links after the app writes it, so it needn't be read again.
    func noteSaved(_ path: String, text: String, modified: Date?) {
        let relative = relativePath(path)
        noteLinks[relative] = NoteLinks(modified: modified, targets: LinkScanner.targets(in: text))
        modifiedTimes[relative] = modified
        scheduleSave()
    }

    /// Reads the notes that are new or changed since their links were last read.
    private func scanLinks() async {
        let notes = files.filter { FileKind(fileName: $0) == .markdown }
        let existing = Set(notes)
        noteLinks = noteLinks.filter { existing.contains($0.key) }

        let stale = notes.filter { note in noteLinks[note].map { $0.modified == nil || $0.modified != modifiedTimes[note] } ?? true }
        for note in stale {
            guard !Task.isCancelled else { break }
            let modified = modifiedTimes[note]
            guard let data = try? await vault.store.read(vault.path(note)),
                  let text = String(data: data, encoding: .utf8),
                  // The note may have moved or been deleted while it was being read.
                  files.contains(note), modifiedTimes[note] == modified
            else { continue }
            noteLinks[note] = NoteLinks(modified: modified, targets: LinkScanner.targets(in: text))
        }
        scheduleSave()
    }

    private var cacheURL: URL? {
        guard !vault.id.isEmpty else { return nil }
        let name = vault.id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? vault.id
        return URL.cachesDirectory.appending(components: "Links", name + ".json")
    }

    private func loadNoteLinks() {
        guard let cacheURL, let data = try? Data(contentsOf: cacheURL) else { return }
        noteLinks = (try? JSONDecoder().decode([String: NoteLinks].self, from: data)) ?? [:]
    }

    /// Saves the links a moment later, so a run of changes is saved once.
    private func scheduleSave() {
        guard let cacheURL else { return }
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(noteLinks) else { return }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    // MARK: Links

    /// Finds the file `target` (the part of a `[[link]]` before any `#` or `|`) refers to.
    func resolve(_ target: String, from notePath: String) -> String? {
        LinkResolver(files: files).resolve(target, from: relativePath(notePath)).map { vault.path($0) }
    }

    /// Whether the index has a file at `path`.
    func contains(_ path: String) -> Bool {
        files.contains(relativePath(path))
    }

    /// When a file was last modified, as of the last refresh.
    func modified(_ path: String) -> Date? {
        modifiedTimes[relativePath(path)]
    }

    /// Autocomplete entries. Notes drop their `.md`; a name used more than once
    /// links by its path so each entry points at the right file.
    var linkTargets: [LinkTarget] {
        let resolver = LinkResolver(files: files)
        return files.map { file in
            LinkTarget(
                name: LinkResolver.linkName(for: VaultPath.name(of: file)),
                link: resolver.shortestLink(to: file),
                folder: VaultPath.parent(of: file)
            )
        }
    }

    /// The file a new note for `target` is saved as.
    static func noteFileName(for target: String) -> String {
        LinkResolver.noteFileName(for: target)
    }

    /// A path relative to the vault, which is how the index stores files.
    func relativePath(_ path: String) -> String {
        let root = VaultPath.join([vault.root])
        let normalized = VaultPath.join([path])
        guard !root.isEmpty else { return normalized }
        if normalized == root { return "" }
        return normalized.hasPrefix(root + "/") ? String(normalized.dropFirst(root.count + 1)) : normalized
    }

    private static func sorted(_ paths: [String]) -> [String] {
        paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
