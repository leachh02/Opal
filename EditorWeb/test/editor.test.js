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
import { addColumn, addRow, alignment, columnAt, splitRow, tablePreview } from "../src/tables.js"

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

describe("adding table rows", () => {
  /** Adds a row with the cursor at `marker`'s position, returning the text with `^` at the new cursor. */
  function add(text) {
    const pos = text.indexOf("^")
    const state = EditorState.create({ doc: text.replace("^", "") })
    const lines = text.replace("^", "").split("\n")
    const first = state.doc.line(1)
    const last = state.doc.line(lines.length)
    const result = state.update(addRow(state.doc, first, last, pos)).state
    const cursor = result.selection.main.head
    return result.doc.sliceString(0, cursor) + "^" + result.doc.sliceString(cursor)
  }

  test("adds an empty row below the cursor's row", () => {
    assert.equal(add("| a | b |\n| - | - |\n| 1^ | 2 |\n| 3 | 4 |"),
      "| a | b |\n| - | - |\n| 1 | 2 |\n| ^ |  |\n| 3 | 4 |")
  })

  test("adds at the end from the last row", () => {
    assert.equal(add("| a | b | c |\n| - | - | - |\n| 1 | 2 | 3^ |"),
      "| a | b | c |\n| - | - | - |\n| 1 | 2 | 3 |\n| ^ |  |  |")
  })

  test("adds the first body row from the header or separator", () => {
    assert.equal(add("| a^ | b |\n| - | - |\n| 1 | 2 |"), "| a | b |\n| - | - |\n| ^ |  |\n| 1 | 2 |")
    assert.equal(add("| a | b |\n| -^ | - |"), "| a | b |\n| - | - |\n| ^ |  |")
  })

  test("follows a header without outer pipes", () => {
    assert.equal(add("a | b\n- | -\n1^ | 2"), "a | b\n- | -\n1 | 2\n ^ |  ")
  })

  test("counts escaped pipes as part of a cell", () => {
    assert.equal(add("| [[a\\|b]] | c |\n| - | - |^"), "| [[a\\|b]] | c |\n| - | - |\n| ^ |  |")
  })
})

describe("adding table columns", () => {
  /** Adds a column after column `after`, returning the text with `^` at the new cursor. */
  function add(text, after) {
    const state = EditorState.create({ doc: text })
    const first = state.doc.line(1)
    const last = state.doc.line(state.doc.lines)
    const result = state.update(addColumn(state.doc, first, last, after)).state
    const cursor = result.selection.main.head
    return result.doc.sliceString(0, cursor) + "^" + result.doc.sliceString(cursor)
  }

  test("adds an empty column at the end, with the cursor in its header", () => {
    assert.equal(add("| a | b |\n| - | - |\n| 1 | 2 |"),
      "| a | b | ^ |\n| - | - | --- |\n| 1 | 2 |  |")
  })

  test("adds after a given column", () => {
    assert.equal(add("| a | b |\n| - | - |\n| 1 | 2 |", 0),
      "| a | ^ | b |\n| - | --- | - |\n| 1 |  | 2 |")
  })

  test("fills out short rows so the column lines up", () => {
    assert.equal(add("| a | b |\n| - | - |\n| 1 |"), "| a | b | ^ |\n| - | - | --- |\n| 1 |  |  |")
  })

  test("follows a header without outer pipes", () => {
    assert.equal(add("a | b\n- | -\n1 | 2"), "a | b | ^ \n- | - | --- \n1 | 2 |  ")
  })

  test("finds the cursor's column", () => {
    const row = "| ab | cd | ef |"
    assert.equal(columnAt(row, row.indexOf("ab")), 0)
    assert.equal(columnAt(row, row.indexOf("cd") + 1), 1)
    assert.equal(columnAt(row, row.length), 2)
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

  function blockDecorations(state) {
    const found = []
    for (const source of state.facet(EditorView.decorations)) {
      if (typeof source === "function") continue
      source.between(0, state.doc.length, (from, to, deco) => { if (deco.spec.block) found.push({ from, to, deco }) })
    }
    return found
  }

  const drawnTables = (state) =>
    blockDecorations(state).filter(({ from, to }) => to > from).map(({ from, to }) => [from, to])
  const addRowButtons = (state) =>
    blockDecorations(state).filter(({ from, to }) => to === from).map(({ from }) => from)

  /** The classes given to each line, for lines that have any. */
  function lineClasses(state) {
    const found = {}
    for (const source of state.facet(EditorView.decorations)) {
      if (typeof source === "function") continue
      source.between(0, state.doc.length, (from, to, deco) => {
        if (deco.spec.class) found[state.doc.lineAt(from).number] = deco.spec.class
      })
    }
    return found
  }

  test("shows the add-row bar under a table being edited", () => {
    assert.deepEqual(addRowButtons(stateFor(doc, tableFrom + 3, true)), [tableTo])
  })

  test("draws the add-column bar beside a table being edited, with the + in the middle", () => {
    // The table is lines 3 to 5.
    assert.deepEqual(lineClasses(stateFor(doc, tableFrom + 3, true)), {
      3: "cm-table-edit-line cm-table-edit-first",
      4: "cm-table-edit-line cm-table-edit-plus",
      5: "cm-table-edit-line cm-table-edit-last",
    })
  })

  test("shows no bars when not editing the table", () => {
    for (const state of [stateFor(doc, 0, true), stateFor(doc, tableFrom + 3, false)]) {
      assert.deepEqual(addRowButtons(state), [])
      assert.deepEqual(lineClasses(state), {})
    }
  })

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
