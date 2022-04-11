//
//  SVGPath+CGPath.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 11/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

#if canImport(CoreGraphics)

import CoreGraphics
import Foundation

extension CGPath {
    static func fromSVG(_ svgPath: String) throws -> CGPath {
        fromSVG(try SVGPath(svgPath))
    }

    static func fromSVG(_ svgPath: SVGPath) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        svgPath.commands.forEach(path.addCommand)
        return path
    }
}

extension CGPoint {
    init(_ svgPoint: SVGPoint) {
        self.init(x: svgPoint.x, y: svgPoint.y)
    }
}

extension SVGPoint {
    init(_ cgPoint: CGPoint) {
        self.init(x: Double(cgPoint.x), y: Double(cgPoint.y))
    }
}

private extension CGMutablePath {
    func addCommand(_ command: SVGCommand) {
        switch command {
        case let .moveTo(point):
            move(to: CGPoint(point))
        case let .lineTo(point):
            addLine(to: CGPoint(point))
        case let .quadratic(control, point):
            addQuadCurve(
                to: CGPoint(point),
                control: CGPoint(control)
            )
        case let .cubic(control1, control2, point):
            addCurve(
                to: CGPoint(point),
                control1: CGPoint(control1),
                control2: CGPoint(control2)
            )
        case let .arc(arc):
            arc.asBezierPath(from: SVGPoint(currentPoint)).forEach(addCommand)
        case .end:
            closeSubpath()
        }
    }
}

#endif
