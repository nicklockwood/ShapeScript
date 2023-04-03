//
//  WhatsNewViewController.swift
//  ShapeScript App
//
//  Created by Nick Lockwood on 27/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Cocoa

class WhatsNewViewController: NSViewController {
    @IBOutlet private var whatsNewView: NSTextView!

    override func viewDidLoad() {
        super.viewDidLoad()
        let file = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md")!
        whatsNewView.string = try! String(contentsOf: file)
    }
}
