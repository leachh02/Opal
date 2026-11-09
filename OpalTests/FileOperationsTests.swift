//
//  FileOperationsTests.swift
//  OpalTests
//
//  Creating, renaming, moving and trashing files against an in-memory vault,
//  and the note index keeping up.
//

import Foundation
import Testing
@testable import Opal

/// A vault held in memory, standing in for an SMB share.
@MainActor
final class MemoryVaultStore: VaultStore {
    private(set) var files: [String: Data] = [:]
    private(set) var folders: Set<String> = [""]
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    struct Missing: Error {}
    struct Exists: Error {}

    init(_ notes: [String: String] = [:], root: String = "") {
        for (path, text) in notes { add(VaultPath.join([root, path]), text: text) }
    }

    func add(_ path: String, text: String = "") {
        files[path] = Data(text.utf8)
        addFolders(above: path)
    }

    func text(_ path: String) -> String? {
        files[path].map { String(decoding: $0, as: UTF8.self) }
    }

    private func addFolders(above path: String) {
        var folder = VaultPath.parent(of: path)
        while !folder.isEmpty {
            folders.insert(folder)
            folder = VaultPath.parent(of: folder)
        }
    }

    func list(_ path: String, includeHidden: Bool) async throws -> [VaultItem] {
        guard folders.contains(path) else { throw Missing() }
        let children = (files.keys.map { ($0, false) } + folders.map { ($0, true) })
            .filter { !$0.0.isEmpty && VaultPath.parent(of: $0.0) == path }
            .filter { includeHidden || !VaultPath.name(of: $0.0).hasPrefix(".") }
        return children.map { child, isDirectory in
            VaultItem(path: child, name: VaultPath.name(of: child), isDirectory: isDirectory,
                      size: UInt64(files[child]?.count ?? 0), modified: date)
        }
    }

    func read(_ path: String) async throws -> Data {
        guard let data = files[path] else { throw Missing() }
        return data
    }

    func write(_ data: Data, to path: String) async throws {
        guard folders.contains(VaultPath.parent(of: path)) else { throw Missing() }
        files[path] = data
    }

    func metadata(_ path: String) async throws -> VaultItemMetadata {
        if let data = files[path] { return VaultItemMetadata(size: UInt64(data.count), isDirectory: false, modified: date) }
        if folders.contains(path) { return VaultItemMetadata(size: 0, isDirectory: true, modified: date) }
        throw Missing()
    }

    func fileExists(_ path: String) async throws -> Bool {
        files[path] != nil || folders.contains(path)
    }

    func createFolder(_ path: String) async throws {
        guard !(try await fileExists(path)) else { throw Exists() }
        guard folders.contains(VaultPath.parent(of: path)) else { throw Missing() }
        folders.insert(path)
    }

    func move(_ path: String, to destination: String) async throws {
        guard try await fileExists(path) else { throw Missing() }
        // Like SMB servers, a change of case only is allowed.
        if destination.lowercased() != path.lowercased(), try await fileExists(destination) { throw Exists() }
        let relocate = { (candidate: String) -> String? in
            if candidate == path { return destination }
            if candidate.hasPrefix(path + "/") { return destination + candidate.dropFirst(path.count) }
            return nil
        }
        for (file, data) in files { if let moved = relocate(file) { files[file] = nil; files[moved] = data } }
        for folder in folders { if let moved = relocate(folder) { folders.remove(folder); folders.insert(moved) } }
    }
}

@MainActor
@Suite("File operations")
struct FileOperationsTests {
    let store: MemoryVaultStore
    let vault: Vault
    let index: NoteIndex
    var files: VaultFiles { VaultFiles(vault: vault, index: index) }

    init() async {
        store = MemoryVaultStore([
            "Home.md": "Start at [[Plan]] or [[Projects/Ideas|ideas]].\n![[photo.png]]",
            "Plan.md": "Back to [[Home]].",
            "Projects/Ideas.md": "See [[Plan#Goals]].",
            "Projects/photo.png": "",
            "Code.md": "`[[Plan]]`",
        ], root: "Vaults/Notes")
        vault = Vault(store: store, root: "Vaults/Notes")
        index = NoteIndex(vault: vault)
        await index.refresh()
    }

    func item(_ relative: String) async throws -> VaultItem {
        let path = vault.path(relative)
        let metadata = try await store.metadata(path)
        return VaultItem(path: path, name: VaultPath.name(of: path), isDirectory: metadata.isDirectory,
                         size: metadata.size, modified: metadata.modified)
    }

    /// Waits for the links in other notes to finish updating.
    func linksUpdated() async throws {
        for _ in 0..<1000 where index.linkUpdate != nil { try await Task.sleep(for: .milliseconds(5)) }
        #expect(index.linkUpdate == nil)
    }

    // MARK: Index

    @Test func indexListsEveryFileAndFolder() {
        #expect(index.files == ["Code.md", "Home.md", "Plan.md", "Projects/Ideas.md", "Projects/photo.png"])
        #expect(index.folders == ["Projects"])
        #expect(index.resolve("Ideas", from: vault.path("Home.md")) == "Vaults/Notes/Projects/Ideas.md")
        #expect(index.relativePath("Vaults/Notes") == "")
        #expect(index.relativePath("/Vaults/Notes/Plan.md") == "Plan.md")
    }

    @Test func indexOffersShortestLinks() {
        index.insert(vault.path("Archive/Plan.md"))
        let links = Dictionary(uniqueKeysWithValues: index.linkTargets.map { ($0.link, $0.name) })
        #expect(links["Plan"] == "Plan")
        #expect(links["Archive/Plan"] == "Plan")
        #expect(links["photo.png"] == "photo.png")
    }

    // MARK: Creating

    @Test func createsANote() async throws {
        let path = try await files.createNote(named: " Inbox ", in: vault.path("Projects"))
        #expect(path == "Vaults/Notes/Projects/Inbox.md")
        #expect(store.text(path) == "")
        #expect(index.contains(path))
    }

    @Test func refusesToReplaceANote() async {
        await #expect(throws: VaultFiles.Failure.self) {
            try await files.createNote(named: "Plan", in: vault.root)
        }
    }

    @Test func createsAFolder() async throws {
        let path = try await files.createFolder(named: "Archive", in: vault.root)
        #expect(store.folders.contains(path))
        #expect(index.folders.contains("Archive"))
    }

    @Test(arguments: ["", "  ", ".hidden", "a/b", "what?", "[[x]]", "a#b", "a|b"])
    func rejectsBadNames(_ name: String) {
        #expect(throws: VaultFiles.Failure.self) { try VaultFiles.validated(name) }
    }

    @Test func trimsNames() throws {
        #expect(try VaultFiles.validated("  Meeting notes \n") == "Meeting notes")
    }

    // MARK: Renaming and moving

    @Test func renamingANoteUpdatesLinksToIt() async throws {
        try await files.rename(try await item("Plan.md"), to: "Roadmap")
        try await linksUpdated()
        #expect(store.files["Vaults/Notes/Plan.md"] == nil)
        #expect(store.text("Vaults/Notes/Roadmap.md") == "Back to [[Home]].")
        #expect(store.text("Vaults/Notes/Home.md") == "Start at [[Roadmap]] or [[Projects/Ideas|ideas]].\n![[photo.png]]")
        #expect(store.text("Vaults/Notes/Projects/Ideas.md") == "See [[Roadmap#Goals]].")
        #expect(store.text("Vaults/Notes/Code.md") == "`[[Plan]]`")
        #expect(index.files.contains("Roadmap.md") && !index.files.contains("Plan.md"))
        #expect(index.failedLinkUpdates.isEmpty)
    }

    @Test func renamingKeepsOtherExtensions() async throws {
        try await files.rename(try await item("Projects/photo.png"), to: "cover.png")
        try await linksUpdated()
        #expect(store.files["Vaults/Notes/Projects/cover.png"] != nil)
        #expect(store.text("Vaults/Notes/Home.md")?.hasSuffix("![[cover.png]]") == true)
    }

    @Test func renamingAFolderUpdatesPathLinks() async throws {
        try await files.rename(try await item("Projects"), to: "Work")
        try await linksUpdated()
        #expect(index.files.contains("Work/Ideas.md"))
        #expect(index.folders == ["Work"])
        // The name alone is enough now, since no other note is called Ideas.
        #expect(store.text("Vaults/Notes/Home.md") == "Start at [[Plan]] or [[Ideas|ideas]].\n![[photo.png]]")
    }

    @Test func refusesToRenameOverAnotherFile() async throws {
        await #expect(throws: VaultFiles.Failure.self) {
            try await files.rename(try await item("Plan.md"), to: "Home")
        }
        #expect(store.text("Vaults/Notes/Plan.md") == "Back to [[Home]].")
    }

    @Test func allowsAChangeOfCaseOnly() async throws {
        try await files.rename(try await item("Plan.md"), to: "plan")
        try await linksUpdated()
        #expect(store.files["Vaults/Notes/plan.md"] != nil)
    }

    @Test func movingANoteKeepsItsLinksWorking() async throws {
        store.add("Vaults/Notes/Zed/photo.png")
        index.insert("Vaults/Notes/Zed", isDirectory: true)
        index.insert("Vaults/Notes/Zed/photo.png")

        // From Zed, `![[photo.png]]` would now mean Zed's own photo, so it needs its path.
        try await files.move(try await item("Home.md"), into: vault.path("Zed"))
        try await linksUpdated()
        #expect(store.files["Vaults/Notes/Home.md"] == nil)
        #expect(store.text("Vaults/Notes/Zed/Home.md") == "Start at [[Plan]] or [[Projects/Ideas|ideas]].\n![[Projects/photo.png]]")
        #expect(store.text("Vaults/Notes/Plan.md") == "Back to [[Home]].")
    }

    @Test func refusesToMoveAFolderIntoItself() async throws {
        await #expect(throws: VaultFiles.Failure.self) {
            try await files.move(try await item("Projects"), into: vault.path("Projects"))
        }
    }

    @Test func newNotesFolderFollowsARename() async throws {
        let vault = Vault(store: store, root: "Vaults/Notes", id: "test-" + UUID().uuidString)
        defer { UserDefaults.standard.removeObject(forKey: "vaultSettings." + vault.id) }
        let index = NoteIndex(vault: vault)
        await index.refresh()
        VaultSettings(newNoteLocation: .folder, newNoteFolder: "Projects").save(for: vault)

        try await VaultFiles(vault: vault, index: index).rename(try await item("Projects"), to: "Work")
        #expect(VaultSettings.load(for: vault).newNoteFolder == "Work")
    }

    // MARK: Deleting

    @Test func trashingMovesToTheTrashFolder() async throws {
        try await files.trash(try await item("Plan.md"))
        #expect(store.text("Vaults/Notes/.trash/Plan.md") == "Back to [[Home]].")
        #expect(!index.files.contains("Plan.md"))
        // Links to it are left as they are.
        #expect(store.text("Vaults/Notes/Home.md")?.contains("[[Plan]]") == true)
    }

    @Test func trashingNumbersNamesAlreadyInTheTrash() async throws {
        store.add("Vaults/Notes/.trash/Plan.md", text: "older")
        try await files.trash(try await item("Plan.md"))
        #expect(store.text("Vaults/Notes/.trash/Plan.md") == "older")
        #expect(store.text("Vaults/Notes/.trash/Plan 2.md") == "Back to [[Home]].")
    }
}
