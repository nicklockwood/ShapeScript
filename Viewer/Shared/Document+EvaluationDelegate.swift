//
//  Document+EvaluationDelegate.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 10/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import SceneKit
import ShapeScript

extension Document: EvaluationDelegate {
    func resolveURL(for path: String) -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: fileURL)
        linkedResources.insert(url)
//        clearBookmarks() // Handy for debugging bookmarks
        if let resolvedURL = resolveBookMark(for: url) {
            if resolvedURL.path != url.path {
                // File was moved, so return the original url (which will throw a file-not-found error)
                // TODO: we could handle this more gracefully by reporting that the file was moved
                return url
            }
            return resolvedURL
        } else {
            bookmarkURL(url)
        }
        return url
    }

    func debugLog(_ values: [AnyHashable]) {
        let line: String
        if values.count == 1 {
            line = String(logDescriptionFor: values[0] as Any)
        } else {
            var spaceNeeded = false
            line = values.compactMap {
                switch $0 {
                case let string as String:
                    spaceNeeded = false
                    return string
                case let value:
                    let string = String(nestedLogDescriptionFor: value as Any)
                    defer { spaceNeeded = true }
                    return spaceNeeded ? " \(string)" : string
                }
            }.joined()
        }

        Swift.print(line)
        DispatchQueue.main.async { [weak self] in
            if let viewController = self?.viewController {
                viewController.showConsole = true
                viewController.appendLog(line + "\n")
            }
        }
    }
}
