//
//  WhatsNewViewController.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 23/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import UIKit

// swiftformat:disable:next preferFinalClasses
@MainActor class WhatsNewViewController: UIViewController {
    let textView: UITextView = .init()

    override func loadView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.font = .systemFont(ofSize: 14)
        textView.isEditable = false
        textView.contentInsetAdjustmentBehavior = .always

        view = UIView()
        view.backgroundColor = .systemBackground
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "What's New in ShapeScript?"
        textView.attributedText = try! loadRTF("WhatsNew")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in
                self?.dismiss(animated: true)
            }
        )
    }
}
