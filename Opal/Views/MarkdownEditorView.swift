//
//  MarkdownEditorView.swift
//  Opal
//
//  Created by Harrison Leach on 28/7/2025.
//


import SwiftUI

struct MarkdownEditorView: View {
    @Binding var content: String
    var onSave: () -> Void

    var body: some View {
        VStack {
            TextEditor(text: $content)
                .padding()
                .font(.system(.body, design: .monospaced))
            Button("Save Changes", action: onSave)
                .padding()
                .buttonStyle(.borderedProminent)
        }
    }
}