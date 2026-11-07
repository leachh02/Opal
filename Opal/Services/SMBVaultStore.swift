//
//  SMBVaultStore.swift
//  Opal
//

import Foundation
import Network
import SMBClient

/// A vault on an SMB share, read and written through SMBClient's TreeAccessor.
///
/// SMB sessions die while the app is suspended or the server times them out,
/// so when an operation fails because the connection is gone, the store asks
/// for a fresh session once and retries.
@MainActor
final class SMBVaultStore: VaultStore {
    typealias Reconnect = @MainActor () async throws -> TreeAccessor

    private var accessor: TreeAccessor
    private let reconnect: Reconnect
    private var reconnecting: Task<TreeAccessor, Error>?

    init(accessor: TreeAccessor, reconnect: @escaping Reconnect) {
        self.accessor = accessor
        self.reconnect = reconnect
    }

    func list(_ path: String, includeHidden: Bool) async throws -> [VaultItem] {
        try await perform { try await $0.listDirectory(path: path) }
            .filter { $0.name != "." && $0.name != ".." }
            .filter { includeHidden || (!$0.isHidden && !$0.name.hasPrefix(".")) }
            .map { file in
                VaultItem(
                    path: VaultPath.join([path, file.name]),
                    name: file.name,
                    isDirectory: file.isDirectory,
                    size: file.size,
                    modified: file.lastWriteTime
                )
            }
    }

    func read(_ path: String) async throws -> Data {
        try await perform { try await $0.download(path: path) }
    }

    func write(_ data: Data, to path: String) async throws {
        try await perform { try await $0.upload(content: data, path: path) }
    }

    func metadata(_ path: String) async throws -> VaultItemMetadata {
        let stat = try await perform { try await $0.fileStat(path: path) }
        return VaultItemMetadata(size: stat.size, isDirectory: stat.isDirectory, modified: stat.lastWriteTime)
    }

    /// SMBClient's `existFile` only treats OBJECT_NAME_NOT_FOUND as missing, but
    /// some servers (Impacket, for one) answer NO_SUCH_FILE, so stat the file instead.
    func fileExists(_ path: String) async throws -> Bool {
        do {
            _ = try await perform { try await $0.fileStat(path: path) }
            return true
        } catch let error as ErrorResponse {
            switch NTStatus(error.header.status) {
            case .objectNameNotFound, .objectPathNotFound, .noSuchFile:
                return false
            default:
                throw error
            }
        }
    }

    private func perform<T>(_ operation: (TreeAccessor) async throws -> T) async throws -> T {
        do {
            return try await operation(accessor)
        } catch where Self.isConnectionLost(error) {
            return try await operation(try await freshAccessor())
        }
    }

    /// Shares one reconnect between operations that fail at the same time.
    private func freshAccessor() async throws -> TreeAccessor {
        if let reconnecting { return try await reconnecting.value }
        let task = Task { try await reconnect() }
        reconnecting = task
        defer { reconnecting = nil }
        accessor = try await task.value
        return accessor
    }

    private static func isConnectionLost(_ error: Error) -> Bool {
        if let response = error as? ErrorResponse {
            switch NTStatus(response.header.status) {
            case .networkSessionExpired, .userSessionDeleted, .networkNameDeleted:
                return true
            default:
                return false
            }
        }
        return error is ConnectionError || error is NWError
    }
}
