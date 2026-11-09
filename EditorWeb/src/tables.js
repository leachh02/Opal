// Markdown tables drawn as a grid in live preview. A table shows its source
// again while the cursor is in it, and tapping a cell puts the cursor there.
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
  if (cells.length && text.slice(cells.at(-1).from, cells.at(-1).to).trim() === "" && /\|\s*$/.test(text)) cells.pop()
  return cells.map(({ from, to }) => {
    const raw = text.slice(from, to)
    const lead = raw.length - raw.trimStart().length
    return { text: raw.trim(), offset: from + lead }
  })
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
      if (!editing) {
        const widget = new TableWidget(doc.sliceString(first.from, last.to), linksVersion)
        decos.push(Decoration.replace({ widget, block: true }).range(first.from, last.to))
      }
      return false
    },
  })
  return Decoration.set(decos)
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
]
