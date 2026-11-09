//
//  PathsAndSettingsTests.swift
//  OpalTests
//

import Foundation
import Testing
@testable import Opal

@Suite("Paths")
struct VaultPathTests {
    @Test func joinsWithoutDoubleSlashes() {
        #expect(VaultPath.join(["Vaults/", "/Notes", "", "Plan.md"]) == "Vaults/Notes/Plan.md")
        #expect(VaultPath.join(["", "Plan.md"]) == "Plan.md")
        #expect(VaultPath.join([]) == "")
    }

    @Test func splitsIntoFolderAndName() {
        #expect(VaultPath.parent(of: "Vaults/Notes/Plan.md") == "Vaults/Notes")
        #expect(VaultPath.parent(of: "Plan.md") == "")
        #expect(VaultPath.name(of: "Vaults/Notes/Plan.md") == "Plan.md")
        #expect(VaultPath.name(of: "Notes") == "Notes")
    }

    @Test @MainActor func vaultPathsStartAtTheRoot() {
        let vault = Vault(store: MemoryVaultStoreHolder.store, root: "Vaults/Notes")
        #expect(vault.path("Projects", "Plan.md") == "Vaults/Notes/Projects/Plan.md")
        #expect(vault.path() == "Vaults/Notes")
    }

    @Test(arguments: [
        ("Plan.md", FileKind.markdown), ("Plan.MARKDOWN", .markdown), ("Board.canvas", .canvas),
        ("photo.JPG", .image), ("icon.svg", .image), ("song.m4a", .audio), ("clip.mov", .video),
        ("paper.pdf", .pdf), ("data.csv", .other), ("README", .other),
    ])
    func recognisesFileKinds(_ name: String, _ kind: FileKind) {
        #expect(FileKind(fileName: name) == kind)
    }
}

@MainActor
enum MemoryVaultStoreHolder {
    static let store = MemoryVaultStore()
}

@Suite("Settings", .serialized)
struct VaultSettingsTests {
    let defaults = UserDefaults(suiteName: "OpalTests.settings")!

    init() { defaults.removePersistentDomain(forName: "OpalTests.settings") }

    @MainActor
    func vault(id: String) -> Vault { Vault(store: MemoryVaultStoreHolder.store, root: "Notes", id: id) }

    @Test @MainActor func defaultsToTheVaultRoot() {
        let settings = VaultSettings.load(for: vault(id: "a"), from: defaults)
        #expect(settings == VaultSettings(newNoteLocation: .vaultRoot, newNoteFolder: ""))
    }

    @Test @MainActor func savesForEachVault() {
        VaultSettings(newNoteLocation: .folder, newNoteFolder: "Inbox").save(for: vault(id: "a"), to: defaults)
        VaultSettings(newNoteLocation: .currentFolder).save(for: vault(id: "b"), to: defaults)
        #expect(VaultSettings.load(for: vault(id: "a"), from: defaults) == VaultSettings(newNoteLocation: .folder, newNoteFolder: "Inbox"))
        #expect(VaultSettings.load(for: vault(id: "b"), from: defaults).newNoteLocation == .currentFolder)
    }

    @Test @MainActor func doesNotSaveForAVaultWithoutAnID() {
        VaultSettings(newNoteLocation: .folder, newNoteFolder: "Inbox").save(for: vault(id: ""), to: defaults)
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.hasPrefix("vaultSettings.") })
    }

    @Test @MainActor func ignoresUnreadableSettings() {
        defaults.set(Data("not json".utf8), forKey: "vaultSettings.a")
        #expect(VaultSettings.load(for: vault(id: "a"), from: defaults) == VaultSettings())
    }
}
