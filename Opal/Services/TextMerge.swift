//
//  TextMerge.swift
//  Opal
//
//  Combining edits made here with edits made to the same note somewhere else,
//  line by line, as git does.
//

import Foundation

enum TextMerge {
    struct Result: Equatable {
        let text: String
        /// How many places both sides changed the same lines. Each is kept
        /// with both versions between conflict markers.
        let conflicts: Int
    }

    static let mineMarker = "<<<<<<< Your edits"
    static let separator = "======="
    static let theirsMarker = ">>>>>>> Other edits"

    /// Merges `mine` and `theirs`, both edited from `base`. Changes to different
    /// lines are combined. Where both changed the same lines differently, both
    /// versions are kept, marked, with `mine` first.
    static func merge(base: String, mine: String, theirs: String) -> Result {
        let baseLines = lines(base), mineLines = lines(mine), theirLines = lines(theirs)
        let inMine = matches(from: baseLines, to: mineLines)
        let inTheirs = matches(from: baseLines, to: theirLines)

        var output: [String] = []
        var conflicts = 0
        // The last line all three share, as indexes into each.
        var (b, m, t) = (-1, -1, -1)

        func takeChunk(upTo next: (Int, Int, Int)) {
            let baseChunk = baseLines[(b + 1)..<next.0]
            let mineChunk = mineLines[(m + 1)..<next.1]
            let theirChunk = theirLines[(t + 1)..<next.2]
            if mineChunk == theirChunk || theirChunk == baseChunk {
                output += mineChunk
            } else if mineChunk == baseChunk {
                output += theirChunk
            } else {
                conflicts += 1
                output.append(mineMarker)
                output += mineChunk
                output.append(separator)
                output += theirChunk
                output.append(theirsMarker)
            }
        }

        for line in baseLines.indices {
            guard let mineLine = inMine[line], let theirLine = inTheirs[line] else { continue }
            takeChunk(upTo: (line, mineLine, theirLine))
            output.append(baseLines[line])
            (b, m, t) = (line, mineLine, theirLine)
        }
        takeChunk(upTo: (baseLines.count, mineLines.count, theirLines.count))

        return Result(text: output.joined(separator: "\n"), conflicts: conflicts)
    }

    private static func lines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    /// For each line of `old`, the line of `new` it's unchanged as, if any.
    private static func matches(from old: [String], to new: [String]) -> [Int?] {
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result = [Int?](repeating: nil, count: old.count)
        var next = 0
        for line in old.indices where !removed.contains(line) {
            while inserted.contains(next) { next += 1 }
            result[line] = next
            next += 1
        }
        return result
    }
}
