//
//  FileSearchTests.swift
//  OpalTests
//
//  Finding files and folders by name.
//

import Testing
@testable import Opal

@Suite("Searching file names")
struct FileSearchTests {
    let files = [
        "Plan.md",
        "Projects/Plan B.md",
        "Projects/Garden plan.md",
        "Archive/Old Plans.md",
        "Archive/Café notes.md",
        "Attachments/plan-sketch.png",
        "Daily/2025-01-03.md",
    ]
    let folders = ["Projects", "Archive", "Attachments", "Daily", "Planning"]

    func search(_ query: String) -> [String] {
        FileSearch.matches(query, files: files, folders: folders).map(\.path)
    }

    @Test func ranksTheWholeNameFirstThenStartsThenWords() {
        #expect(search("plan") == [
            "Plan.md",                      // the whole name
            "Projects/Plan B.md",           // starts with it, shortest name first
            "Planning",
            "Attachments/plan-sketch.png",
            "Archive/Old Plans.md",         // a later word starts with it
            "Projects/Garden plan.md",
        ])
    }

    @Test func ignoresCaseAndAccents() {
        #expect(search("CAFE") == ["Archive/Café notes.md"])
    }

    @Test func needsEveryWord() {
        #expect(search("plan garden") == ["Projects/Garden plan.md"])
        #expect(search("plan zebra").isEmpty)
    }

    @Test func matchesNamesNotFolders() {
        // "Projects" is a folder of plans, but only the folder itself is called that.
        #expect(search("projects") == ["Projects"])
    }

    @Test func notesMatchWithoutTheirExtension() {
        #expect(search("md").isEmpty)
        #expect(search("png") == ["Attachments/plan-sketch.png"])
    }

    @Test func findsFolders() {
        let match = FileSearch.matches("daily", files: files, folders: folders)
        #expect(match == [FileSearch.Match(path: "Daily", isDirectory: true)])
    }

    @Test func blankSearchesFindNothing() {
        #expect(search("").isEmpty)
        #expect(search("   ").isEmpty)
    }

    @Test func showsNotesWithoutTheirExtension() {
        #expect(FileSearch.searchName(.init(path: "Projects/Plan B.md", isDirectory: false)) == "Plan B")
        #expect(FileSearch.searchName(.init(path: "a/photo.png", isDirectory: false)) == "photo.png")
        #expect(FileSearch.searchName(.init(path: "Notes.md", isDirectory: true)) == "Notes.md")
    }

    @Test func stopsAtTheLimit() {
        let many = (1...300).map { "Note \($0).md" }
        #expect(FileSearch.matches("note", files: many, folders: [], limit: 50).count == 50)
    }
}
