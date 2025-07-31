//
//  MarkdownEditorView.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//


import SwiftUI
import MarkdownUI
import SMBClient

struct MarkdownEditorView: View {
    let path: String
    let treeAccessor: TreeAccessor

    @State private var lines: [String] = []
    @State private var editingLineIndex: Int? = nil
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(lines.indices, id: \.self) { index in
                    if editingLineIndex == index {
                        TextEditor(text: $lines[index])
                            .focused($isEditing)
                            .frame(minHeight: 44)
                            .onSubmit {
                                editingLineIndex = nil
                            }
                    } else {
                        Markdown(lines[index])
                            .onTapGesture {
                                editingLineIndex = index
                            }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(path.components(separatedBy: "/").last ?? "Note")
        .toolbar {
            Button("Save") {
                saveToFile()
            }
        }
        .task {
            await loadFile()
        }
    }

    private func loadFile() async {
        do {
            let data = try await treeAccessor.download(path: path)
            if let text = String(data: data, encoding: .utf8) {
                lines = text.components(separatedBy: .newlines)
            }
        } catch {
            print("❌ Failed to load file: \(error.localizedDescription)")
        }
    }

    private func saveToFile() {
        Task {
            do {
                let text = lines.joined(separator: "\n")
                let data = Data(text.utf8)
                try await treeAccessor.upload(content: data, path: path)
                print("✅ File saved")
            } catch {
                print("❌ Failed to save file: \(error.localizedDescription)")
            }
        }
    }
}
