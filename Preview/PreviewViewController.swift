//
//  PreviewViewController.swift
//  Preview
//
//  Created by Lockwood, Nick on 08/12/2025.
//

import Cocoa
import Quartz
import SceneKit

final class PreviewViewController: NSViewController, @preconcurrency QLPreviewingController {
    private var document: Document?
    private var documentViewController: DocumentViewController!

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func preparePreviewOfFile(
        at url: URL,
        completionHandler handler: @escaping (Error?) -> Void
    ) {
        do {
            let document = try Document(contentsOf: url, ofType: url.pathExtension.lowercased())
            self.document = document
            document.makeWindowControllers()
            documentViewController = document.viewController
            documentViewController.isQuickLook = true
            addChild(documentViewController)
            documentViewController.view.frame = view.bounds
            view.addSubview(documentViewController.view)
            documentViewController.view.autoresizingMask = [.width, .height]
            document.updateViews()
            handler(nil)
        } catch {
            handler(error)
        }
    }
}
