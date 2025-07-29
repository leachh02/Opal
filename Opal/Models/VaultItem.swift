//
//  VaultItem.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//


import Foundation

enum VaultItem: Identifiable {
    case folder(name: String, path: String)
    case file(name: String, path: String)

    var id: String { path }
    var name: String {
        switch self {
        case .folder(let name, _), .file(let name, _): return name
        }
    }

    var path: String {
        switch self {
        case .folder(_, let path), .file(_, let path): return path
        }
    }
}
