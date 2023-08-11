//
//  WindowController.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 19/10/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import AppKit

class WindowController: NSWindowController {
    override func newWindowForTab(_ sender: Any?) {
        NSDocumentController.shared.openDocument(sender)
    }
}
