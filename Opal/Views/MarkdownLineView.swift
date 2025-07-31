//
//  MarkdownLineView.swift
//  Opal
//
//  Created by Harrison Leach on 29/7/2025.
//


import SwiftUI

struct MarkdownLineView: View {
    let line: String

    var body: some View {
        if line.starts(with: "# ") {
            Text(line.dropFirst(2))
                .font(.title)
                .bold()
        } else if line.starts(with: "## ") {
            Text(line.dropFirst(3))
                .font(.title2)
        } else if line.starts(with: "- ") {
            Text("• \(line.dropFirst(2))")
                .font(.body)
        } else {
            Text(line)
                .font(.body)
        }
    }
}