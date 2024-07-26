//
//  LicensesViewController.swift
//  ShapeScript App
//
//  Created by Nick Lockwood on 27/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Cocoa

class LicensesViewController: NSViewController {
    @IBOutlet private var textView: NSTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.textStorage?.setAttributedString(loadRTF("Licenses"))
    }
}
