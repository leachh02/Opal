//
//  TextMergeTests.swift
//  OpalTests
//

import Testing
@testable import Opal

struct TextMergeTests {
    private func merge(_ base: String, mine: String, theirs: String) -> TextMerge.Result {
        TextMerge.merge(base: base, mine: mine, theirs: theirs)
    }

    @Test func combinesChangesToDifferentLines() {
        let result = merge("a\nb\nc\nd", mine: "A\nb\nc\nd", theirs: "a\nb\nc\nD")
        #expect(result == .init(text: "A\nb\nc\nD", conflicts: 0))
    }

    @Test func keepsAdditionsFromBothSides() {
        let result = merge("one\ntwo\nthree", mine: "zero\none\ntwo\nthree", theirs: "one\ntwo\nthree\nfour")
        #expect(result == .init(text: "zero\none\ntwo\nthree\nfour", conflicts: 0))
    }

    @Test func keepsDeletionsFromBothSides() {
        let result = merge("a\nb\nc\nd\ne", mine: "a\nc\nd\ne", theirs: "a\nb\nc\ne")
        #expect(result == .init(text: "a\nc\ne", conflicts: 0))
    }

    @Test func sameChangeOnBothSidesIsntAConflict() {
        let result = merge("a\nb\nc", mine: "a\nB\nc", theirs: "a\nB\nc")
        #expect(result == .init(text: "a\nB\nc", conflicts: 0))
    }

    @Test func onlyOneSideChanged() {
        #expect(merge("a\nb", mine: "a\nb", theirs: "a\nx\nb").text == "a\nx\nb")
        #expect(merge("a\nb", mine: "a\nx\nb", theirs: "a\nb").text == "a\nx\nb")
    }

    @Test func marksLinesBothSidesChanged() {
        let result = merge("title\nold line\nend", mine: "title\nmy line\nend", theirs: "title\ntheir line\nend")
        #expect(result.conflicts == 1)
        #expect(result.text == """
            title
            \(TextMerge.mineMarker)
            my line
            \(TextMerge.separator)
            their line
            \(TextMerge.theirsMarker)
            end
            """)
    }

    @Test func mergesAroundAConflict() {
        let result = merge("a\nb\nc\nd\ne", mine: "A\nb\nmine\nd\ne", theirs: "a\nb\ntheirs\nd\nE")
        #expect(result.conflicts == 1)
        #expect(result.text.hasPrefix("A\nb\n\(TextMerge.mineMarker)\nmine\n"))
        #expect(result.text.hasSuffix("theirs\n\(TextMerge.theirsMarker)\nd\nE"))
    }

    @Test func keepsTheTrailingNewline() {
        #expect(merge("a\nb\nc\n", mine: "A\nb\nc\n", theirs: "a\nb\nC\n").text == "A\nb\nC\n")
    }

    @Test func changesToNeighbouringLinesConflict() {
        // As in git: with no unchanged line between them, it's not clear how they fit together.
        #expect(merge("a\nb\nc", mine: "A\nb\nc", theirs: "a\nB\nc").conflicts == 1)
    }

    @Test func bothAddingToAnEmptyNoteConflicts() {
        let result = merge("", mine: "mine", theirs: "theirs")
        #expect(result.conflicts == 1)
    }
}
