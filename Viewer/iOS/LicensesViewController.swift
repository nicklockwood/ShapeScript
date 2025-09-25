//
//  LicensesViewController.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 23/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import UIKit

final class LicensesViewController: WhatsNewViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Licenses"

        let attributedText = try! loadRTF("Licenses").mutableCopy() as! NSMutableAttributedString
        let range = attributedText.string.range(of: "Licenses\n\n")!
        attributedText.replaceCharacters(in: NSRange(range, in: attributedText.string), with: "")
        textView.attributedText = attributedText
    }
}
