// Obsidian-style live preview: Markdown syntax is hidden and rendered in
// place, and revealed again on the lines the cursor is on. The document text
// itself is never transformed, so what is saved is exactly what was typed.

import { syntaxTree } from "@codemirror/language"
import { StateEffect } from "@codemirror/state"
import { Decoration, ViewPlugin, WidgetType } from "@codemirror/view"

// Lowercased names that `[[links]]` can point at, or null until the vault has
// been indexed (links aren't marked unresolved before then).
let linkableNames = null

/** Dispatch this after `setLinkableNames` so links are restyled. */
export const linkableNamesChanged = StateEffect.define()

export function setLinkableNames(names) {
  linkableNames = names
}

/** The key a link target is matched on: its file name, lowercased, with `.md` implied. */
export function linkKey(target) {
  const name = target.split("/").pop().trim().toLowerCase()
  return name.endsWith(".md") ? name.slice(0, -3) : name
}

function isResolved(target) {
  const name = target.split("#")[0]
  return linkableNames == null || name.trim() === "" || linkableNames.has(linkKey(name))
}

class CheckboxWidget extends WidgetType {
  constructor(checked) { super(); this.checked = checked }
  eq(other) { return other.checked === this.checked }
  toDOM(view) {
    const box = document.createElement("span")
    box.className = "cm-task-checkbox" + (this.checked ? " cm-task-checked" : "")
    box.setAttribute("role", "checkbox")
    box.setAttribute("aria-checked", String(this.checked))
    // Toggle on tap without moving the cursor or raising the keyboard. Cancelling
    // touchend on iOS also cancels the click that would follow it.
    box.addEventListener("touchend", (e) => {
      e.preventDefault()
      toggleTaskAt(view, view.posAtDOM(box))
    })
    box.addEventListener("mousedown", (e) => e.preventDefault())
    box.addEventListener("click", (e) => {
      e.preventDefault()
      toggleTaskAt(view, view.posAtDOM(box))
    })
    return box
  }
  ignoreEvent() { return true }
}

class TextWidget extends WidgetType {
  constructor(text, className) { super(); this.text = text; this.className = className }
  eq(other) { return other.text === this.text && other.className === this.className }
  toDOM() {
    const span = document.createElement("span")
    span.className = this.className
    span.textContent = this.text
    return span
  }
}

class RuleWidget extends WidgetType {
  eq() { return true }
  toDOM() {
    const hr = document.createElement("span")
    hr.className = "cm-hr"
    return hr
  }
}

const bullet = Decoration.replace({ widget: new TextWidget("•", "cm-bullet") })
const hide = Decoration.replace({})
const rule = Decoration.replace({ widget: new RuleWidget() })

/** Flip the `[ ]` / `[x]` marker of the task item that starts at or after `pos` on its line. */
export function toggleTaskAt(view, pos) {
  const line = view.state.doc.lineAt(pos)
  const offset = pos - line.from
  const match = /\[([ xX])\]/.exec(line.text.slice(offset))
  if (!match) return false
  const at = line.from + offset + match.index + 1
  view.dispatch({ changes: { from: at, to: at + 1, insert: match[1] === " " ? "x" : " " } })
  return true
}

function buildDecorations(view) {
  const { state } = view
  const doc = state.doc
  const focused = view.hasFocus
  const selection = state.selection.ranges.map((r) => ({
    from: doc.lineAt(r.from).from,
    to: doc.lineAt(r.to).to,
    exactFrom: r.from,
    exactTo: r.to,
  }))
  // A span is "active" (shows raw syntax) when it shares a line with the cursor.
  const lineActive = (from, to) => focused && selection.some((r) => from <= r.to && to >= r.from)
  // A span is "touched" when the cursor is inside or right next to it.
  const touched = (from, to) => focused && selection.some((r) => from <= r.exactTo && to >= r.exactFrom)

  const decos = []
  let replacedUntil = -1
  const replace = (from, to, deco = hide) => {
    if (from >= to && !deco.spec.widget) return
    if (from < replacedUntil) return
    replacedUntil = to
    decos.push(deco.range(from, to))
  }
  const mark = (from, to, cls, attributes) => {
    if (from < to) decos.push(Decoration.mark({ class: cls, attributes }).range(from, to))
  }
  const lineClass = (from, to, cls) => {
    for (let pos = from; pos <= to;) {
      const line = doc.lineAt(pos)
      decos.push(Decoration.line({ class: cls }).range(line.from))
      pos = line.to + 1
    }
  }

  for (const { from, to } of view.visibleRanges) {
    syntaxTree(state).iterate({
      from, to,
      enter(ref) {
        const node = ref.node
        const name = node.name
        const active = lineActive(node.from, node.to)

        if (/^(ATX|Setext)Heading(\d)$/.test(name)) {
          lineClass(node.from, node.to, "cm-heading cm-h" + name.slice(-1))
          return
        }

        switch (name) {
          case "Frontmatter":
            lineClass(node.from, node.to, "cm-frontmatter")
            return false

          case "HeaderMark": {
            if (active) return
            const isSetext = node.parent?.name.startsWith("Setext")
            const after = doc.sliceString(node.to, node.to + 1)
            replace(node.from, isSetext ? node.to : node.to + (after === " " ? 1 : 0))
            return
          }

          case "EmphasisMark":
          case "StrikethroughMark":
          case "HighlightMark":
            if (!active) replace(node.from, node.to)
            return

          case "Highlight":
            mark(node.from, node.to, "cm-highlight")
            return

          case "InlineCode":
            mark(node.from, node.to, "cm-inline-code")
            if (!active) {
              for (const m of node.getChildren("CodeMark")) replace(m.from, m.to)
            }
            return false

          case "FencedCode": {
            const first = doc.lineAt(node.from)
            const last = doc.lineAt(node.to)
            decos.push(Decoration.line({ class: "cm-codeblock cm-codeblock-begin" }).range(first.from))
            if (last.number > first.number + 1) lineClass(doc.line(first.number + 1).from, doc.line(last.number - 1).from, "cm-codeblock")
            if (last.number > first.number) decos.push(Decoration.line({ class: "cm-codeblock cm-codeblock-end" }).range(last.from))
            if (!touched(node.from, node.to)) {
              const info = node.getChild("CodeInfo")
              const label = info ? doc.sliceString(info.from, info.to) : ""
              replace(first.from, first.to, Decoration.replace({ widget: new TextWidget(label, "cm-code-lang") }))
              const marks = node.getChildren("CodeMark")
              const closing = marks.length > 1 ? marks[marks.length - 1] : null
              if (closing && last.number > first.number) replace(last.from, last.to)
            }
            return false
          }

          case "Blockquote": {
            lineClass(node.from, node.to, "cm-blockquote")
            const first = doc.lineAt(node.from)
            const callout = /^(\s*>\s*)\[!([\w-]+)\][+-]?(\s*)(.*)$/.exec(first.text)
            if (callout) {
              const type = callout[2].toLowerCase()
              lineClass(node.from, node.to, "cm-callout cm-callout-" + type)
              decos.push(Decoration.line({ class: "cm-callout-title" }).range(first.from))
              if (!lineActive(first.from, first.to)) {
                // Hide the leading "> [!type]" too; the label widget stands in for it.
                const start = first.from
                const end = first.from + callout[0].length - callout[4].length
                const title = callout[4] ? "" : type.charAt(0).toUpperCase() + type.slice(1)
                replace(start, end, Decoration.replace({ widget: new TextWidget(title, "cm-callout-label") }))
              }
            }
            return
          }

          case "QuoteMark": {
            if (lineActive(node.from, node.to)) return
            const after = doc.sliceString(node.to, node.to + 1)
            replace(node.from, node.to + (after === " " ? 1 : 0))
            return
          }

          case "ListMark": {
            const item = node.parent
            const task = item?.getChild("Task")
            const marker = task?.getChild("TaskMarker")
            if (marker) {
              const checked = /x/i.test(doc.sliceString(marker.from, marker.to))
              if (checked) mark(marker.to, task.to, "cm-task-done")
              if (!touched(node.from, marker.to)) {
                replace(node.from, marker.to, Decoration.replace({ widget: new CheckboxWidget(checked) }))
              }
            } else if (item?.parent?.name === "BulletList" && !touched(node.from, node.to)) {
              replace(node.from, node.to, bullet)
            }
            return
          }

          case "HorizontalRule":
            if (!lineActive(node.from, node.to)) replace(node.from, node.to, rule)
            return

          case "Link": {
            const marks = node.getChildren("LinkMark")
            const url = node.getChild("URL")
            if (marks.length < 2) return
            const labelFrom = marks[0].to
            const labelTo = marks[1].from
            const href = url ? doc.sliceString(url.from, url.to) : ""
            mark(labelFrom, labelTo, active ? "cm-link" : "cm-link cm-link-rendered", { "data-href": href })
            if (!active && url) {
              replace(marks[0].from, marks[0].to)
              replace(marks[1].from, node.to)
            }
            return
          }

          case "Image": {
            if (active) return false
            const marks = node.getChildren("LinkMark")
            const alt = marks.length >= 2 ? doc.sliceString(marks[0].to, marks[1].from) : ""
            replace(node.from, node.to, Decoration.replace({ widget: new TextWidget(alt || "Image", "cm-embed cm-image") }))
            return false
          }

          case "URL":
            if (node.parent?.name !== "Link" && node.parent?.name !== "Image") {
              mark(node.from, node.to, active ? "cm-url" : "cm-url cm-link-rendered", { "data-href": doc.sliceString(node.from, node.to) })
            }
            return

          case "WikiLink": {
            const inner = doc.sliceString(node.from + 2, node.to - 2)
            const pipe = inner.indexOf("|")
            const target = pipe >= 0 ? inner.slice(0, pipe) : inner
            const textFrom = node.from + 2 + (!active && pipe >= 0 ? pipe + 1 : 0)
            if (!active) {
              replace(node.from, textFrom)
              replace(node.to - 2, node.to)
            }
            const cls = "cm-wikilink" + (isResolved(target) ? "" : " cm-wikilink-unresolved")
            mark(active ? node.from : textFrom, active ? node.to : node.to - 2,
              active ? cls : cls + " cm-link-rendered", { "data-target": target })
            return false
          }

          case "Embed": {
            if (active) return false
            const target = doc.sliceString(node.from + 3, node.to - 2).split("|")[0]
            replace(node.from, node.to, Decoration.replace({ widget: new TextWidget(target, "cm-embed") }))
            return false
          }

          case "Tag":
            mark(node.from, node.to, "cm-tag")
            return

          case "Table":
            lineClass(node.from, node.to, "cm-table")
            return

          case "TableDelimiter": {
            const line = doc.lineAt(node.from)
            if (/^\s*\|?\s*:?-/.test(line.text) && node.from <= line.from + 1) {
              decos.push(Decoration.line({ class: "cm-table-delimiter" }).range(line.from))
            }
            return
          }
        }
      },
    })
  }

  return Decoration.set(decos, true)
}

function renderedLink(target) {
  return target instanceof Element ? target.closest(".cm-link-rendered") : null
}

function openLink(view, el) {
  const target = el.getAttribute("data-target")
  if (target != null) view.dom.dispatchEvent(new CustomEvent("opal-open-wikilink", { detail: target, bubbles: true }))
  else view.dom.dispatchEvent(new CustomEvent("opal-open-url", { detail: el.getAttribute("data-href"), bubbles: true }))
}

const TAP_SLOP_PX = 10

export const livePreview = ViewPlugin.fromClass(class {
  constructor(view) {
    this.decorations = buildDecorations(view)
    this.pendingTap = null
  }
  update(update) {
    if (update.docChanged || update.viewportChanged || update.selectionSet || update.focusChanged ||
        syntaxTree(update.startState) !== syntaxTree(update.state) ||
        update.transactions.some((tr) => tr.effects.some((e) => e.is(linkableNamesChanged)))) {
      this.decorations = buildDecorations(update.view)
    }
  }
}, {
  decorations: (plugin) => plugin.decorations,
  // Tapping a rendered link opens it instead of placing the cursor.
  eventHandlers: {
    // iOS moves the selection before it sends mouse events, so taps are handled
    // as touches; cancelling touchend stops the cursor moving and the keyboard opening.
    touchstart(event) {
      const el = renderedLink(event.target)
      const touch = event.touches[0]
      this.pendingTap = el && event.touches.length === 1 ? { el, x: touch.clientX, y: touch.clientY } : null
      return false
    },
    touchmove(event) {
      const touch = event.touches[0]
      if (this.pendingTap && Math.hypot(touch.clientX - this.pendingTap.x, touch.clientY - this.pendingTap.y) > TAP_SLOP_PX) {
        this.pendingTap = null
      }
      return false
    },
    touchend(event, view) {
      const tap = this.pendingTap
      this.pendingTap = null
      if (!tap) return false
      event.preventDefault()
      openLink(view, tap.el)
      return true
    },
    mousedown(event, view) {
      const el = renderedLink(event.target)
      if (!el) return false
      event.preventDefault()
      openLink(view, el)
      return true
    },
  },
})
