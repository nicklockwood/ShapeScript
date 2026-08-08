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
    associatedtype ViewController: DocumentViewControllerProtocol

    static var backgroundColor: OSColor { get }

    var cache: GeometryCache { get }
    var settings: Settings { get }
    var documentFileURL: URL? { get }
    var fileMonitor: FileMonitor? { get }
    var viewController: ViewController? { get }

    var scene: Scene? { get set }
    var loadingProgress: LoadingProgress? { get set }
    var rerenderRequired: Bool { get set }
    var sourceString: String { get set }
    var error: ProgramError? { get set }
    var cameras: [Camera] { get set }
}
