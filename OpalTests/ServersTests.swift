//
//  ServersTests.swift
//  OpalTests
//
//  Forgetting saved servers and their passwords.
//

import Foundation
import Testing
@testable import Opal

@MainActor
@Suite("Saved servers", .serialized)
struct ServersTests {
    let defaults = UserDefaults(suiteName: "OpalTests.servers")!
    let servers: ServerManager
    // A host no real server uses, so the Keychain entries are the tests' own.
    let nas = ConnectionSettings(host: "opal-tests-nas.invalid", share: "Notes", username: "alice")
    let pi = ConnectionSettings(host: "opal-tests-pi.invalid", port: 4445, share: "Vault", username: "")

    init() {
        defaults.removePersistentDomain(forName: "OpalTests.servers")
        servers = ServerManager(defaults: defaults)
        for settings in [nas, pi] {
            servers.addServer(settings)
            CredentialStore.shared.save(server: settings.host, securityDomain: settings.share,
                                        username: settings.username, password: "secret")
        }
    }

    func saved(_ settings: ConnectionSettings) -> Server {
        servers.servers.first { settings.matches($0) }!
    }

    func hasPassword(_ settings: ConnectionSettings) -> Bool {
        CredentialStore.shared.load(server: settings.host, securityDomain: settings.share) != nil
    }

    @Test func forgettingTheLastServerStopsReconnecting() {
        nas.save(to: defaults)
        defaults.set("Vaults/Notes", forKey: "vaultPath")
        let appState = AppState(defaults: defaults, servers: servers)
        #expect(appState.settings == nas)

        appState.forget(saved(nas))
        #expect(appState.settings == nil)
        #expect(appState.vaultPath == nil)
        #expect(!hasPassword(nas))
        #expect(servers.servers.map(\.server) == [pi.host])
        // Nothing comes back on the next launch.
        #expect(AppState(defaults: defaults, servers: ServerManager(defaults: defaults)).settings == nil)
        let restored = ServerManager(defaults: defaults)
        restored.restoreSavedServers()
        #expect(restored.servers.map(\.server) == [pi.host])
        CredentialStore.shared.delete(server: pi.host, securityDomain: pi.share)
    }

    @Test func forgettingAnotherServerKeepsTheLastOne() {
        nas.save(to: defaults)
        let appState = AppState(defaults: defaults, servers: servers)

        appState.forget(saved(pi))
        #expect(appState.settings == nas)
        #expect(hasPassword(nas))
        #expect(!hasPassword(pi))
        CredentialStore.shared.delete(server: nas.host, securityDomain: nas.share)
    }

    @Test func forgetsSettingsSavedByEarlierVersions() {
        defaults.set(nas.host, forKey: "host")
        defaults.set(nas.share, forKey: "share")
        let appState = AppState(defaults: defaults, servers: servers)
        #expect(appState.settings?.host == nas.host)

        appState.forget(saved(nas))
        #expect(ConnectionSettings.loadSaved(from: defaults) == nil)
        CredentialStore.shared.delete(server: pi.host, securityDomain: pi.share)
    }
}
