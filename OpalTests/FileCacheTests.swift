//
//  FileCacheTests.swift
//  OpalTests
//
//  Downloaded copies of files, and clearing them at launch.
//

import Foundation
import Testing
@testable import Opal

@MainActor
@Suite("Downloaded files", .serialized)
struct FileCacheTests {
    let store = MemoryVaultStore(["photo.png": "first"], root: "Vault")
    var cache: FileCache { FileCache(vault: Vault(store: store, root: "Vault", id: "file-cache-tests")) }

    func contents(_ url: URL) throws -> String {
        String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    @Test func downloadsAFileOnce() async throws {
        let url = try await cache.localURL(for: "Vault/photo.png")
        #expect(try contents(url) == "first")

        // The server's copy hasn't changed, so the download is reused.
        store.add("Vault/photo.png", text: "second")
        #expect(try contents(try await cache.localURL(for: "Vault/photo.png")) == "first")
        FileCache.clearAll()
    }

    @Test func clearingDeletesEveryCopy() async throws {
        let url = try await cache.localURL(for: "Vault/photo.png")
        FileCache.clearAll()
        #expect(!FileManager.default.fileExists(atPath: FileCache.root.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))

        // The next time it's shown, the file is downloaded again.
        store.add("Vault/photo.png", text: "second")
        #expect(try contents(try await cache.localURL(for: "Vault/photo.png")) == "second")
        FileCache.clearAll()
    }

    @Test func countsTheSpaceUsed() async throws {
        FileCache.clearAll()
        #expect(await FileCache.totalSize() == 0)
        _ = try await cache.localURL(for: "Vault/photo.png")
        #expect(await FileCache.totalSize() > 0)
        FileCache.clearAll()
    }

    @Test func clearsOnLaunchUnlessTurnedOff() {
        let defaults = UserDefaults(suiteName: "OpalTests.storage")!
        defaults.removePersistentDomain(forName: "OpalTests.storage")
        #expect(StoragePreferences.clearsDownloadsOnLaunch(defaults))
        defaults.set(false, forKey: StoragePreferences.clearDownloadsOnLaunchKey)
        #expect(!StoragePreferences.clearsDownloadsOnLaunch(defaults))
    }

    @Test func clearingWithNothingDownloadedIsFine() {
        FileCache.clearAll()
        FileCache.clearAll()
        #expect(!FileManager.default.fileExists(atPath: FileCache.root.path(percentEncoded: false)))
    }
}
