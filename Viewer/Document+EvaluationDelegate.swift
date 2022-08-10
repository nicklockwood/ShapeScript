//
//  Document+EvaluationDelegate.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 10/08/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Foundation
import ShapeScript
import SceneKit

extension Document: EvaluationDelegate {
    func resolveURL(for path: String) -> URL {
        let url = URL(fileURLWithPath: path, relativeTo: fileURL)
        linkedResources.insert(url)
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

    func importGeometry(for url: URL) throws -> Geometry? {
        var isDirectory: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        var url = url
        if isDirectory.boolValue {
            let newURL = url.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: newURL.path) {
                url = newURL
            }
        }
        let scene = try SCNScene(url: url, options: [
            .flattenScene: false,
            .createNormalsIfAbsent: true,
            .convertToYUp: true,
        ])
        return try Geometry(scnNode: scene.rootNode)
    }

    func debugLog(_ values: [AnyHashable]) {
        var spaceNeeded = false
        let line = values.compactMap {
            switch $0 {
            case let string as String:
                spaceNeeded = false
                return string
            case let value:
                let string = String(logDescriptionFor: value as Any)
                defer { spaceNeeded = true }
                return spaceNeeded ? " \(string)" : string
            }
        }.joined()

        Swift.print(line)
        DispatchQueue.main.async {
            for viewController in self.sceneViewControllers {
                viewController.showConsole = true
                viewController.appendLog(line + "\n")
            }
        }
    }
}
