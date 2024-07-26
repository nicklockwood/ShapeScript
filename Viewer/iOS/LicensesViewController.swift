//
//  LicensesViewController.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 23/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import UIKit

class LicensesViewController: WhatsNewViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Licenses"
        textView.attributedText = try! loadRTF("Licenses")
    }
}
