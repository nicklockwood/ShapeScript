//
//  DocumentViewControllerProtocol.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 27/06/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import SceneKit
import ShapeScript

@MainActor
protocol DocumentViewControllerProtocol: AnyObject, Sendable {
    associatedtype Document: DocumentProtocol

    static var documentBackgroundColor: Color { get }

    var document: Document? { get }
    var scnScene: SCNScene { get }
    var renderTimer: Timer? { get set }
    var scnView: SCNView { get }
    var errorTextView: OSTextView { get }
    var grantAccessButton: OSButton { get }
    var isQuickLook: Bool { get set }
    var cameraNode: SCNNode { get }
    var axesNode: SCNNode? { get set }
    var errorMessage: NSAttributedString? { get set }
    var isLoading: Bool { get set }
    var showConsole: Bool { get set }
    var showAxes: Bool { get set }
    var isOrthographic: Bool { get set }
    var camera: Camera { get set }
    var background: MaterialProperty? { get set }
    var geometry: Geometry? { get set }
    var selectedGeometry: Geometry? { get set }

    @discardableResult
    func presentError(_ error: Error, completionHandler: (() -> Void)?) -> Bool

    func clearLog()
    func appendLog(_ text: String)
    func updateModals()
    func copyCamera()
    func resetCamera()
    func refreshView()
}
