//
//  FileCache.swift
//  Opal
//
//  Local copies of vault files such as images and PDFs, for viewers that
//  need a file on the device. A copy is reused until the server's changes.
//  Copies are deleted each time the app launches, unless kept in Settings.
//

import Foundation

@MainActor
struct FileCache {
    let vault: Vault

    /// A local copy of the file at `path`, downloaded if there isn't one or the
    /// server's copy has changed. Pass `modified` if it's known, to save asking the server.
    func localURL(for path: String, modified: Date? = nil) async throws -> URL {
        let modified = if let modified { modified } else { try await vault.store.metadata(path).modified }
        let local = folder.appending(path: relativePath(path))
        let attributes = try? FileManager.default.attributesOfItem(atPath: local.path(percentEncoded: false))
        if let cached = attributes?[.modificationDate] as? Date, cached == modified {
            return local
        }

        // A note can embed the same image more than once, so share one download.
        if let download = Self.downloads[local] { return try await download.value }
        let download = Task {
            let data = try await vault.store.read(path)
            try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: local, options: .atomic)
            // The server's modified time marks which version this is.
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: local.path(percentEncoded: false))
            return local
        }
        Self.downloads[local] = download
        defer { Self.downloads[local] = nil }
        return try await download.value
    }

    private static var downloads: [URL: Task<URL, Error>] = [:]

    // MARK: Every vault's copies

    /// The space every vault's copies take up, in bytes.
    nonisolated static func totalSize() async -> Int64 {
        await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return 0 }
            var total: Int64 = 0
            for case let file as URL in files {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
            return total
        }.value
    }

    /// Deletes every vault's copies, at launch or from Settings. Files are
    /// downloaded again when next shown. The folder is moved aside straight
    /// away, so new downloads start afresh, and deleted in the background.
    nonisolated static func clearAll() {
        let files = FileManager.default
        guard files.fileExists(atPath: root.path(percentEncoded: false)) else { return }
        let old = files.temporaryDirectory.appending(component: "Old Files " + UUID().uuidString)
        do {
            try files.moveItem(at: root, to: old)
        } catch {
            try? files.removeItem(at: root)
            return
        }
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    nonisolated static var root: URL { URL.cachesDirectory.appending(component: "Files") }

    private var folder: URL {
        let name = vault.id.isEmpty ? "Default" : vault.id
        return Self.root.appending(component: name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? name)
    }

    private func relativePath(_ path: String) -> String {
        let root = VaultPath.join([vault.root])
        let normalized = VaultPath.join([path])
        return !root.isEmpty && normalized.hasPrefix(root + "/") ? String(normalized.dropFirst(root.count + 1)) : normalized
    }
}
