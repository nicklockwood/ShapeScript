//
//  WhatsNewViewController.swift
//  Viewer
//
//  Created by Nick Lockwood on 27/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Cocoa

@MainActor
final class WhatsNewViewController: NSViewController {
    private let textView: NSTextView = makeRTFTextView()

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 480))
        let scrollView = makeScrollView(for: textView)
        rootView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: rootView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.textStorage?.setAttributedString(loadRTF("WhatsNew"))
    }
}
