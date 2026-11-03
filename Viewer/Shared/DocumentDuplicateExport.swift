//
//  DocumentDuplicateExport.swift
//  ShapeScript Viewer
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

/// Owns a fresh temporary file for one document-picker export.
final class DocumentDuplicateExport {
    let fileURL: URL
    private let directory: URL

    init(fileURL sourceURL: URL, contents: Data?) throws {
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        self.fileURL = directory.appendingPathComponent(sourceURL.duplicateFileName)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let contents {
                try contents.write(to: fileURL, options: .atomic)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}
