//
//  URL+DisplayName.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 19/08/2026.
//

import Foundation

extension URL {
    var displayName: String {
        FileManager.default.displayName(atPath: path)
    }

    var displayBaseName: String {
        deletingPathExtension().displayName
    }

    var duplicateFileName: String {
        let baseName = deletingPathExtension().lastPathComponent
        let numberedName = if let separator = baseName.lastIndex(of: " "),
                              separator != baseName.startIndex,
                              case let suffix = baseName[baseName.index(after: separator)...],
                              !suffix.isEmpty,
                              suffix.allSatisfy({ $0 >= "0" && $0 <= "9" }),
                              let number = UInt64(suffix), number < UInt64.max
        {
            "\(baseName[..<separator]) \(number + 1)"
        } else {
            "\(baseName) 2"
        }
        return pathExtension.isEmpty ? numberedName : "\(numberedName).\(pathExtension)"
    }
}
