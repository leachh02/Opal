//
//  FilePreviewView.swift
//  Opal
//
//  Shows a file that isn't a note, such as an image, PDF, audio or video,
//  with Quick Look, after downloading a copy to the device.
//

import QuickLook
import SwiftUI

struct FilePreviewView: View {
    let vault: Vault
    let path: String
    /// The file's modified time, if known, so an up-to-date copy needn't be checked with the server.
    var modified: Date?

    @State private var localURL: URL?
    @State private var error: String?

    private var name: String { VaultPath.name(of: path) }

    var body: some View {
        Group {
            if let localURL {
                if QLPreviewController.canPreview(localURL as NSURL) {
                    QuickLookView(url: localURL)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ContentUnavailableView(
                        "Can't Preview This File",
                        systemImage: FileKind(fileName: name).systemImage,
                        description: Text("Use Share to open it in another app.")
                    )
                }
            } else if let error {
                ContentUnavailableView {
                    Label("Couldn't open file", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Try Again") { Task { await load() } }
                }
            } else {
                ProgressView("Downloading…")
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let localURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: localURL)
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        error = nil
        do {
            localURL = try await FileCache(vault: vault).localURL(for: path, modified: modified)
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

/// Quick Look's viewer for one file, shown inside the navigation stack.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
