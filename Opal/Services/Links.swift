//
//  Links.swift
//  Opal
//
//  How `[[links]]` find their files, and how they're rewritten when files
//  move. Plain values with no app state, so they can be tested on their own.
//

import Foundation

/// Resolves `[[link]]` targets against a list of vault-relative file paths,
/// following Obsidian: a matching path wins, then a file in the linking note's
/// folder, then the one with the shortest path. Matching ignores case.
struct LinkResolver {
    let files: [String]
    /// Files by lowercased name, so a lookup doesn't scan the whole vault.
    private let filesByName: [String: [String]]

    init(files: [String]) {
        self.files = files
        filesByName = Dictionary(grouping: files) { VaultPath.name(of: $0).lowercased() }
    }

    func resolve(_ target: String, from notePath: String) -> String? {
        // `[[photo.png]]` is a file with an extension, but `[[Meeting 2025.01.03]]`
        // is a note whose name has a dot, so try the name as written, then as a note.
        for name in Self.fileNames(for: target) {
            if let match = resolve(fileName: name.lowercased(), from: notePath) { return match }
        }
        return nil
    }

    private func resolve(fileName wanted: String, from notePath: String) -> String? {
        let candidates = (filesByName[VaultPath.name(of: wanted)] ?? []).filter { file in
            let lowered = file.lowercased()
            return lowered == wanted || lowered.hasSuffix("/" + wanted)
        }
        guard !candidates.isEmpty else { return nil }

        let folder = VaultPath.parent(of: notePath).lowercased()
        return candidates.first { $0.lowercased() == wanted }
            ?? candidates.first { VaultPath.parent(of: $0).lowercased() == folder }
            ?? candidates.min { a, b in
                let (depthA, depthB) = (a.split(separator: "/").count, b.split(separator: "/").count)
                return depthA != depthB ? depthA < depthB : a.localizedStandardCompare(b) == .orderedAscending
            }
    }

    /// How a link to `file` is written: just its name if no other file shares it,
    /// otherwise its path from the vault root (Obsidian's "shortest path when possible").
    func shortestLink(to file: String) -> String {
        let shared = (filesByName[VaultPath.name(of: file).lowercased()]?.count ?? 0) > 1
        return Self.linkName(for: shared ? file : VaultPath.name(of: file))
    }

    /// The file names a link target could mean, most likely first.
    static func fileNames(for target: String) -> [String] {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasSuffix(".md") { return [trimmed] }
        return (trimmed as NSString).pathExtension.isEmpty ? [trimmed + ".md"] : [trimmed, trimmed + ".md"]
    }

    /// The file a new note for `target` is saved as.
    static func noteFileName(for target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespaces)
        return trimmed.lowercased().hasSuffix(".md") ? trimmed : trimmed + ".md"
    }

    /// Notes are linked without their `.md`; other files keep their extension.
    static func linkName(for path: String) -> String {
        (path as NSString).pathExtension.lowercased() == "md" ? (path as NSString).deletingPathExtension : path
    }
}

/// Updates `[[links]]` and `![[embeds]]` in a note after files were moved or
/// renamed, so they keep pointing at the same files.
///
/// A link is only touched when it pointed at a file before the move and would
/// now point somewhere else (or nowhere). Only its target changes: headings,
/// block references and display text are kept. Links in code are left alone.
struct LinkRewriter {
    /// Vault-relative files before the move.
    let before: LinkResolver
    /// Vault-relative files after the move.
    let after: LinkResolver
    /// Old path → new path for every file that moved.
    let moves: [String: String]
    /// Lowercased names of moved files, before and after. A link can only
    /// resolve differently after a move if it names one of them.
    private let movedNames: Set<String>

    init(filesBefore: [String], moves: [String: String]) {
        before = LinkResolver(files: filesBefore)
        after = LinkResolver(files: filesBefore.map { moves[$0] ?? $0 })
        self.moves = moves
        movedNames = Set(moves.flatMap { [VaultPath.name(of: $0).lowercased(), VaultPath.name(of: $1).lowercased()] })
    }

    /// The note's text with its links updated, or nil if none needed changing.
    /// `oldPath` and `newPath` are where the note itself was and now is.
    func rewrite(_ text: String, oldPath: String, newPath: String) -> String? {
        var changed = false
        let rewritten = LinkScanner.mapLinkLines(in: text) { line in
            var result = line as NSString
            // Replace from the end so earlier ranges stay valid.
            for target in LinkScanner.targetRanges(in: line).reversed() {
                let name = result.substring(with: target)
                guard let replacement = newTarget(for: name, oldPath: oldPath, newPath: newPath) else { continue }
                result = result.replacingCharacters(in: target, with: replacement) as NSString
                changed = true
            }
            return result as String
        }
        return changed ? rewritten : nil
    }

    /// Whether `rewrite` would change a note with these link targets, so notes
    /// that wouldn't change needn't be read.
    func wouldChange(linkTargets targets: [String], oldPath: String, newPath: String) -> Bool {
        // A note that moved itself can see any link resolve differently, since
        // links prefer files in the note's own folder.
        let moved = oldPath != newPath
        return targets.contains { target in
            (moved || namesMovedFile(target))
                && newTarget(for: target, oldPath: oldPath, newPath: newPath) != nil
        }
    }

    private func namesMovedFile(_ target: String) -> Bool {
        LinkResolver.fileNames(for: target).contains { movedNames.contains(VaultPath.name(of: $0).lowercased()) }
    }

    /// The link target to write instead of `name`, or nil to leave it as it is.
    private func newTarget(for name: String, oldPath: String, newPath: String) -> String? {
        guard let pointedAt = before.resolve(name, from: oldPath) else { return nil }
        let intended = moves[pointedAt] ?? pointedAt
        if after.resolve(name, from: newPath) == intended { return nil }
        return after.shortestLink(to: intended)
    }
}

/// Finds `[[links]]` and `![[embeds]]` in a note's text, leaving out any in code.
enum LinkScanner {
    /// The target of every link in `text`: the part before any `#` or `|`.
    static func targets(in text: String) -> [String] {
        var found: [String] = []
        _ = mapLinkLines(in: text) { line in
            let ns = line as NSString
            found += targetRanges(in: line).map { ns.substring(with: $0) }
            return line
        }
        return found
    }

    /// Passes each line that has a link, outside fenced code, through `transform`.
    static func mapLinkLines(in text: String, _ transform: (String) -> String) -> String {
        var inFence = false
        // Splitting on "\n" keeps any "\r" with its line, so line endings survive.
        return text.components(separatedBy: "\n").map { line -> String in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }
            guard !inFence, line.contains("[[") else { return line }
            return transform(line)
        }.joined(separator: "\n")
    }

    private static let wikiLink = try! NSRegularExpression(pattern: #"\[\[([^\[\]\n]+?)\]\]"#)

    /// Where each link's target is in `line`, in order, leaving out links in inline code.
    static func targetRanges(in line: String) -> [NSRange] {
        let ns = line as NSString
        let code = codeSpans(in: ns)
        return wikiLink.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            if code.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { return nil }
            guard let target = targetRange(in: ns, inner: match.range(at: 1)),
                  !ns.substring(with: target).trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return target
        }
    }

    /// The file part of a link's inside: before any `#heading`, `#^block` or `|display text`.
    /// In tables the pipe is escaped as `\|`, and the backslash isn't part of the target.
    private static func targetRange(in line: NSString, inner: NSRange) -> NSRange? {
        let content = line.substring(with: inner) as NSString
        var end = content.length
        for separator in ["|", "#"] {
            let found = content.range(of: separator)
            if found.location != NSNotFound { end = min(end, found.location) }
        }
        if end > 0, content.substring(with: NSRange(location: end - 1, length: 1)) == "\\",
           end < content.length, content.substring(with: NSRange(location: end, length: 1)) == "|" {
            end -= 1
        }
        guard end > 0 else { return nil }
        return NSRange(location: inner.location, length: end)
    }

    /// Ranges of inline code (`` `code` ``, ``` ``code`` ```) in a line.
    private static func codeSpans(in line: NSString) -> [NSRange] {
        var spans: [NSRange] = []
        var index = 0
        while index < line.length {
            guard line.character(at: index) == 0x60 else { index += 1; continue }
            var run = 0
            while index + run < line.length, line.character(at: index + run) == 0x60 { run += 1 }
            // Find a closing run of exactly the same length.
            var search = index + run
            var closed = false
            while search < line.length {
                guard line.character(at: search) == 0x60 else { search += 1; continue }
                var closing = 0
                while search + closing < line.length, line.character(at: search + closing) == 0x60 { closing += 1 }
                if closing == run {
                    spans.append(NSRange(location: index, length: search + closing - index))
                    index = search + closing
                    closed = true
                    break
                }
                search += closing
            }
            if !closed { index += run }
        }
        return spans
    }
}
