//
//  main.swift
//  Viewer
//
//  Created by Nick Lockwood on 24/06/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Cocoa

let app = NSApplication.shared
MainActor.assumeIsolated {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    delegate.configureMainMenu()
}

app.run()
