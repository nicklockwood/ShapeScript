//
//  WhatsNewViewController.swift
//  ShapeScript App
//
//  Created by Nick Lockwood on 27/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Cocoa

final class WhatsNewViewController: NSViewController {
    @IBOutlet private var whatsNewView: NSTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        whatsNewView.textStorage?.setAttributedString(loadRTF("WhatsNew"))
    }
}
