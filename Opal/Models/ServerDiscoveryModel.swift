//
//  ServerDiscoveryModel.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import Foundation
import Combine

class ServerDiscoveryModel: ObservableObject {
    @Published var discovered: [Service] = []
    @Published var saved: [Server] = []

    private var discoveryObserver: AnyCancellable?
    private var savedObserver: AnyCancellable?

    init() {
        discoveryObserver = NotificationCenter.default
            .publisher(for: ServiceDiscovery.serviceDidDiscover)
            .sink { [weak self] _ in
                self?.discovered = Array(ServiceDiscovery.shared.services)
            }

        savedObserver = NotificationCenter.default
            .publisher(for: ServerManager.serversDidUpdate)
            .sink { [weak self] _ in
                self?.saved = ServerManager.shared.servers
            }

        ServiceDiscovery.shared.start()
        ServerManager.shared.restoreSavedServers()
        discovered = Array(ServiceDiscovery.shared.services)
        saved = ServerManager.shared.servers
    }
}