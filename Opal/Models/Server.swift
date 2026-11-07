//
//  Server.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import Foundation

/// A saved server shown on the connect screen.
struct Server: Codable {
  let id: ID
  let displayName: String
  let server: String
  let port: Int?
  // Optional so servers saved by earlier versions still decode.
  let share: String?
  let username: String?

  init(id: ID, displayName: String, server: String, port: Int?, share: String?, username: String?) {
    self.id = id
    self.displayName = displayName
    self.server = server
    self.port = port
    self.share = share
    self.username = username
  }
}

extension Server: Hashable {
  // The same share on the same server is one entry, whatever its id.
  static func == (lhs: Server, rhs: Server) -> Bool {
    lhs.server == rhs.server && lhs.port == rhs.port && lhs.share == rhs.share
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(server)
    hasher.combine(port)
    hasher.combine(share)
  }
}
