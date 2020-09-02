//
//  WelcomeViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 02/11/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

class WelcomeViewController: NSViewController {
    @IBOutlet var shouldShowAtStartupCheckbox: NSButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        shouldShowAtStartupCheckbox.state = WelcomeViewController.shouldShowAtStartup ? .on : .off
    }

    @IBAction func openMacAppStore(_: Any) {
        NSWorkspace.shared.open(URL(string:
            "https://apps.apple.com/app/id1441135869")!)
    }

    @IBAction func toggleShowAtStartup(_ sender: NSButton) {
        WelcomeViewController.shouldShowAtStartup = (sender.state == .on)
    }

    public static var shouldShowAtStartup: Bool {
        get { return Settings.shared.showWelcomeScreenAtStartup }
        set { Settings.shared.showWelcomeScreenAtStartup = newValue }
    }
}
