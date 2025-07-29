//
//  SMBConnectionService.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import Foundation
import SMBClient

@MainActor
class SMBConnectionService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var treeAccessor: TreeAccessor? = nil
    @Published var error: String? = nil

    private(set) var client: SMBClient?

    func connect(host: String, port: String?, username: String, password: String, share: String) async {
        do {
            let smbClient: SMBClient
            if let port = port.flatMap(Int.init) {
                smbClient = SMBClient(host: host, port: port)
            } else {
                smbClient = SMBClient(host: host)
            }

            try await smbClient.login(username: username, password: password)

            self.client = smbClient
            self.treeAccessor = smbClient.treeAccessor(share: share)
            self.isConnected = true
            self.error = nil
        } catch {
            self.isConnected = false
            self.error = error.localizedDescription
        }
    }
}
