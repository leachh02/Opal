//
//  SMBConnectionService.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//

import Foundation
import Network
import SMBClient

/// Owns the SMB session: logging in, checking the share, and logging off.
@MainActor
final class SMBConnectionService {
    private var client: SMBClient?

    /// Logs in and opens the share, replacing any existing session.
    func connect(_ settings: ConnectionSettings, password: String) async throws -> TreeAccessor {
        if let previous = client {
            // The old session is often already dead (e.g. after the app was suspended), so don't wait on it.
            client = nil
            Task { _ = try? await previous.logoff() }
        }

        let client = settings.port.map { SMBClient(host: settings.host, port: $0) } ?? SMBClient(host: settings.host)
        do {
            try await client.login(username: settings.username, password: password)
            // The accessor copies the session's negotiated state, so it must be made after login.
            let accessor = client.treeAccessor(share: settings.share)
            // The share is only opened on first use, so list it now to report a bad share name here.
            _ = try await accessor.listDirectory(path: "")
            self.client = client
            return accessor
        } catch {
            throw ConnectionFailure(error, settings: settings)
        }
    }

    func disconnect() async {
        guard let client else { return }
        self.client = nil
        _ = try? await client.logoff()
    }
}

/// A connection error with a message worth showing to the user.
struct ConnectionFailure: LocalizedError {
    let errorDescription: String?

    init(_ error: Error, settings: ConnectionSettings) {
        let host = settings.host
        let share = settings.share
        if let response = error as? ErrorResponse {
            switch NTStatus(response.header.status) {
            case .logonFailure:
                errorDescription = "The username or password is incorrect."
            case .badNetworkName, .objectPathNotFound, .objectNameNotFound:
                errorDescription = "There's no share called “\(share)” on \(host)."
            case .accessDenied:
                errorDescription = "This account doesn't have access to “\(share)”."
            default:
                errorDescription = response.localizedDescription
            }
        } else if error is NWError {
            errorDescription = "Couldn't reach \(host). Check the address and that you're on the same network."
        } else if error is ConnectionError {
            errorDescription = "\(host) closed the connection."
        } else {
            errorDescription = "Couldn't connect to \(host): \(error.localizedDescription)"
        }
    }
}
