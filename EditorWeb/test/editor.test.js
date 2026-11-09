// Tests for the editor's Markdown handling that don't need a page.
// Run with `npm test` in EditorWeb.

import assert from "node:assert/strict"
import { describe, test } from "node:test"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { ensureSyntaxTree } from "@codemirror/language"
import { EditorSelection, EditorState } from "@codemirror/state"
import { EditorView } from "@codemirror/view"
import { isResolved, linkKey, setLinkableNames } from "../src/live-preview.js"
import { obsidianSyntax } from "../src/obsidian-syntax.js"
import { alignment, splitRow, tablePreview } from "../src/tables.js"

const cells = (row) => splitRow(row).map((cell) => cell.text)

describe("splitting table rows", () => {
  test("splits on pipes and trims cells", () => {
    assert.deepEqual(cells("| a | b  |c|"), ["a", "b", "c"])
  })

  test("leading and trailing pipes are optional", () => {
    assert.deepEqual(cells("a | b"), ["a", "b"])
    assert.deepEqual(cells("| a | b"), ["a", "b"])
  })

  test("keeps empty cells in the middle", () => {
    assert.deepEqual(cells("| a |  | c |"), ["a", "", "c"])
  })

  test("escaped pipes stay in the cell", () => {
    assert.deepEqual(cells("| [[Plan\\|the plan]] | x |"), ["[[Plan\\|the plan]]", "x"])
  })

  test("pipes in inline code stay in the cell", () => {
    assert.deepEqual(cells("| `a | b` | ``c | ` d`` | e |"), ["`a | b`", "``c | ` d``", "e"])
  })

  test("records where each cell's text starts", () => {
    assert.deepEqual(splitRow("| a |  bb |").map((cell) => cell.offset), [2, 7])
  })
})

describe("column alignment", () => {
  test("reads colons in the separator row", () => {
    assert.deepEqual(cells("| --- | :-- | --: | :-: |").map(alignment), [null, "left", "right", "center"])
  })
})

describe("link resolution", () => {
  test("matches on the file name, ignoring case and .md", () => {
    assert.equal(linkKey("Projects/Plan.md"), "plan")
    assert.equal(linkKey(" Ideas "), "ideas")
    assert.equal(linkKey("photo.PNG"), "photo.png")
  })

  test("everything resolves until the vault is indexed", () => {
    setLinkableNames(null)
    assert.equal(isResolved("Anything"), true)
  })

  test("checks names once the vault is indexed", () => {
    setLinkableNames(new Set(["plan", "photo.png"]))
    assert.equal(isResolved("Plan#Goals"), true)
    assert.equal(isResolved("Archive/plan.md"), true)
    assert.equal(isResolved("photo.png"), true)
    assert.equal(isResolved("Missing"), false)
    // A link to a heading in the same note always resolves.
    assert.equal(isResolved("#Heading"), true)
    setLinkableNames(null)
  })
})

describe("tables in live preview", () => {
  const table = "| Name | Tags |\n| --- | :-: |\n| [[Plan]] | #work |"
  const doc = `Intro\n\n${table}\n\nOutro`
  const tableFrom = doc.indexOf("|")
  const tableTo = tableFrom + table.length

  function stateFor(text, cursor, focused) {
    let state = EditorState.create({
      doc: text,
      selection: EditorSelection.cursor(cursor),
      extensions: [markdown({ base: markdownLanguage, extensions: obsidianSyntax }), tablePreview],
    })
    ensureSyntaxTree(state, state.doc.length, 5000)
    // A change in focus is what the view would report; here it is dispatched by hand.
    const focusEffect = state.facet(EditorView.focusChangeEffect)[0](state, focused)
    return state.update({ effects: focusEffect }).state
  }

  function drawnTables(state) {
    const ranges = []
    for (const source of state.facet(EditorView.decorations)) {
      if (typeof source === "function") continue
      source.between(0, state.doc.length, (from, to, deco) => { if (deco.spec.block) ranges.push([from, to]) })
    }
    return ranges
  }

  test("draws a table as a grid", () => {
    assert.deepEqual(drawnTables(stateFor(doc, 0, false)), [[tableFrom, tableTo]])
  })

  test("shows the source while the cursor is in the table", () => {
    assert.deepEqual(drawnTables(stateFor(doc, tableFrom + 3, true)), [])
  })

  test("keeps the grid when the cursor is elsewhere", () => {
    assert.deepEqual(drawnTables(stateFor(doc, doc.length, true)), [[tableFrom, tableTo]])
  })

  test("keeps the grid when the editor isn't focused", () => {
    assert.deepEqual(drawnTables(stateFor(doc, tableFrom + 3, false)), [[tableFrom, tableTo]])
  })

  test("leaves tables in quotes and lists as text", () => {
    const quoted = "> | a | b |\n> | - | - |\n> | 1 | 2 |"
    assert.deepEqual(drawnTables(stateFor(quoted, 0, false)), [])
  })
})
