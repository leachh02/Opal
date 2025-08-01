//
//  MarkdownBlockView.swift
//  Opal
//
//  Created by Harrison Leach on 1/8/2025.
//


import SwiftUI
import MarkdownUI

// MARK: - Block View Component
struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let isEditing: Bool
    let onStartEditing: () -> Void
    let onFinishEditing: () -> Void
    let onContentChanged: (String) -> Void
    
    @State private var editingText: String = ""
    @FocusState private var isFocused: Bool
    
    var body: some View {
        Group {
            if isEditing && block.isEditable {
                editingView
            } else {
                renderView
            }
        }
        .onAppear {
            editingText = block.content
        }
        .onChange(of: block.content) { newContent in
            if !isEditing {
                editingText = newContent
            }
        }
    }
    
    @ViewBuilder
    private var editingView: some View {
        TextEditor(text: $editingText)
            .focused($isFocused)
            .font(fontForBlockType)
            .frame(minHeight: minHeightForBlockType)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(4)
            .onAppear {
                isFocused = true
            }
            .onSubmit {
                commitEdit()
            }
            .onChange(of: isFocused) { focused in
                if !focused {
                    commitEdit()
                }
            }
    }
    
    @ViewBuilder
    private var renderView: some View {
        if block.type == .emptyLine {
            Text("")
                .frame(height: 8)
        } else {
            Markdown(block.content)
                .onTapGesture {
                    if block.isEditable {
                        onStartEditing()
                    }
                }
        }
    }
    
    private func commitEdit() {
        if editingText != block.content {
            onContentChanged(editingText)
        }
        onFinishEditing()
    }
    
    private var fontForBlockType: Font {
        switch block.type {
        case .codeBlock:
            return .system(.body, design: .monospaced)
        case .heading(let level):
            switch level {
            case 1: return .largeTitle
            case 2: return .title
            case 3: return .title2
            default: return .headline
            }
        default:
            return .body
        }
    }
    
    private var minHeightForBlockType: CGFloat {
        switch block.type {
        case .codeBlock:
            return 100
        case .heading:
            return 50
        default:
            return 44
        }
    }
}
