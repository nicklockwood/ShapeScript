//
//  WelcomeViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 02/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

class WelcomeViewController: NSViewController {
    @IBOutlet private var welcomeView: NSTextView!
    @IBOutlet private var shouldShowAtStartupCheckbox: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        welcomeView.textStorage?.setAttributedString(loadRTF("Welcome"))
        shouldShowAtStartupCheckbox.state =
            WelcomeViewController.shouldShowAtStartup ? .on : .off
    }

    @IBAction func openGettingStartedGuide(_: Any) {
        NSWorkspace.shared.open(onlineHelpURL.appendingPathComponent("getting-started"))
    }

    @IBAction func toggleShowAtStartup(_ sender: NSButton) {
        WelcomeViewController.shouldShowAtStartup = (sender.state == .on)
    }

    public static var shouldShowAtStartup: Bool {
        get { Settings.shared.showWelcomeScreenAtStartup }
        set { Settings.shared.showWelcomeScreenAtStartup = newValue }
    }
}
