//
//  PreferencesViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

class PreferencesViewController: NSViewController {
    @IBOutlet var editorPopUp: NSPopUpButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        configureEditorPopup(editorPopUp)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        configureEditorPopup(editorPopUp)
    }

    // MARK: Editor

    @IBAction func didSelectEditor(_ sender: NSPopUpButton) {
        handleEditorPopupAction(for: sender, in: view.window)
    }
}
