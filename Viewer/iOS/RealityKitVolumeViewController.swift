//
//  RealityKitVolumeViewController.swift
//  Viewer (iOS)
//
//  Created by Nick Lockwood on 06/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

#if os(visionOS)

import SwiftUI
import UIKit

let volumeActivityType = "com.charcoaldesign.ShapeScriptViewer.volume"
let volumeSceneConfigurationName = "Volume Configuration"
let volumeWindowGroupID = "com.charcoaldesign.ShapeScriptViewer.volume.window"
private let volumeLayoutWidth: CGFloat = 1280
let volumeLayoutHeight: CGFloat = 1280
private let volumeLayoutDepth = volumeLayoutWidth * CGFloat(volumeDefaultDepth / volumeDefaultWidth)
let volumeOrnamentScale: CGFloat = 0.5
private let volumeMinimumDimension = 0.05
private let flatVolumeLayoutDepth: CGFloat = 0

extension VolumeSize {
    func layoutWidth(usesRealityKitRenderer: Bool) -> CGFloat {
        guard usesRealityKitRenderer else {
            return volumeLayoutWidth
        }
        let scale = max(volumeMinimumDimension, width) / volumeDefaultWidth
        return volumeLayoutWidth * CGFloat(scale)
    }

    func layoutHeight(usesRealityKitRenderer: Bool) -> CGFloat {
        guard usesRealityKitRenderer else {
            return volumeLayoutHeight
        }
        let scale = max(volumeMinimumDimension, height) / volumeDefaultHeight
        return volumeLayoutHeight * CGFloat(scale)
    }

    func layoutDepth(usesRealityKitRenderer: Bool) -> CGFloat {
        guard usesRealityKitRenderer else { return flatVolumeLayoutDepth }
        let scale = max(volumeMinimumDimension, depth) / volumeDefaultDepth
        return volumeLayoutDepth * CGFloat(scale)
    }
}

struct VolumeDocumentReference: Codable, Hashable {
    let urlString: String

    init(fileURL: URL) {
        self.urlString = fileURL.absoluteString
    }

    var fileURL: URL? {
        URL(string: urlString)
    }
}

private struct VolumeDocumentHost: UIViewControllerRepresentable {
    let viewController: DocumentViewController

    func makeUIViewController(context _: Context) -> DocumentViewController {
        viewController
    }

    func updateUIViewController(
        _: DocumentViewController,
        context _: Context
    ) {}
}

private struct VolumeDocumentContent: View {
    let viewController: DocumentViewController
    let volumeSize: VolumeSize
    let usesRealityKitRenderer: Bool

    var body: some View {
        ZStack {
            if usesRealityKitRenderer {
                viewController.realityKitView
            }
            VolumeDocumentHost(viewController: viewController)
        }
        .frame(width: contentWidth, height: contentHeight)
        .frame(depth: contentDepth, alignment: .center)
    }

    private var contentWidth: CGFloat {
        volumeSize.layoutWidth(usesRealityKitRenderer: usesRealityKitRenderer)
    }

    private var contentHeight: CGFloat {
        volumeSize.layoutHeight(usesRealityKitRenderer: usesRealityKitRenderer)
    }

    private var contentDepth: CGFloat {
        volumeSize.layoutDepth(usesRealityKitRenderer: usesRealityKitRenderer)
    }
}

private struct VolumeDocumentSceneRoot: View {
    let reference: VolumeDocumentReference
    @State private var viewController: DocumentViewController?
    @State private var volumeSize = VolumeSize.volume
    @State private var showsWindowBackground = false
    @State private var usesRealityKitRenderer = true
    @State private var didOpenDocument = false
    @State private var errorMessage: String?

    nonisolated init(reference: VolumeDocumentReference) {
        self.reference = reference
    }

    var body: some View {
        Group {
            if let errorMessage {
                Text(errorMessage)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(width: 600, height: 600)
            } else if let viewController {
                VolumeDocumentContent(
                    viewController: viewController,
                    volumeSize: volumeSize,
                    usesRealityKitRenderer: usesRealityKitRenderer
                )
            } else {
                SwiftUI.ProgressView()
                    .frame(width: 600, height: 600)
            }
        }
        .glassBackgroundEffect(displayMode: showsWindowBackground ? .always : .never)
        .task(id: reference) {
            await openDocumentIfNeeded()
        }
    }

    @MainActor
    private func openDocumentIfNeeded() async {
        guard !didOpenDocument else {
            return
        }
        didOpenDocument = true

        let viewController = DocumentViewController(rendererKind: .realityKit)
        self.viewController = viewController
        viewController.setVolumeSizeHandler { size in
            if usesRealityKitRenderer {
                volumeSize = size
            }
        }
        viewController.onRendererKindChanged = { viewController in
            showsWindowBackground = viewController.showsWindowBackground
            usesRealityKitRenderer = viewController.usesRealityKitRenderer
            if viewController.usesRealityKitRenderer {
                viewController.refreshAxesAndCamera()
            } else {
                volumeSize = .flat
            }
        }

        guard let fileURL = reference.fileURL else {
            errorMessage = "Unable to open file."
            return
        }

        let document = Document(fileURL: fileURL)
        viewController.document = document
        viewController.loadViewIfNeeded()

        let success: Bool = if document.documentState == .closed {
            await withCheckedContinuation { continuation in
                document.open { success in
                    DispatchQueue.main.async {
                        continuation.resume(returning: success)
                    }
                }
            }
        } else {
            true
        }

        guard success else {
            errorMessage = "Unable to open file."
            return
        }
        viewController.updateSceneTitle()
    }
}

@available(visionOS 26.0, *)
@objc(VisionDocumentSceneDelegate)
final class VisionDocumentSceneDelegate: NSObject, UIHostingSceneDelegate {
    nonisolated static var rootScene: some SwiftUI.Scene {
        WindowGroup(
            id: volumeWindowGroupID,
            for: VolumeDocumentReference.self
        ) { reference in
            if let reference = reference.wrappedValue {
                VolumeDocumentSceneRoot(reference: reference)
            } else {
                Text("No document selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(width: 600, height: 600)
                    .glassBackgroundEffect()
            }
        }
        .windowStyle(.volumetric)
        .windowResizability(.contentSize)
        .defaultSize(
            width: volumeDefaultWidth,
            height: volumeDefaultHeight,
            depth: volumeDefaultDepth,
            in: .meters
        )
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        UIApplication.shared.closeAuxiliaryScenesIfNoMainScenesRemain(excluding: scene)
    }
}

extension UIScene {
    var isVolumeScene: Bool {
        session.role == .windowApplicationVolumetric
    }
}

extension Notification.Name {
    static let documentSceneUpdated = Self("documentSceneUpdated")
}

#endif
