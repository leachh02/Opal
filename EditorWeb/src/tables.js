// Markdown tables drawn as a grid in live preview. A table shows its source
// again while the cursor is in it, with bars beside and under it to add a
// column or a row, and tapping a cell puts the cursor there.
//
// Unlike the rest of live preview these are block decorations, which
// CodeMirror only accepts from a state field, not a view plugin.

import { syntaxTree } from "@codemirror/language"
import { StateEffect, StateField } from "@codemirror/state"
import { Decoration, EditorView, WidgetType } from "@codemirror/view"
import { isResolved, linkableNamesChanged } from "./live-preview.js"

const TAP_SLOP_PX = 10

const setFocused = StateEffect.define()

/** Whether the editor has focus, kept in state since a state field can't ask the view. */
const focusedField = StateField.define({
  create: () => false,
  update(value, tr) {
    for (const e of tr.effects) if (e.is(setFocused)) value = e.value
    return value
  },
})

/** A table's first and last lines, if it can be drawn: tables inside quotes or lists stay as text. */
export function tableLines(doc, node) {
  const first = doc.lineAt(node.from)
  if (doc.sliceString(first.from, node.from).trim() !== "") return null
  const end = doc.sliceString(node.to - 1, node.to) === "\n" ? node.to - 1 : node.to
  return { first, last: doc.lineAt(Math.max(node.from, end)) }
}

/** Splits a row on its unescaped pipes, keeping each cell's offset within the line. */
export function splitRow(text) {
  return cellBounds(text).cells.map(({ from, to }) => {
    const raw = text.slice(from, to)
    const lead = raw.length - raw.trimStart().length
    return { text: raw.trim(), offset: from + lead }
  })
}

/**
 * Where each cell of a row starts and ends, untrimmed. A cell ends at the pipe
 * after it, or at the end of the line; `trailingPipe` says which for the last.
 */
function cellBounds(text) {
  const cells = []
  let start = 0
  let ticks = 0
  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if (ch === "\\") { i++; continue }
    if (ch === "`") {
      let run = 1
      while (text[i + run] === "`") run++
      ticks = ticks === 0 ? run : ticks === run ? 0 : ticks
      i += run - 1
      continue
    }
    if (ch === "|" && ticks === 0) {
      cells.push({ from: start, to: i })
      start = i + 1
    }
  }
  cells.push({ from: start, to: text.length })
  // Leading and trailing pipes are optional and don't start cells.
  if (text.slice(cells[0].from, cells[0].to).trim() === "" && /^\s*\|/.test(text)) cells.shift()
  const trailingPipe = cells.length > 0 && text.slice(cells.at(-1).from, cells.at(-1).to).trim() === "" && /\|\s*$/.test(text)
  if (trailingPipe) cells.pop()
  return { cells, trailingPipe }
}

/** The column of the cell at `offset` in a row. */
export function columnAt(text, offset) {
  const { cells } = cellBounds(text)
  const index = cells.findIndex((cell) => offset <= cell.to)
  return index === -1 ? Math.max(0, cells.length - 1) : index
}

/**
 * The change that adds an empty column to the table from `first` to `last`,
 * after column `after` (the last, if not given), with the cursor in its header.
 * Rows that are short of cells are filled out first, so the new column lines up.
 */
export function addColumn(doc, first, last, after) {
  const columns = Math.max(1, splitRow(first.text).length)
  const index = Math.min(after ?? columns - 1, columns - 1)
  const changes = []
  let cursor = null
  for (let n = first.number; n <= last.number; n++) {
    const line = doc.line(n)
    const { cells, trailingPipe } = cellBounds(line.text)
    const blank = n === first.number + 1 ? " --- " : "  "
    let at, insert
    if (cells.length > index + 1) {
      // A pipe follows the cell, so the new one goes just before that pipe.
      at = cells[index].to
      insert = "|" + blank
    } else {
      // The new cell goes at the end, after any cells this row is missing.
      const missing = index + 1 - cells.length
      at = trailingPipe ? cells.at(-1).to : line.text.length
      insert = "|  ".repeat(missing) + "|" + blank
      if (!trailingPipe && !line.text.endsWith(" ")) insert = " " + insert
    }
    if (n === first.number) cursor = line.from + at + insert.lastIndexOf("|") + 2
    changes.push({ from: line.from + at, insert })
  }
  // Nothing is inserted before the header, so its position holds in the new document.
  return { changes, selection: { anchor: cursor }, scrollIntoView: true }
}

export function alignment(cell) {
  const left = cell.startsWith(":")
  const right = cell.endsWith(":")
  return left && right ? "center" : right ? "right" : left ? "left" : null
}

// Inline Markdown inside a cell: code, emphasis, highlights, links, embeds and tags.
const INLINE = new RegExp([
  /(`+)([\s\S]*?[^`])\1(?!`)/.source,
  /\*\*([\s\S]+?)\*\*/.source,
  /__([\s\S]+?)__/.source,
  /~~([\s\S]+?)~~/.source,
  /==([\s\S]+?)==/.source,
  /\*([^*\s](?:[\s\S]*?[^*\s])?)\*/.source,
  /\b_([^_\s](?:[\s\S]*?[^_\s])?)_\b/.source,
  /!\[\[([^\]]+)\]\]/.source,
  /\[\[([^\]]+)\]\]/.source,
  /\[([^\]]*)\]\(([^)\s]+)\)/.source,
  /(?<=^|\s)(#[\p{L}\p{N}_\/-]*[\p{L}_\/-][\p{L}\p{N}_\/-]*)/.source,
].join("|"), "gu")

function renderInline(text, parent) {
  let at = 0
  for (const m of text.matchAll(INLINE)) {
    if (m.index > at) parent.append(text.slice(at, m.index))
    at = m.index + m[0].length
    const element = (tag, className, content) => {
      const el = document.createElement(tag)
      if (className) el.className = className
      if (content != null) renderInline(content, el)
      parent.append(el)
      return el
    }
    if (m[1]) element("code", "cm-inline-code").textContent = m[2]
    else if (m[3] || m[4]) element("strong", null, m[3] ?? m[4])
    else if (m[5]) element("s", null, m[5])
    else if (m[6]) element("mark", "cm-highlight", m[6])
    else if (m[7] || m[8]) element("em", null, m[7] ?? m[8])
    else if (m[9]) {
      const [target, label] = m[9].split("|")
      element("span", "cm-embed").textContent = label?.trim() && !/^\d+(x\d+)?$/.test(label.trim()) ? label.trim() : target.trim()
    } else if (m[10]) {
      const [target, label] = m[10].split("|")
      const link = element("span", "cm-wikilink cm-link-rendered" + (isResolved(target) ? "" : " cm-wikilink-unresolved"))
      link.dataset.target = target.trim()
      link.textContent = (label ?? target).trim()
    } else if (m[12] !== undefined) {
      const link = element("span", "cm-link cm-link-rendered", m[11])
      link.dataset.href = m[12]
    } else if (m[13]) {
      element("span", "cm-tag").textContent = m[13]
    }
  }
  if (at < text.length) parent.append(text.slice(at))
}

class TableWidget extends WidgetType {
  /** `source` is the table's text; `linksVersion` redraws it when which notes exist changes. */
  constructor(source, linksVersion) { super(); this.source = source; this.linksVersion = linksVersion }
  eq(other) { return other.source === this.source && other.linksVersion === this.linksVersion }

  toDOM(view) {
    const lines = this.source.split("\n")
    let lineStart = 0
    const rows = lines.map((line) => {
      const row = { cells: splitRow(line), start: lineStart }
      lineStart += line.length + 1
      return row
    })
    const columns = rows[0].cells.length
    const aligns = rows[1].cells.map((cell) => alignment(cell.text))

    const wrap = document.createElement("div")
    wrap.className = "cm-table-wrap"
    const table = document.createElement("table")
    table.className = "cm-table-grid"
    rows.forEach((row, index) => {
      if (index === 1) return
      const tr = (index === 0 ? table.createTHead() : table.tBodies[0] ?? table.createTBody()).insertRow()
      for (let c = 0; c < columns; c++) {
        const cell = row.cells[c]
        const td = document.createElement(index === 0 ? "th" : "td")
        if (aligns[c]) td.style.textAlign = aligns[c]
        // Where the cell's text starts in the table, to put the cursor there when tapped.
        td.dataset.offset = String(row.start + (cell ? cell.offset : lines[index].length))
        // In a table, `[[note\|alias]]` escapes the pipe that would otherwise end the cell.
        if (cell) renderInline(cell.text.replace(/\\\|/g, "|"), td)
        tr.append(td)
      }
    })
    wrap.append(table)
    this.handleTaps(view, wrap)
    return wrap
  }

  /** A tap opens a link, or edits the table at the cell tapped. Drags scroll as usual. */
  handleTaps(view, wrap) {
    let start = null
    let lastTouch = 0
    const tap = (target, event) => {
      const link = target.closest(".cm-link-rendered")
      if (link) {
        // Cancelling the tap stops iOS placing the cursor and raising the keyboard.
        event.preventDefault()
        const wiki = link.dataset.target
        view.dom.dispatchEvent(wiki != null
          ? new CustomEvent("opal-open-wikilink", { detail: wiki, bubbles: true })
          : new CustomEvent("opal-open-url", { detail: link.dataset.href, bubbles: true }))
        return
      }
      const cell = target.closest("td, th")
      const offset = cell ? Number(cell.dataset.offset) : 0
      // Showing the source in the same step as moving the cursor keeps the cursor on real text.
      const edit = () => view.dispatch({ selection: { anchor: view.posAtDOM(wrap) + offset }, effects: setFocused.of(true) })
      if (view.hasFocus) {
        event.preventDefault()
        edit()
        return
      }
      // iOS only raises the keyboard for focus it gives itself, so let the tap focus
      // the editor, then move the cursor into the cell once iOS has placed it.
      const onFocus = () => setTimeout(edit, 50)
      view.contentDOM.addEventListener("focus", onFocus, { once: true })
      setTimeout(() => view.contentDOM.removeEventListener("focus", onFocus), 1000)
    }
    wrap.addEventListener("touchstart", (e) => {
      start = e.touches.length === 1 ? { x: e.touches[0].clientX, y: e.touches[0].clientY } : null
    }, { passive: true })
    wrap.addEventListener("touchmove", (e) => {
      const touch = e.touches[0]
      if (start && Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > TAP_SLOP_PX) start = null
    }, { passive: true })
    wrap.addEventListener("touchend", (e) => {
      if (!start) return
      start = null
      lastTouch = Date.now()
      tap(e.target, e)
    })
    // Without a touch screen, a click does the same. iOS also sends a click after a touch, which is skipped.
    wrap.addEventListener("click", (e) => {
      if (Date.now() - lastTouch < 1000) return
      tap(e.target, e)
      if (!view.hasFocus) view.focus()
    })
  }

  get estimatedHeight() { return (this.source.split("\n").length - 1) * 36 }
  ignoreEvent() { return true }
}

/**
 * The change that adds an empty row to the table from `first` to `last`, below
 * the row at `pos` (or below the header, for the header and separator rows),
 * with the cursor in its first cell.
 */
export function addRow(doc, first, last, pos) {
  const header = doc.line(first.number)
  const columns = Math.max(1, splitRow(header.text).length)
  // Follow the header's style: with or without pipes at the ends.
  const piped = /^\s*\|/.test(header.text)
  const cells = Array(columns).fill("  ").join("|")
  const row = piped ? `|${cells}|` : cells
  const current = doc.lineAt(Math.min(Math.max(pos, first.from), last.to))
  const after = current.number <= first.number + 1 ? doc.line(Math.min(first.number + 1, last.number)) : current
  return {
    changes: { from: after.to, insert: "\n" + row },
    // Between the first cell's two spaces, so typing gives `| text |`.
    selection: { anchor: after.to + 1 + (piped ? 2 : 1) },
    scrollIntoView: true,
  }
}

// While a table's text is being edited, a bar with a "+" runs down its right
// side to add a column after the cursor's, and one runs along the bottom to add
// a row below the cursor's, as in Obsidian. The side bar is drawn by the lines
// themselves (see `.cm-table-edit-line`), so it follows the text as it wraps.

const COLUMN_BAR_PX = 32

/** Adds a row below the cursor's row in the table at `tableFrom`. */
function addRowAtCursor(view, tableFrom) {
  const node = tableAt(view.state, tableFrom)
  const lines = node && tableLines(view.state.doc, node)
  if (lines) view.dispatch(addRow(view.state.doc, lines.first, lines.last, view.state.selection.main.head))
}

/** Adds a column after the cursor's column in the table at `tableFrom`. */
function addColumnAtCursor(view, tableFrom) {
  const node = tableAt(view.state, tableFrom)
  const lines = node && tableLines(view.state.doc, node)
  if (!lines) return
  const head = view.state.selection.main.head
  const line = view.state.doc.lineAt(Math.min(Math.max(head, lines.first.from), lines.last.to))
  view.dispatch(addColumn(view.state.doc, lines.first, lines.last, columnAt(line.text, head - line.from)))
}

/**
 * Runs `action` on a tap, taking the tap before the editor sees it so focus,
 * and the cursor, stay in the table.
 */
function onTap(element, action) {
  let lastTouch = 0
  element.addEventListener("touchstart", (e) => e.preventDefault(), { passive: false })
  element.addEventListener("touchend", (e) => { e.preventDefault(); lastTouch = Date.now(); action() })
  element.addEventListener("mousedown", (e) => e.preventDefault())
  element.addEventListener("click", (e) => { e.preventDefault(); if (Date.now() - lastTouch > 1000) action() })
}

/** The bar under a table being edited, which adds a row. */
class RowBarWidget extends WidgetType {
  constructor(tableFrom) { super(); this.tableFrom = tableFrom }
  eq(other) { return other.tableFrom === this.tableFrom }

  toDOM(view) {
    const bar = document.createElement("div")
    bar.className = "cm-table-add cm-table-add-row"
    bar.setAttribute("role", "button")
    bar.setAttribute("aria-label", "Add Row")
    bar.textContent = "+"
    onTap(bar, () => addRowAtCursor(view, this.tableFrom))
    return bar
  }

  ignoreEvent() { return true }
}

/** The start of the table whose text line `line` is, if it's being edited. */
function editedTableAt(view, line) {
  if (!line.classList.contains("cm-table-edit-line")) return null
  const pos = view.posAtDOM(line)
  const tree = syntaxTree(view.state)
  for (let node = tree.resolveInner(pos, 1); node; node = node.parent) {
    if (node.name === "Table") return view.state.doc.lineAt(node.from).from
  }
  return null
}

/** Whether a tap at `x` is on the column bar drawn at the right of `line`. */
function onColumnBar(line, x) {
  return x >= line.getBoundingClientRect().right - COLUMN_BAR_PX
}

/** Taps on the column bar beside a table being edited. */
const columnBarTaps = (() => {
  let pending = null
  const start = (view, event, x) => {
    const line = event.target.closest?.(".cm-table-edit-line")
    const tableFrom = line && onColumnBar(line, x) ? editedTableAt(view, line) : null
    if (tableFrom == null) { pending = null; return false }
    // Touches are cancelled when they end, as touchstart can't be in a passive listener.
    if (event.type === "mousedown") event.preventDefault()
    pending = tableFrom
    return true
  }
  const end = (view, event) => {
    if (pending == null) return false
    event.preventDefault()
    const tableFrom = pending
    pending = null
    addColumnAtCursor(view, tableFrom)
    return true
  }
  return EditorView.domEventHandlers({
    touchstart: (event, view) => start(view, event, event.touches[0]?.clientX ?? 0),
    touchend: (event, view) => end(view, event),
    touchmove: () => { pending = null; return false },
    mousedown: (event, view) => start(view, event, event.clientX),
    mouseup: (event, view) => end(view, event),
  })
})()

/** The table node starting at `from`. */
function tableAt(state, from) {
  let found = null
  syntaxTree(state).iterate({
    from, to: from,
    enter(node) {
      if (node.name === "Table" && state.doc.lineAt(node.from).from === from) found = node.node
      return !found
    },
  })
  return found
}

let linksVersion = 0

function buildTables(state) {
  const doc = state.doc
  const focused = state.field(focusedField)
  const decos = []
  syntaxTree(state).iterate({
    enter(node) {
      if (node.name !== "Table") return
      const lines = tableLines(doc, node)
      if (!lines) return false
      const { first, last } = lines
      const editing = focused && state.selection.ranges.some((r) => r.from <= last.to && r.to >= first.from)
      if (editing) {
        // Each line draws its part of the column bar; the middle one shows the "+".
        const middle = Math.floor((first.number + last.number) / 2)
        for (let n = first.number; n <= last.number; n++) {
          const classes = ["cm-table-edit-line"]
          if (n === first.number) classes.push("cm-table-edit-first")
          if (n === last.number) classes.push("cm-table-edit-last")
          if (n === middle) classes.push("cm-table-edit-plus")
          decos.push(Decoration.line({ class: classes.join(" ") }).range(doc.line(n).from))
        }
        decos.push(Decoration.widget({ widget: new RowBarWidget(first.from), block: true, side: 1 }).range(last.to))
      } else {
        const widget = new TableWidget(doc.sliceString(first.from, last.to), linksVersion)
        decos.push(Decoration.replace({ widget, block: true }).range(first.from, last.to))
      }
      return false
    },
  })
  return Decoration.set(decos, true)
}

const tablesField = StateField.define({
  create: buildTables,
  update(decos, tr) {
    const linksChanged = tr.effects.some((e) => e.is(linkableNamesChanged))
    if (linksChanged) linksVersion++
    if (tr.docChanged || tr.selection || linksChanged || tr.effects.some((e) => e.is(setFocused)) ||
        syntaxTree(tr.startState) !== syntaxTree(tr.state)) {
      return buildTables(tr.state)
    }
    return decos
  },
  provide: (field) => EditorView.decorations.from(field),
})

export const tablePreview = [
  focusedField,
  EditorView.focusChangeEffect.of((_, focusing) => setFocused.of(focusing)),
  tablesField,
  columnBarTaps,
]
