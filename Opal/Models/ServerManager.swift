import Foundation

class ServerManager {
  static let shared = ServerManager()
  static let serversDidUpdate = Notification.Name("ServerManagerServersDidUpdate")

  private(set) var servers = [Server]()

  private init() {}

  /// Saves a server, replacing any saved entry for the same share.
  func addServer(_ settings: ConnectionSettings) {
    let server = Server(
      id: ID(UUID().uuidString),
      displayName: settings.title,
      server: settings.host,
      port: settings.port,
      share: settings.share,
      username: settings.isGuest ? nil : settings.username
    )

    if let index = servers.firstIndex(of: server) {
      servers[index] = Server(
        id: servers[index].id, displayName: server.displayName, server: server.server,
        port: server.port, share: server.share, username: server.username
      )
    } else {
      servers.append(server)
    }
    persist()
  }

  func removeServer(_ server: Server) {
    guard let index = servers.firstIndex(of: server) else { return }
    servers.remove(at: index)
    persist()
  }

  private func persist() {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .binary
    if let data = try? encoder.encode(servers) {
      UserDefaults.standard.setValue(data, forKey: "servers")
    }
    NotificationCenter.default.post(name: Self.serversDidUpdate, object: self)
  }

  func restoreSavedServers() {
    guard let data = UserDefaults.standard.data(forKey: "servers") else {
      return
    }

    let decoder = PropertyListDecoder()
    guard let servers = try? decoder.decode([Server].self, from: data) else {
      return
    }
    guard !servers.isEmpty else { return }

    self.servers = servers
    NotificationCenter.default.post(name: Self.serversDidUpdate, object: self)
  }

  func server(for id: ID) -> Server? {
    servers.first { $0.id == id }
  }
}
