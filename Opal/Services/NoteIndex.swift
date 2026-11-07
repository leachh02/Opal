//
//  NoteIndex.swift
//  Opal
//
//  Every file in the open vault, so `[[links]]` resolve and autocomplete
//  across all folders the way they do in Obsidian.
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
    @Published private(set) var isLoaded = false

    private var refreshing: Task<Void, Never>?

    init(vault: Vault) {
        self.vault = vault
    }

    /// Re-lists the whole vault. Calls made while a refresh is running wait for it.
    func refresh() async {
        if let refreshing { return await refreshing.value }
        let task = Task { await crawl() }
        refreshing = task
        await task.value
        refreshing = nil
    }

    private func crawl() async {
        var found: [String] = []
        var folders = [vault.root]
        while let folder = folders.popLast() {
            // A folder that can't be listed is skipped rather than failing the whole index.
            guard let items = try? await vault.store.list(folder) else { continue }
            for item in items {
                if item.isDirectory {
                    folders.append(item.path)
                } else {
                    found.append(relativePath(item.path))
                }
            }
        }
        files = found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        isLoaded = true
    }

    /// Adds a file created by the app, without waiting for the next refresh.
    func insert(_ path: String) {
        let relative = relativePath(path)
        guard !files.contains(relative) else { return }
        files.append(relative)
        files.sort { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Finds the file `target` (the part of a `[[link]]` before any `#` or `|`) refers to,
    /// following Obsidian: a matching path wins, then a file in the linking note's
    /// folder, then the one with the shortest path. Matching ignores case.
    func resolve(_ target: String, from notePath: String) -> String? {
        let wanted = Self.fileName(for: target).lowercased()
        let candidates = files.filter { file in
            let lowered = file.lowercased()
            return lowered == wanted || lowered.hasSuffix("/" + wanted)
        }
        guard !candidates.isEmpty else { return nil }

        let folder = relativePath(VaultPath.parent(of: notePath)).lowercased()
        let best = candidates.first { $0.lowercased() == wanted }
            ?? candidates.first { VaultPath.parent(of: $0).lowercased() == folder }
            ?? candidates.min { a, b in
                let (depthA, depthB) = (a.split(separator: "/").count, b.split(separator: "/").count)
                return depthA != depthB ? depthA < depthB : a.localizedStandardCompare(b) == .orderedAscending
            }
        return best.map { vault.path($0) }
    }

    /// Autocomplete entries. Notes drop their `.md`; a name used more than once
    /// links by its path so each entry points at the right file.
    var linkTargets: [LinkTarget] {
        let named = files.map { file in (file: file, name: Self.linkName(for: (file as NSString).lastPathComponent)) }
        var counts: [String: Int] = [:]
        for entry in named { counts[entry.name.lowercased(), default: 0] += 1 }
        return named.map { entry in
            let shared = counts[entry.name.lowercased(), default: 0] > 1
            return LinkTarget(
                name: entry.name,
                link: shared ? Self.linkName(for: entry.file) : entry.name,
                folder: VaultPath.parent(of: entry.file)
            )
        }
    }

    /// The file name a link target points at: `.md` is implied when there's no extension.
    static func fileName(for target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        return (trimmed as NSString).pathExtension.isEmpty ? trimmed + ".md" : trimmed
    }

    private static func linkName(for path: String) -> String {
        (path as NSString).pathExtension.lowercased() == "md" ? (path as NSString).deletingPathExtension : path
    }

    private func relativePath(_ path: String) -> String {
        let root = VaultPath.join([vault.root])
        let normalized = VaultPath.join([path])
        guard !root.isEmpty else { return normalized }
        if normalized == root { return "" }
        return normalized.hasPrefix(root + "/") ? String(normalized.dropFirst(root.count + 1)) : normalized
    }
}
