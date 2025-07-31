//
//  MarkdownEditorViewModel.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import Foundation
import Combine

class MarkdownEditorViewModel: ObservableObject {
    @Published var rawText: String
    @Published var editingLineIndex: Int? = nil
    
    init(initialText: String) {
        self.rawText = initialText
    }
    
    var lines: [String] {
        rawText.components(separatedBy: .newlines)
    }
    
    func update(lineAt index: Int, with text: String) {
        var updated = lines
        updated[index] = text
        rawText = updated.joined(separator: "\n")
    }
}