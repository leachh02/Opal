//
//  MarkdownBlock.swift
//  Opal
//
//  Created by Harrison Leach on 1/8/2025.
//


import SwiftUI
import Markdown

// MARK: - Data Models
struct MarkdownBlock: Identifiable, Equatable {
    let id = UUID()
    let type: BlockType
    let content: String
    let sourceRange: NSRange
    let originalRange: Range<String.Index>
    
    enum BlockType: Equatable {
        case paragraph
        case heading(level: Int)
        case codeBlock(language: String?)
        case blockquote
        case list(ordered: Bool)
        case listItem(level: Int)
        case thematicBreak
        case emptyLine
    }
    
    var isEditable: Bool {
        switch type {
        case .emptyLine:
            return false
        default:
            return true
        }
    }
}

// MARK: - Markdown Parser
class MarkdownDocumentParser {
    static func parseBlocks(from text: String) -> [MarkdownBlock] {
        guard !text.isEmpty else { return [] }
        
        let document = Document(parsing: text)
        var blocks: [MarkdownBlock] = []
        var currentIndex = text.startIndex
        
        // Parse markdown blocks
        for child in document.children {
            // Handle any content before this block (like empty lines)
            if let range = child.range {
                // Convert SourceLocation to String.Index
                let blockStart = sourceLocationToIndex(range.lowerBound, in: text)
                let blockEnd = sourceLocationToIndex(range.upperBound, in: text)
                
                if currentIndex < blockStart {
                    let gap = String(text[currentIndex..<blockStart])
                    blocks.append(contentsOf: parseGapContent(gap, startIndex: currentIndex, in: text))
                }
                
                // Parse the actual block
                let blockRange = blockStart..<blockEnd
                let blockContent = String(text[blockRange])
                let block = createBlock(from: child, content: blockContent, range: blockRange, in: text)
                blocks.append(block)
                
                currentIndex = blockRange.upperBound
            }
        }
        
        // Handle any remaining content
        if currentIndex < text.endIndex {
            let remaining = String(text[currentIndex...])
            blocks.append(contentsOf: parseGapContent(remaining, startIndex: currentIndex, in: text))
        }
        
        return blocks
    }
    
    private static func sourceLocationToIndex(_ location: SourceLocation, in text: String) -> String.Index {
        let lines = text.components(separatedBy: .newlines)
        var currentIndex = text.startIndex
        
        // Navigate to the correct line (1-based)
        for lineNumber in 1..<location.line {
            if lineNumber <= lines.count {
                currentIndex = text.index(currentIndex, offsetBy: lines[lineNumber - 1].count + 1) // +1 for newline
            }
        }
        
        // Navigate to the correct column (1-based)
        let targetColumn = max(1, location.column) - 1 // Convert to 0-based
        let remainingDistance = min(targetColumn, text.distance(from: currentIndex, to: text.endIndex))
        
        return text.index(currentIndex, offsetBy: remainingDistance)
    }
    
    private static func createBlock(from markup: Markup, content: String, range: Range<String.Index>, in text: String) -> MarkdownBlock {
        let nsRange = NSRange(range, in: text)
        
        switch markup {
        case is Paragraph:
            return MarkdownBlock(type: .paragraph, content: content, sourceRange: nsRange, originalRange: range)
        case let heading as Heading:
            return MarkdownBlock(type: .heading(level: heading.level), content: content, sourceRange: nsRange, originalRange: range)
        case let codeBlock as CodeBlock:
            return MarkdownBlock(type: .codeBlock(language: codeBlock.language), content: content, sourceRange: nsRange, originalRange: range)
        case is BlockQuote:
            return MarkdownBlock(type: .blockquote, content: content, sourceRange: nsRange, originalRange: range)
        case is OrderedList:
            return MarkdownBlock(type: .list(ordered: true), content: content, sourceRange: nsRange, originalRange: range)
        case is UnorderedList:
            return MarkdownBlock(type: .list(ordered: false), content: content, sourceRange: nsRange, originalRange: range)
        case is ThematicBreak:
            return MarkdownBlock(type: .thematicBreak, content: content, sourceRange: nsRange, originalRange: range)
        default:
            return MarkdownBlock(type: .paragraph, content: content, sourceRange: nsRange, originalRange: range)
        }
    }
    
    private static func parseGapContent(_ gap: String, startIndex: String.Index, in text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = gap.components(separatedBy: .newlines)
        var currentOffset = 0
        
        for line in lines {
            guard currentOffset < gap.count else { break }
            
            let lineStart = text.index(startIndex, offsetBy: currentOffset)
            let lineEnd = text.index(lineStart, offsetBy: min(line.count, gap.count - currentOffset))
            let range = lineStart..<lineEnd
            let nsRange = NSRange(range, in: text)
            
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                blocks.append(MarkdownBlock(type: .emptyLine, content: line, sourceRange: nsRange, originalRange: range))
            } else {
                blocks.append(MarkdownBlock(type: .paragraph, content: line, sourceRange: nsRange, originalRange: range))
            }
            
            currentOffset += line.count + 1 // +1 for newline
        }
        
        return blocks
    }
}

// MARK: - Document Model
class MarkdownDocumentModel: ObservableObject {
    @Published var originalText: String = ""
    @Published var blocks: [MarkdownBlock] = []
    @Published var editingBlockID: UUID?
    
    func updateText(_ newText: String) {
        originalText = newText
        reparse()
    }
    
    private func reparse() {
        blocks = MarkdownDocumentParser.parseBlocks(from: originalText)
    }
    
    func startEditing(blockID: UUID) {
        editingBlockID = blockID
    }
    
    func updateBlock(_ blockID: UUID, with newContent: String) {
        guard let blockIndex = blocks.firstIndex(where: { $0.id == blockID }) else { return }
        let block = blocks[blockIndex]
        
        // Replace the block's content in the original text
        let range = block.originalRange
        originalText = originalText.replacingCharacters(in: range, with: newContent)
        reparse()
    }
    
    func finishEditing() {
        editingBlockID = nil
    }
}
