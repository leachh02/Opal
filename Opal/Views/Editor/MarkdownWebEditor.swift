//
//  MarkdownWebEditor.swift
//  Opal
//

import SwiftUI
import WebKit

/// Hosts the controller's web view. State lives in the controller, not here,
/// so SwiftUI can recreate this struct freely.
struct MarkdownWebEditor: UIViewRepresentable {
    @ObservedObject var controller: MarkdownEditorController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}

/// Formatting buttons shown under the editor, since there is no Tab key or
/// shortcut bar on an iPhone keyboard.
struct MarkdownFormattingBar: View {
    let controller: MarkdownEditorController

    var body: some View {
        HStack(spacing: 0) {
            button("checklist", "Toggle task", .task)
            button("decrease.indent", "Outdent", .outdent)
            button("increase.indent", "Indent", .indent)
            button("bold", "Bold", .bold)
            button("italic", "Italic", .italic)
            button("highlighter", "Highlight", .highlight)
            button("chevron.left.forwardslash.chevron.right", "Code", .code)
            button("arrow.uturn.backward", "Undo", .undo)
            button("arrow.uturn.forward", "Redo", .redo)
        }
    }

    private func button(_ systemImage: String, _ label: String, _ command: MarkdownEditorController.Command) -> some View {
        Button {
            controller.exec(command)
        } label: {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity, minHeight: 32)
        }
        .accessibilityLabel(label)
    }
}

#if DEBUG
/// Launch with `-OpalEditorDemo` to try the editor without an SMB server.
struct EditorDemoView: View {
    @StateObject private var editor = MarkdownEditorController()

    var body: some View {
        NavigationStack {
            MarkdownWebEditor(controller: editor)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle("Editor demo")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(editor.mode == .live ? "Source" : "Preview") {
                            editor.mode = editor.mode == .live ? .source : .live
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        MarkdownFormattingBar(controller: editor)
                    }
                }
        }
        .onAppear {
            editor.setNoteNames(["Daily Note", "Projects", "Reading List"])
            editor.setContent(Self.sample)
        }
    }

    static let sample = """
    ---
    tags: [demo]
    ---
    # Opal editor demo

    Some **bold**, *italic*, ~~strike~~, ==highlight== and `inline code`. A #tag here.

    Link to [[Daily Note]] and [[Projects|an alias]], plus [a website](https://example.com).

    > [!tip] Live preview
    > Tap a line to see its Markdown.

    - Bullet
    \t- Nested bullet
    - [ ] Tap the box to tick me
    - [x] Already done

    | Col A | Col B |
    | ----- | ----- |
    | 1     | 2     |

    ```swift
    let answer = 42
    ```

    """
}
#endif
