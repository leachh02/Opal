// Opal's Markdown editor: CodeMirror 6 running in a WKWebView.
//
// Swift drives it through `window.opal` and listens for messages posted to
// `window.webkit.messageHandlers.opal`:
//   { type: "ready" }
//   { type: "change", text }          debounced after edits
//   { type: "openWikiLink", target }  a rendered [[link]] was tapped
//   { type: "openURL", url }          a rendered [link](url) was tapped

import { autocompletion } from "@codemirror/autocomplete"
import { history, indentLess, indentMore, redo, undo, defaultKeymap, historyKeymap, indentWithTab } from "@codemirror/commands"
import { markdown, markdownLanguage } from "@codemirror/lang-markdown"
import { HighlightStyle, indentUnit, syntaxHighlighting } from "@codemirror/language"
import { languages } from "@codemirror/language-data"
import { Compartment, EditorSelection, EditorState } from "@codemirror/state"
import { EditorView, keymap } from "@codemirror/view"
import { tags as t } from "@lezer/highlight"
import { livePreview, toggleTaskAt } from "./live-preview.js"
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

let noteNames = []

function wikiLinkCompletions(context) {
  const match = context.matchBefore(/\[\[[^\]|\n]*/)
  if (!match) return null
  return {
    from: match.from + 2,
    options: noteNames.map((name) => ({ label: name, apply: name + "]]" })),
    validFor: /^[^\]|\n]*$/,
  }
}

const preview = new Compartment()

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
      EditorView.contentAttributes.of({ autocapitalize: "sentences", autocorrect: "on", spellcheck: "true" }),
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
  setNoteNames(names) {
    noteNames = Array.isArray(names) ? names : []
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
