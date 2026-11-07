//
//  MarkdownEditorController.swift
//  Opal
//
//  Owns the WKWebView that hosts the CodeMirror editor (EditorWeb/, bundled
//  into Resources/Editor) and bridges it to Swift.
//

import Foundation
import WebKit

@MainActor
final class MarkdownEditorController: NSObject, ObservableObject {
    enum Mode: String {
        case live
        case source
    }

    /// Formatting commands understood by `window.opal.exec` in the editor.
    enum Command: String {
        case bold, italic, strikethrough, highlight, code, task, indent, outdent, undo, redo
    }

    @Published private(set) var isReady = false
    /// The editor's latest text, updated shortly after each edit.
    @Published private(set) var text = ""
    @Published var mode: Mode = .live {
        didSet { if mode != oldValue { call("window.opal.setMode(mode)", ["mode": mode.rawValue]) } }
    }

    var onOpenWikiLink: ((String) -> Void)?
    var onOpenURL: ((URL) -> Void)?

    private var pendingContent: String?
    private var pendingLinkTargets: [[String: String]]?
    private var pendingSubpath: String?

    private(set) lazy var webView: WKWebView = makeWebView()

    /// An editor that has already loaded, since starting one takes longer than reading a note.
    private static var spare: MarkdownEditorController?

    /// A loaded editor if there is one, then starts loading the next.
    static func make() -> MarkdownEditorController {
        let controller = spare ?? MarkdownEditorController()
        spare = nil
        _ = controller.webView
        Task {
            // Wait for the note's own editor and push animation first.
            try? await Task.sleep(for: .seconds(1))
            prepareSpare()
        }
        return controller
    }

    /// Starts loading an editor for the next note to be opened.
    static func prepareSpare() {
        guard spare == nil else { return }
        let controller = MarkdownEditorController()
        _ = controller.webView
        spare = controller
    }

    func setContent(_ text: String) {
        self.text = text
        if isReady {
            call("window.opal.setContent(text)", ["text": text])
        } else {
            pendingContent = text
        }
    }

    /// Files offered when typing `[[`. Links to anything else are shown as unresolved.
    func setLinkTargets(_ targets: [NoteIndex.LinkTarget]) {
        let encoded = targets.map { ["name": $0.name, "link": $0.link, "folder": $0.folder] }
        if isReady {
            call("window.opal.setLinkTargets(targets)", ["targets": encoded])
        } else {
            pendingLinkTargets = encoded
        }
    }

    /// Scrolls to the `heading` or `^block-id` of a `[[note#heading]]` link.
    func reveal(subpath: String) {
        if isReady {
            call("window.opal.revealSubpath(subpath)", ["subpath": subpath])
        } else {
            pendingSubpath = subpath
        }
    }

    /// Reads the text straight from the editor, so it includes edits made within the change debounce.
    func currentContent() async -> String {
        guard isReady else { return text }
        do {
            if let content = try await webView.callAsyncJavaScript(
                "return window.opal.getContent()", arguments: [:], contentWorld: .page
            ) as? String {
                text = content
            }
        } catch {
            print("Failed to read editor content: \(error)")
        }
        return text
    }

    func exec(_ command: Command) {
        call("window.opal.exec(name)", ["name": command.rawValue])
    }

    private func call(_ script: String, _ arguments: [String: Any]) {
        guard isReady else { return }
        Task {
            do {
                _ = try await webView.callAsyncJavaScript(script, arguments: arguments, contentWorld: .page)
            } catch {
                print("Editor call failed (\(script)): \(error)")
            }
        }
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakMessageHandler(self), name: "opal")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        #if DEBUG
        webView.isInspectable = true
        #endif

        if let url = Bundle.main.url(forResource: "editor", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            assertionFailure("editor.html missing from bundle; run `npm run build` in EditorWeb/")
        }
        return webView
    }

    fileprivate func handle(_ body: Any) {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return }

        switch type {
        case "ready":
            isReady = true
            if let content = pendingContent {
                pendingContent = nil
                call("window.opal.setContent(text)", ["text": content])
            }
            if let targets = pendingLinkTargets {
                pendingLinkTargets = nil
                call("window.opal.setLinkTargets(targets)", ["targets": targets])
            }
            if let subpath = pendingSubpath {
                pendingSubpath = nil
                call("window.opal.revealSubpath(subpath)", ["subpath": subpath])
            }
            if mode != .live {
                call("window.opal.setMode(mode)", ["mode": mode.rawValue])
            }
        case "change":
            if let text = message["text"] as? String {
                self.text = text
            }
        case "openWikiLink":
            if let target = message["target"] as? String {
                onOpenWikiLink?(target)
            }
        case "openURL":
            if let string = message["url"] as? String, let url = URL(string: string) {
                onOpenURL?(url)
            }
        default:
            break
        }
    }
}

/// Breaks the retain cycle between WKUserContentController and the controller.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var controller: MarkdownEditorController?

    init(_ controller: MarkdownEditorController) {
        self.controller = controller
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated {
            controller?.handle(body)
        }
    }
}
