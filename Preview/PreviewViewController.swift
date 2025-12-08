//
//  PreviewViewController.swift
//  Preview
//
//  Created by Lockwood, Nick on 08/12/2025.
//

import Cocoa
import Quartz
import SceneKit

final class PreviewViewController: NSViewController, QLPreviewingController {
    private var documentViewController: DocumentViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping @Sendable (Error?) -> Void
    ) {
        do {
            let document = try Document(contentsOf: url, ofType: "shape")
            document.makeWindowControllers()
            documentViewController = document.viewController
            addChild(documentViewController)
            documentViewController.view.frame = view.bounds
            view.addSubview(documentViewController.view)
            documentViewController.view.autoresizingMask = [.width, .height]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                document.updateViews()
                handler(nil)
            }
        } catch {
            handler(error)
        }
    }
}
