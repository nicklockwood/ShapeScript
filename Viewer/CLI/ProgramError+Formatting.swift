//
//  ProgramError.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 01/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import ShapeScript

extension ProgramError {
    /// Returns a nicely-formatted rich text error message.
    func message(with source: String) -> String {
        var errorMessage = "\(messageAndLocation(with: source))\n"
        if let line = annotatedErrorLine(with: source) {
            let indentedLines = line.split(separator: "\n").map { "  \($0)" }
            errorMessage += "\n\(indentedLines.joined(separator: "\n"))\n"
        }
        if let hint = hint {
            errorMessage += "\n\(hint)\n"
        }
        return errorMessage
    }
}

private func numberOfEmoji<S: StringProtocol>(in string: S) -> Int {
    string.reduce(0) { count, c in
        let scalars = c.unicodeScalars
        if scalars.count > 1 || (scalars.first?.value ?? 0) > 0x238C {
            return count + 1
        }
        return count
    }
}

private func emojiSpacing<S: StringProtocol>(for string: S) -> Int {
    Int(Double(numberOfEmoji(in: string)) * 1.25)
}
