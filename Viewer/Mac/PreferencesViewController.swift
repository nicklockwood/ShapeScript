//
//  PreferencesViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 21/12/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Cocoa

final class PreferencesViewController: NSViewController {
    private let editorPopUp: NSPopUpButton = .init()

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 331))
        let label = NSTextField(labelWithString: "External Editor")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .right

        editorPopUp.translatesAutoresizingMaskIntoConstraints = false
        editorPopUp.target = self
        editorPopUp.action = #selector(didSelectEditor(_:))

        rootView.addSubview(label)
        rootView.addSubview(editorPopUp)
        NSLayoutConstraint.activate([
            editorPopUp.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 20),
            editorPopUp.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -20),
            editorPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),
            editorPopUp.firstBaselineAnchor.constraint(equalTo: label.firstBaselineAnchor),
            editorPopUp.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: rootView.leadingAnchor, constant: 20),
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureEditorPopup(editorPopUp)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        configureEditorPopup(editorPopUp)
    }

    // MARK: Editor

    @objc func didSelectEditor(_ sender: NSPopUpButton) {
        handleEditorPopupAction(for: sender, in: view.window)
    }
}
