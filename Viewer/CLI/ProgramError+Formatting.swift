//
//  ProgramError+Formatting.swift
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
        if let hint {
            errorMessage += "\n\(hint)\n"
        }
        return errorMessage
    }
}
