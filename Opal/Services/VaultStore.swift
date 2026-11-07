//
//  VaultStore.swift
//  Opal
//
//  The file operations the app needs from wherever a vault lives. Views talk
//  to this instead of SMBClient, so other backends (local files, the Files
//  app) can be added later without touching them.
//

import Foundation

@MainActor
protocol VaultStore: AnyObject {
    /// Lists a directory, skipping `.`/`..` and, unless asked, hidden and dot files.
    func list(_ path: String, includeHidden: Bool) async throws -> [VaultItem]
    func read(_ path: String) async throws -> Data
    func write(_ data: Data, to path: String) async throws
    func metadata(_ path: String) async throws -> VaultItemMetadata
    func fileExists(_ path: String) async throws -> Bool
    func createFolder(_ path: String) async throws
    /// Moves or renames a file or folder. Fails rather than replace anything at `destination`.
    func move(_ path: String, to destination: String) async throws
}

extension VaultStore {
    func list(_ path: String) async throws -> [VaultItem] {
        try await list(path, includeHidden: false)
    }
}

/// An open vault: the store it lives in and the folder that is its root.
struct Vault {
    let store: any VaultStore
    let root: String
    /// Names the vault across launches, such as for caching what's in it. Empty if it has none.
    var id = ""

    func path(_ components: String...) -> String {
        VaultPath.join([root] + components)
    }
}

struct VaultItem: Identifiable, Hashable {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date

    var id: String { path }
    var kind: FileKind { isDirectory ? .folder : FileKind(fileName: name) }
}

struct VaultItemMetadata: Equatable {
    let size: UInt64
    let isDirectory: Bool
    let modified: Date
}

enum FileKind {
    case folder, markdown, canvas, image, audio, video, pdf, other

    init(fileName: String) {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "canvas": self = .canvas
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "svg", "avif": self = .image
        case "mp3", "m4a", "wav", "aac", "flac", "ogg", "3gp": self = .audio
        case "mp4", "mov", "m4v", "webm", "mkv", "ogv": self = .video
        case "pdf": self = .pdf
        default: self = .other
        }
    }

    var systemImage: String {
        switch self {
        case .folder: "folder"
        case .markdown: "doc.text"
        case .canvas: "rectangle.on.rectangle"
        case .image: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .pdf: "doc.richtext"
        case .other: "doc"
        }
    }
}

enum VaultPath {
    static func join(_ components: [String]) -> String {
        components
            .flatMap { $0.split(separator: "/") }
            .joined(separator: "/")
    }

    static func parent(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }

    static func name(of path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
