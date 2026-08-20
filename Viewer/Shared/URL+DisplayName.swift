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
}
