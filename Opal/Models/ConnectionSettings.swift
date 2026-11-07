//
//  ConnectionSettings.swift
//  Opal
//

import Foundation

/// Where to connect. The password is kept in the Keychain, never here.
struct ConnectionSettings: Codable, Equatable {
    var displayName: String?
    var host: String
    var port: Int?
    var share: String
    /// Empty for guest access.
    var username: String

    var isGuest: Bool { username.isEmpty }
    var title: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? host }
}

extension ConnectionSettings {
    private static let defaultsKey = "connectionSettings"

    static func loadSaved(from defaults: UserDefaults = .standard) -> ConnectionSettings? {
        if let data = defaults.data(forKey: defaultsKey),
           let settings = try? JSONDecoder().decode(ConnectionSettings.self, from: data) {
            return settings
        }
        // Settings saved by earlier versions, one key per field.
        guard let host = defaults.string(forKey: "host"), !host.isEmpty,
              let share = defaults.string(forKey: "share"), !share.isEmpty else { return nil }
        let username = CredentialStore.shared.load(server: host, securityDomain: share)?.username ?? ""
        return ConnectionSettings(
            displayName: defaults.string(forKey: "displayName"),
            host: host,
            port: defaults.string(forKey: "port").flatMap(Int.init),
            share: share,
            username: username
        )
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
