// Lezer Markdown extensions for Obsidian-specific syntax: YAML frontmatter,
// [[wikilinks]], ![[embeds]], ==highlights== and #tags. Also the markers a
// merge leaves where both sides changed the same lines.

import { styleTags, tags as t } from "@lezer/highlight"

const FRONTMATTER_RE = /^---[ \t]*\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/

const Frontmatter = {
  defineNodes: [{ name: "Frontmatter", block: true }],
  parseBlock: [{
    name: "Frontmatter",
    before: "HorizontalRule",
    parse(cx, line) {
      if (cx.lineStart !== 0 || !/^---[ \t]*$/.test(line.text) || !cx.input) return false
      const head = cx.input.read(0, Math.min(cx.input.length, 64 * 1024))
      if (!FRONTMATTER_RE.test(head)) return false
      const start = cx.lineStart
      while (cx.nextLine()) {
        if (/^(---|\.\.\.)[ \t]*$/.test(line.text)) {
          const end = cx.lineStart + line.text.length
          cx.nextLine()
          cx.addElement(cx.elt("Frontmatter", start, end))
          return true
        }
      }
      return false
    },
  }],
  props: [styleTags({ Frontmatter: t.meta })],
}

// `<<<<<<< Your edits`, `=======` and `>>>>>>> Other edits`, as git writes them.
// Without this, `=======` would turn the line above into a heading and
// `>>>>>>>` would be a quote.
const CONFLICT_MARKER_RE = /^(?:(?:<{7}|>{7})(?:[ \t].*)?|={7}[ \t]*)$/

const ConflictMarkers = {
  defineNodes: [{ name: "ConflictMarker", block: true }],
  parseBlock: [{
    name: "ConflictMarker",
    before: "Blockquote",
    parse(cx, line) {
      if (line.indent > 0 || !CONFLICT_MARKER_RE.test(line.text)) return false
      cx.addElement(cx.elt("ConflictMarker", cx.lineStart, cx.lineStart + line.text.length))
      cx.nextLine()
      return true
    },
    endLeaf: (cx, line) => line.indent === 0 && CONFLICT_MARKER_RE.test(line.text),
  }],
  props: [styleTags({ ConflictMarker: t.meta })],
}

function bracketLink(name, prefix) {
  return {
    name,
    before: name === "Embed" ? "Image" : "Link",
    parse(cx, next, pos) {
      for (let i = 0; i < prefix.length; i++) {
        if (cx.char(pos + i) !== prefix.charCodeAt(i)) return -1
      }
      const rest = cx.slice(pos + prefix.length, cx.end)
      const close = rest.indexOf("]]")
      if (close <= 0) return -1
      const inner = rest.slice(0, close)
      if (inner.includes("\n") || inner.includes("[")) return -1
      const end = pos + prefix.length + close + 2
      return cx.addElement(cx.elt(name, pos, end, [
        cx.elt("WikiLinkMark", pos, pos + prefix.length),
        cx.elt("WikiLinkMark", end - 2, end),
      ]))
    },
  }
}

const WikiLinks = {
  defineNodes: ["WikiLink", "Embed", "WikiLinkMark"],
  parseInline: [bracketLink("Embed", "![["), bracketLink("WikiLink", "[[")],
  props: [styleTags({
    "WikiLink Embed": t.link,
    WikiLinkMark: t.processingInstruction,
  })],
}

const Highlight = {
  defineNodes: ["Highlight", "HighlightMark"],
  parseInline: [{
    name: "Highlight",
    parse(cx, next, pos) {
      if (next !== 61 || cx.char(pos + 1) !== 61) return -1
      const rest = cx.slice(pos + 2, cx.end)
      const close = rest.indexOf("==")
      if (close <= 0 || /^\s/.test(rest) || rest.slice(0, close).includes("\n")) return -1
      const end = pos + 2 + close + 2
      return cx.addElement(cx.elt("Highlight", pos, end, [
        cx.elt("HighlightMark", pos, pos + 2),
        cx.elt("HighlightMark", end - 2, end),
      ]))
    },
  }],
  props: [styleTags({ HighlightMark: t.processingInstruction })],
}

const TAG_RE = /^#[\p{L}\p{N}_/-]*[\p{L}_/-][\p{L}\p{N}_/-]*/u

const Tags = {
  defineNodes: ["Tag"],
  parseInline: [{
    name: "Tag",
    parse(cx, next, pos) {
      if (next !== 35) return -1
      const prev = cx.char(pos - 1)
      if (prev !== -1 && !/\s/.test(String.fromCharCode(prev))) return -1
      const match = TAG_RE.exec(cx.slice(pos, cx.end))
      if (!match) return -1
      return cx.addElement(cx.elt("Tag", pos, pos + match[0].length))
    },
  }],
  props: [styleTags({ Tag: t.labelName })],
}

export const obsidianSyntax = [Frontmatter, ConflictMarkers, WikiLinks, Highlight, Tags]
