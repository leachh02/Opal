//
//  AppState.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//

import Foundation
import SMBClient

/// App-wide state: which server we're connected to and which vault is open.
@MainActor
final class AppState: ObservableObject {
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    @Published private(set) var status: ConnectionStatus = .disconnected
    /// The last server connected to successfully.
    @Published private(set) var settings: ConnectionSettings?
    @Published private(set) var store: (any VaultStore)?
    /// The open vault's folder within the share; `""` is the share itself.
    @Published private(set) var vaultPath: String? {
        didSet { defaults.set(vaultPath, forKey: Self.vaultPathKey) }
    }

    var vault: Vault? {
        guard let store, let vaultPath else { return nil }
        return Vault(store: store, root: vaultPath)
    }

    private static let vaultPathKey = "vaultPath"
    private let defaults: UserDefaults
    private let connection = SMBConnectionService()
    /// Kept in memory so dropped sessions can be reopened even when the password isn't saved.
    private var password = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = ConnectionSettings.loadSaved(from: defaults)
        if let path = defaults.string(forKey: Self.vaultPathKey) {
            vaultPath = path
        } else if let legacy = defaults.string(forKey: "currentVaultPath"), !legacy.isEmpty {
            vaultPath = legacy
        }
    }

    /// Connects to a server from the connect screen. Throws a `ConnectionFailure` to show the user.
    func connect(_ newSettings: ConnectionSettings, password: String, rememberPassword: Bool = true) async throws {
        let previousStatus = status
        status = .connecting
        let accessor: TreeAccessor
        do {
            accessor = try await connection.connect(newSettings, password: password)
        } catch {
            // The connect screen shows this error itself.
            status = previousStatus
            throw error
        }

        if settings?.host != newSettings.host || settings?.share != newSettings.share {
            vaultPath = nil
        }
        settings = newSettings
        newSettings.save(to: defaults)
        self.password = password
        if !newSettings.isGuest && rememberPassword {
            CredentialStore.shared.save(
                server: newSettings.host,
                securityDomain: newSettings.share,
                username: newSettings.username,
                password: password
            )
        }
        ServerManager.shared.addServer(newSettings)
        openStore(with: accessor)
    }

    /// Reconnects to the saved server, e.g. at launch.
    func reconnect() async {
        guard let settings, store == nil, status != .connecting else { return }
        if !settings.isGuest {
            password = CredentialStore.shared.load(server: settings.host, securityDomain: settings.share)?.password ?? ""
        }
        status = .connecting
        do {
            openStore(with: try await connection.connect(settings, password: password))
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func openVault(at path: String) {
        vaultPath = path
    }

    func closeVault() {
        vaultPath = nil
    }

    /// Logs off. The vault is remembered for next time.
    func disconnect() async {
        await connection.disconnect()
        store = nil
        status = .disconnected
    }

    private func openStore(with accessor: TreeAccessor) {
        store = SMBVaultStore(accessor: accessor) { [weak self] in
            guard let self, let settings = self.settings else { throw ConnectionError.disconnected }
            return try await self.connection.connect(settings, password: self.password)
        }
        status = .connected
    }
}
