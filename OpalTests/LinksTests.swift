//
//  LinksTests.swift
//  OpalTests
//
//  How `[[links]]` resolve, are found in notes, and are rewritten after moves.
//

import Testing
@testable import Opal

@Suite("Resolving links")
struct LinkResolverTests {
    let resolver = LinkResolver(files: [
        "Home.md",
        "Projects/Plan.md",
        "Projects/Ideas.md",
        "Archive/Plan.md",
        "Archive/2024/Ideas.md",
        "Daily/Meeting 2025.01.03.md",
        "Attachments/photo.png",
    ])

    @Test func findsANoteByName() {
        #expect(resolver.resolve("Home", from: "Daily/Today.md") == "Home.md")
    }

    @Test func ignoresCase() {
        #expect(resolver.resolve("home", from: "Today.md") == "Home.md")
        #expect(resolver.resolve("ATTACHMENTS/PHOTO.PNG", from: "Today.md") == "Attachments/photo.png")
    }

    @Test func acceptsTheExtension() {
        #expect(resolver.resolve("Home.md", from: "Today.md") == "Home.md")
    }

    @Test func findsFilesWithOtherExtensions() {
        #expect(resolver.resolve("photo.png", from: "Home.md") == "Attachments/photo.png")
    }

    @Test func treatsDotsInANameAsPartOfTheName() {
        #expect(resolver.resolve("Meeting 2025.01.03", from: "Home.md") == "Daily/Meeting 2025.01.03.md")
    }

    @Test func prefersAFullPath() {
        #expect(resolver.resolve("Archive/Plan", from: "Projects/Ideas.md") == "Archive/Plan.md")
    }

    @Test func prefersTheLinkingNotesFolder() {
        #expect(resolver.resolve("Plan", from: "Archive/Notes.md") == "Archive/Plan.md")
        #expect(resolver.resolve("Plan", from: "Projects/Notes.md") == "Projects/Plan.md")
    }

    @Test func otherwisePrefersTheShortestPath() {
        #expect(resolver.resolve("Ideas", from: "Home.md") == "Projects/Ideas.md")
    }

    @Test func breaksTiesAlphabetically() {
        #expect(resolver.resolve("Plan", from: "Home.md") == "Archive/Plan.md")
    }

    @Test func returnsNilForMissingFiles() {
        #expect(resolver.resolve("Nowhere", from: "Home.md") == nil)
        #expect(resolver.resolve("Projects/Home", from: "Home.md") == nil)
    }

    @Test func linksByNameUnlessTheNameIsShared() {
        #expect(resolver.shortestLink(to: "Home.md") == "Home")
        #expect(resolver.shortestLink(to: "Archive/Plan.md") == "Archive/Plan")
        #expect(resolver.shortestLink(to: "Attachments/photo.png") == "photo.png")
    }

    @Test func namesNewNotes() {
        #expect(LinkResolver.noteFileName(for: " Ideas ") == "Ideas.md")
        #expect(LinkResolver.noteFileName(for: "Ideas.MD") == "Ideas.MD")
        #expect(LinkResolver.noteFileName(for: "v1.2") == "v1.2.md")
    }
}

@Suite("Finding links")
struct LinkScannerTests {
    @Test func findsLinksAndEmbeds() {
        let text = "See [[Plan]] and ![[photo.png]].\nAlso [[Ideas]]"
        #expect(LinkScanner.targets(in: text) == ["Plan", "photo.png", "Ideas"])
    }

    @Test func keepsOnlyTheFilePart() {
        let text = "[[Plan#Goals]] [[Plan#^block]] [[Plan|the plan]] [[Plan#Goals|goals]]"
        #expect(LinkScanner.targets(in: text) == ["Plan", "Plan", "Plan", "Plan"])
    }

    @Test func handlesEscapedPipesInTables() {
        #expect(LinkScanner.targets(in: "| [[Plan\\|the plan]] | x |") == ["Plan"])
    }

    @Test func skipsHeadingOnlyAndEmptyLinks() {
        #expect(LinkScanner.targets(in: "[[#Heading]] [[ ]] [[|text]]").isEmpty)
    }

    @Test func skipsInlineCode() {
        #expect(LinkScanner.targets(in: "`[[Code]]` ``a [[More]] b`` [[Real]]") == ["Real"])
    }

    @Test func treatsAnUnclosedBacktickAsText() {
        #expect(LinkScanner.targets(in: "a ` b [[Real]]") == ["Real"])
    }

    @Test func skipsFencedCode() {
        let text = """
        [[Before]]
        ```
        [[InFence]]
        ```
          ~~~
        [[InTildes]]
          ~~~
        [[After]]
        """
        #expect(LinkScanner.targets(in: text) == ["Before", "After"])
    }
}

@Suite("Rewriting links after a move")
struct LinkRewriterTests {
    @Test func updatesALinkToARenamedNote() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        #expect(rewriter.rewrite("See [[Plan]].", oldPath: "Home.md", newPath: "Home.md") == "See [[Roadmap]].")
    }

    @Test func keepsHeadingsBlocksAndDisplayText() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        let text = "[[Plan#Goals]] [[Plan#^b1]] [[Plan|the plan]] ![[Plan]]"
        #expect(rewriter.rewrite(text, oldPath: "Home.md", newPath: "Home.md")
                == "[[Roadmap#Goals]] [[Roadmap#^b1]] [[Roadmap|the plan]] ![[Roadmap]]")
    }

    @Test func leavesLinksThatStillResolve() {
        // Moving a uniquely named note to another folder doesn't change `[[Plan]]`.
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Projects/Plan.md"])
        #expect(rewriter.rewrite("[[Plan]]", oldPath: "Home.md", newPath: "Home.md") == nil)
    }

    @Test func writesAPathWhenTheNewNameIsShared() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Archive/Ideas.md", "Home.md"], moves: ["Plan.md": "Ideas.md"])
        #expect(rewriter.rewrite("[[Plan]]", oldPath: "Home.md", newPath: "Home.md") == "[[Ideas]]")
        // `[[Ideas]]` used to mean the archived note, which now needs its path.
        #expect(rewriter.rewrite("[[Ideas]]", oldPath: "Home.md", newPath: "Home.md") == "[[Archive/Ideas]]")
    }

    @Test func followsFilesInsideAMovedFolder() {
        let rewriter = LinkRewriter(
            filesBefore: ["Projects/Plan.md", "Projects/photo.png", "Archive/Plan.md", "Home.md"],
            moves: ["Projects/Plan.md": "Old/Plan.md", "Projects/photo.png": "Old/photo.png"]
        )
        #expect(rewriter.rewrite("[[Projects/Plan]] ![[photo.png]]", oldPath: "Home.md", newPath: "Home.md")
                == "[[Old/Plan]] ![[photo.png]]")
    }

    @Test func fixesLinksInANoteThatMoved() {
        // From Archive, `[[Plan]]` meant Archive/Plan; after moving to Projects it would mean Projects/Plan.
        let rewriter = LinkRewriter(
            filesBefore: ["Archive/Plan.md", "Projects/Plan.md", "Archive/Notes.md"],
            moves: ["Archive/Notes.md": "Projects/Notes.md"]
        )
        #expect(rewriter.rewrite("[[Plan]]", oldPath: "Archive/Notes.md", newPath: "Projects/Notes.md") == "[[Archive/Plan]]")
    }

    @Test func leavesBrokenLinksAndCodeAlone() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        let text = "[[Missing]] `[[Plan]]`\n```\n[[Plan]]\n```"
        #expect(rewriter.rewrite(text, oldPath: "Home.md", newPath: "Home.md") == nil)
    }

    @Test func keepsLineEndings() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        #expect(rewriter.rewrite("a\r\n[[Plan]]\r\nb", oldPath: "Home.md", newPath: "Home.md") == "a\r\n[[Roadmap]]\r\nb")
    }

    @Test func rewritesInsideTables() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        #expect(rewriter.rewrite("| [[Plan\\|p]] |", oldPath: "Home.md", newPath: "Home.md") == "| [[Roadmap\\|p]] |")
    }

    @Test func predictsWhichNotesChange() {
        let rewriter = LinkRewriter(filesBefore: ["Plan.md", "Ideas.md", "Home.md"], moves: ["Plan.md": "Roadmap.md"])
        #expect(rewriter.wouldChange(linkTargets: ["Plan"], oldPath: "Home.md", newPath: "Home.md"))
        #expect(!rewriter.wouldChange(linkTargets: ["Ideas", "Missing"], oldPath: "Home.md", newPath: "Home.md"))
        #expect(!rewriter.wouldChange(linkTargets: [], oldPath: "Home.md", newPath: "Home.md"))
    }
}
