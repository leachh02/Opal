// Opal's Markdown editor: CodeMirror 6 running in a WKWebView.
//
// Swift drives it through `window.opal` and listens for messages posted to
// `window.webkit.messageHandlers.opal`:
//   { type: "ready" }
//   { type: "change", text }          debounced after edits
//   { type: "openWikiLink", target }  a rendered [[link]] was tapped (the part before any `|`)
//   { type: "openURL", url }          a rendered [link](url) was tapped

import { autocompletion } from "@codemirror/autocomplete"
import { history, indentLess, indentMore, redo, undo, defaultKeymap, historyKeymap, indentWithTab } from "@codemirror/commands"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { HighlightStyle, indentUnit, syntaxHighlighting } from "@codemirror/language"
import { languages } from "@codemirror/language-data"
import { Compartment, EditorSelection, EditorState } from "@codemirror/state"
import { EditorView, keymap } from "@codemirror/view"
import { tags as t } from "@lezer/highlight"
import { linkKey, linkableNamesChanged, livePreview, setLinkableNames, toggleTaskAt } from "./live-preview.js"
import { obsidianSyntax } from "./obsidian-syntax.js"

const CHANGE_DEBOUNCE_MS = 300

function post(message) {
  const handler = window.webkit?.messageHandlers?.opal
  if (handler) handler.postMessage(message)
  else console.debug("[opal]", message)
}

const highlight = HighlightStyle.define([
  { tag: t.heading, fontWeight: "700" },
  { tag: t.strong, fontWeight: "700" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: [t.link, t.url], color: "var(--accent)" },
  { tag: [t.processingInstruction, t.contentSeparator, t.meta], color: "var(--muted)" },
  { tag: t.monospace, fontFamily: "var(--mono)" },
  { tag: t.labelName, color: "var(--accent)" },
  // Code block contents
  { tag: [t.keyword, t.modifier, t.operatorKeyword], color: "var(--code-keyword)" },
  { tag: [t.string, t.special(t.string), t.regexp], color: "var(--code-string)" },
  { tag: [t.number, t.bool, t.null, t.atom], color: "var(--code-number)" },
  { tag: [t.comment, t.lineComment, t.blockComment], color: "var(--muted)", fontStyle: "italic" },
  { tag: [t.typeName, t.className, t.namespace], color: "var(--code-type)" },
  { tag: [t.function(t.variableName), t.function(t.propertyName)], color: "var(--code-function)" },
])

// Files `[[` can complete: { name, link, folder }.
let linkTargets = []

function wikiLinkCompletions(context) {
  const match = context.matchBefore(/\[\[[^\]|#\n]*/)
  if (!match) return null
  return {
    from: match.from + 2,
    options: linkTargets.map((target) => ({ label: target.name, detail: target.folder || undefined, apply: target.link + "]]" })),
    validFor: /^[^\]|#\n]*$/,
  }
}

/** Moves the cursor to a `#heading` or `#^block` without focusing, so the note stays rendered. */
function revealSubpath(subpath) {
  const doc = view.state.doc
  const wanted = subpath.trim().toLowerCase()
  const block = wanted.startsWith("^") ? wanted : null
  for (let n = 1; n <= doc.lines; n++) {
    const line = doc.line(n)
    const text = line.text.trim().toLowerCase()
    const found = block
      ? text.endsWith(" " + block) || text === block
      : /^#{1,6}\s/.test(text) && text.replace(/^#{1,6}\s+/, "").replace(/\s+#+$/, "") === wanted
    if (found) {
      view.dispatch({ selection: { anchor: line.from }, effects: EditorView.scrollIntoView(line.from, { y: "start", yMargin: 16 }) })
      return true
    }
  }
  return false
}

const preview = new Compartment()
const typing = new Compartment()
let typingAttributes = { autocapitalize: "sentences", autocorrect: "on", spellcheck: "true" }

function createState(text) {
  return EditorState.create({
    doc: text,
    extensions: [
      // Keep Windows line endings intact so saving doesn't rewrite every line.
      text.includes("\r\n") ? EditorState.lineSeparator.of("\r\n") : [],
      history(),
      keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
      markdown({ base: markdownLanguage, codeLanguages: languages, extensions: obsidianSyntax }),
      syntaxHighlighting(highlight),
      indentUnit.of("\t"),
      EditorState.tabSize.of(4),
      EditorView.lineWrapping,
      typing.of(EditorView.contentAttributes.of(typingAttributes)),
      autocompletion({ override: [wikiLinkCompletions], icons: false }),
      preview.of(livePreview),
      EditorView.updateListener.of((update) => { if (update.docChanged) scheduleChange() }),
    ],
  })
}

const view = new EditorView({ state: createState(""), parent: document.getElementById("editor") })

let changeTimer = null
function scheduleChange() {
  clearTimeout(changeTimer)
  changeTimer = setTimeout(() => post({ type: "change", text: view.state.doc.toString() }), CHANGE_DEBOUNCE_MS)
}

view.dom.addEventListener("opal-open-wikilink", (e) => post({ type: "openWikiLink", target: e.detail }))
view.dom.addEventListener("opal-open-embed", (e) => post({ type: "openEmbed", target: e.detail.target, kind: e.detail.kind }))
view.dom.addEventListener("opal-open-url", (e) => post({ type: "openURL", url: e.detail }))

/** Wrap each selection in `marker`, or unwrap it if it is already wrapped. */
function toggleWrap(marker) {
  const { state } = view
  const n = marker.length
  view.dispatch(state.changeByRange((range) => {
    const before = state.sliceDoc(range.from - n, range.from)
    const after = state.sliceDoc(range.to, range.to + n)
    if (before === marker && after === marker) {
      return {
        changes: [{ from: range.from - n, to: range.from }, { from: range.to, to: range.to + n }],
        range: EditorSelection.range(range.from - n, range.to - n),
      }
    }
    return {
      changes: [{ from: range.from, insert: marker }, { from: range.to, insert: marker }],
      range: EditorSelection.range(range.from + n, range.to + n),
    }
  }))
  view.focus()
}

/** Turn the selected lines into task items, or toggle them if they already are. */
function toggleTask() {
  const { state } = view
  const line = state.doc.lineAt(state.selection.main.head)
  const task = /^(\s*[-*+] )\[[ xX]\]/.exec(line.text)
  if (task) {
    toggleTaskAt(view, line.from + task[1].length)
  } else {
    const list = /^(\s*[-*+] )/.exec(line.text)
    const indent = /^\s*/.exec(line.text)[0]
    const insertAt = list ? line.from + list[1].length : line.from + indent.length
    view.dispatch({ changes: { from: insertAt, insert: list ? "[ ] " : "- [ ] " } })
  }
  view.focus()
}

const commands = {
  bold: () => toggleWrap("**"),
  italic: () => toggleWrap("*"),
  strikethrough: () => toggleWrap("~~"),
  highlight: () => toggleWrap("=="),
  code: () => toggleWrap("`"),
  task: toggleTask,
  indent: () => indentMore(view),
  outdent: () => indentLess(view),
  undo: () => undo(view),
  redo: () => redo(view),
}

window.opal = {
  /** Replace the document, resetting undo history and the cursor. */
  setContent(text) {
    clearTimeout(changeTimer)
    view.setState(createState(text))
  },
  getContent() {
    return view.state.doc.toString()
  },
  /** "live" renders Markdown in place; "source" shows the raw text. */
  setMode(mode) {
    view.dispatch({ effects: preview.reconfigure(mode === "source" ? [] : livePreview) })
  },
  /** Settings from the Settings screen: `textScale` is a percentage of the iPhone's text size. */
  setOptions({ textScale, autocorrect, spellcheck }) {
    document.documentElement.style.setProperty("--text-scale", String(textScale / 100))
    typingAttributes = { autocapitalize: "sentences", autocorrect: autocorrect ? "on" : "off", spellcheck: String(spellcheck) }
    view.dispatch({ effects: typing.reconfigure(EditorView.contentAttributes.of(typingAttributes)) })
  },
  /** Files that `[[links]]` can point at, for autocomplete and to dim links to missing notes. */
  setLinkTargets(targets) {
    linkTargets = Array.isArray(targets) ? targets : []
    setLinkableNames(new Set(linkTargets.map((target) => linkKey(target.name))))
    view.dispatch({ effects: linkableNamesChanged.of(null) })
  },
  /** Scrolls to `heading` or `^block-id` from a link like `[[note#heading]]`. */
  revealSubpath(subpath) {
    return revealSubpath(subpath)
  },
  exec(name) {
    const command = commands[name]
    if (!command) return false
    command()
    return true
  },
  focus() {
    view.focus()
  },
}

post({ type: "ready" })
