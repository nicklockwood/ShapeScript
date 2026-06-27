//
//  DocumentProtocol.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 25/06/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

protocol DocumentProtocol: AnyObject, EvaluationDelegate, Sendable {
    static var documentBackgroundColor: Color { get }

    var cache: GeometryCache { get }
    var settings: Settings { get }
    var documentFileURL: URL? { get }
    var fileMonitor: FileMonitor? { get }
    var viewController: DocumentViewController? { get }

    var scene: Scene? { get set }
    var geometry: Geometry { get }
    var loadingProgress: LoadingProgress? { get set }
    var rerenderRequired: Bool { get set }
    var sourceString: String { get set }
    var errorMessage: NSAttributedString? { get set }
    var error: ProgramError? { get set }
    var cameras: [Camera] { get set }
}
