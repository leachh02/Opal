//
//  InlineElementType.swift
//  Opal
//
//  Created by Harrison Leach on 1/8/2025.
//


import Foundation

// MARK: - Inline Element Types
enum InlineElementType: Equatable {
    case bold
    case italic
    case boldItalic
    case inlineCode
    case link(url: String)
    case plainText
}

// MARK: - Inline Element Model
struct InlineElement: Identifiable, Equatable {
    let id = UUID()
    let type: InlineElementType
    let content: String        // The actual text content (without markdown syntax)
    let rawText: String       // The original markdown text (with syntax)
    let range: NSRange        // Position in the original string
    
    var hasMarkdownSyntax: Bool {
        switch type {
        case .plainText:
            return false
        default:
            return true
        }
    }
    
    var syntaxLength: Int {
        return rawText.count - content.count
    }
}

// MARK: - Inline Markdown Parser
class InlineMarkdownParser {
    
    static func parseInlineElements(from text: String) -> [InlineElement] {
        var elements: [InlineElement] = []
        var currentIndex = 0
        
        while currentIndex < text.count {
            let remainingText = String(text.dropFirst(currentIndex))
            
            if let element = parseNextElement(from: remainingText, startIndex: currentIndex) {
                elements.append(element)
                currentIndex = element.range.upperBound
            } else {
                // No more markdown elements, treat rest as plain text
                let remainingRange = NSRange(location: currentIndex, length: text.count - currentIndex)
                let remainingContent = String(text.dropFirst(currentIndex))
                
                if !remainingContent.isEmpty {
                    elements.append(InlineElement(
                        type: .plainText,
                        content: remainingContent,
                        rawText: remainingContent,
                        range: remainingRange
                    ))
                }
                break
            }
        }
        
        return elements
    }
    
    private static func parseNextElement(from text: String, startIndex: Int) -> InlineElement? {
        // Try to parse different markdown elements in order of priority
        
        // 1. Try bold italic (***text***)
        if let element = parseBoldItalic(from: text, startIndex: startIndex) {
            return element
        }
        
        // 2. Try bold (**text**)
        if let element = parseBold(from: text, startIndex: startIndex) {
            return element
        }
        
        // 3. Try italic (*text*)
        if let element = parseItalic(from: text, startIndex: startIndex) {
            return element
        }
        
        // 4. Try inline code (`text`)
        if let element = parseInlineCode(from: text, startIndex: startIndex) {
            return element
        }
        
        // 5. Try link ([text](url))
        if let element = parseLink(from: text, startIndex: startIndex) {
            return element
        }
        
        // 6. Parse plain text until next markdown element
        return parsePlainText(from: text, startIndex: startIndex)
    }
    
    // MARK: - Individual Parsers
    
    private static func parseBoldItalic(from text: String, startIndex: Int) -> InlineElement? {
        return parseDelimitedText(
            from: text,
            startIndex: startIndex,
            delimiter: "***",
            type: .boldItalic
        )
    }
    
    private static func parseBold(from text: String, startIndex: Int) -> InlineElement? {
        return parseDelimitedText(
            from: text,
            startIndex: startIndex,
            delimiter: "**",
            type: .bold
        )
    }
    
    private static func parseItalic(from text: String, startIndex: Int) -> InlineElement? {
        return parseDelimitedText(
            from: text,
            startIndex: startIndex,
            delimiter: "*",
            type: .italic
        )
    }
    
    private static func parseInlineCode(from text: String, startIndex: Int) -> InlineElement? {
        return parseDelimitedText(
            from: text,
            startIndex: startIndex,
            delimiter: "`",
            type: .inlineCode
        )
    }
    
    private static func parseLink(from text: String, startIndex: Int) -> InlineElement? {
        // Pattern: [text](url)
        guard text.hasPrefix("[") else { return nil }
        
        // Find closing ]
        guard let closingBracket = text.firstIndex(of: "]") else { return nil }
        let linkText = String(text[text.index(after: text.startIndex)..<closingBracket])
        
        // Check for (url) after ]
        let afterBracket = text.index(after: closingBracket)
        guard afterBracket < text.endIndex,
              text[afterBracket] == "(" else { return nil }
        
        // Find closing )
        let searchStart = text.index(after: afterBracket)
        guard let closingParen = text[searchStart...].firstIndex(of: ")") else { return nil }
        
        let url = String(text[searchStart..<closingParen])
        let fullRange = text.startIndex..<text.index(after: closingParen)
        let rawText = String(text[fullRange])
        
        return InlineElement(
            type: .link(url: url),
            content: linkText,
            rawText: rawText,
            range: NSRange(location: startIndex, length: rawText.count)
        )
    }
    
    private static func parseDelimitedText(
        from text: String,
        startIndex: Int,
        delimiter: String,
        type: InlineElementType
    ) -> InlineElement? {
        guard text.hasPrefix(delimiter) else { return nil }
        
        let searchStart = text.index(text.startIndex, offsetBy: delimiter.count)
        guard let endRange = text[searchStart...].range(of: delimiter) else { return nil }
        
        let content = String(text[searchStart..<endRange.lowerBound])
        guard !content.isEmpty else { return nil } // Don't match empty delimiters
        
        let fullRange = text.startIndex..<endRange.upperBound
        let rawText = String(text[fullRange])
        
        return InlineElement(
            type: type,
            content: content,
            rawText: rawText,
            range: NSRange(location: startIndex, length: rawText.count)
        )
    }
    
    private static func parsePlainText(from text: String, startIndex: Int) -> InlineElement? {
        // Find the next markdown character
        let markdownChars: Set<Character> = ["*", "`", "["]
        
        var endIndex = 0
        for (index, char) in text.enumerated() {
            if markdownChars.contains(char) {
                endIndex = index
                break
            }
            endIndex = index + 1
        }
        
        guard endIndex > 0 else { return nil }
        
        let content = String(text.prefix(endIndex))
        return InlineElement(
            type: .plainText,
            content: content,
            rawText: content,
            range: NSRange(location: startIndex, length: content.count)
        )
    }
}
