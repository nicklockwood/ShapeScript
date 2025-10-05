//
//  WelcomeViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 02/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

final class WelcomeViewController: NSViewController {
    @IBOutlet private var welcomeView: NSTextView!
    @IBOutlet private var shouldShowAtStartupCheckbox: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        welcomeView.textStorage?.setAttributedString(loadRTF("Welcome"))
        shouldShowAtStartupCheckbox.state =
            Settings.shared.showWelcomeScreenAtStartup ? .on : .off
    }

    @IBAction func openGettingStartedGuide(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL.appendingPathComponent("getting-started"))
    }

    @IBAction func toggleShowAtStartup(_ sender: NSButton) {
        Settings.shared.showWelcomeScreenAtStartup = (sender.state == .on)
    }
}
