//
//  DocumentReloadRequest.swift
//  iOS Viewer
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Foundation

/// Carries a reload and its document across file-presenter and main-actor callbacks.
struct DocumentReloadRequest: Sendable {
    let document: Document
    let url: URL
    let completion: (@Sendable (Bool) -> Void)?
}
