//
//  FileSearch.swift
//  Opal
//
//  Finding files and folders by name, from the note index's list of the
//  vault, so nothing is downloaded.
//

import Foundation

enum FileSearch {
    struct Match: Equatable {
        /// Vault-relative path.
        let path: String
        let isDirectory: Bool
    }

    /// Files and folders whose name contains every word of `query`, ignoring case
    /// and accents. Notes match without their `.md`. Best matches come first:
    /// the whole name, then names starting with the query, then words in the name
    /// starting with it, then the rest; shorter names first within each.
    static func matches(_ query: String, files: [String], folders: [String], limit: Int = 200) -> [Match] {
        let words = query.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !words.isEmpty else { return [] }
        let phrase = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))

        let candidates = folders.map { Match(path: $0, isDirectory: true) } + files.map { Match(path: $0, isDirectory: false) }
        let ranked: [(match: Match, rank: Int, name: String)] = candidates.compactMap { match in
            let name = fold(searchName(match))
            guard words.allSatisfy(name.contains) else { return nil }
            return (match, rank(name, phrase: phrase), name)
        }
        return ranked
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                if $0.name.count != $1.name.count { return $0.name.count < $1.name.count }
                return $0.match.path.localizedStandardCompare($1.match.path) == .orderedAscending
            }
            .prefix(limit)
            .map(\.match)
    }

    /// The name shown and searched: notes without their extension, as in Obsidian.
    static func searchName(_ match: Match) -> String {
        let name = VaultPath.name(of: match.path)
        guard !match.isDirectory, FileKind(fileName: name) == .markdown else { return name }
        return (name as NSString).deletingPathExtension
    }

    private static func rank(_ name: String, phrase: String) -> Int {
        if name == phrase { return 0 }
        if name.hasPrefix(phrase) { return 1 }
        if name.contains(" " + phrase) || name.contains("-" + phrase) || name.contains("_" + phrase) { return 2 }
        return 3
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
