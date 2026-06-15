//
//  SVGPath+CoreGraphics.swift
//  SVGPath
//
//  Created by Nick Lockwood on 08/01/2022.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//
//  Distributed under the permissive MIT license
//  Get the latest version from here:
//
//  https://github.com/nicklockwood/SVGPath
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to
//  deal in the Software without restriction, including without limitation the
//  rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#if canImport(CoreGraphics)

import CoreGraphics

// MARK: SVGPath to CGPath

public extension CGPath {
    /// Create a `CGPath` from an SVG path string.
    /// - Parameters:
    ///   - svgPath: The SVG path string.
    ///   - rect: An optional rectangle that the path should be scaled to fit inside.
    static func from(svgPath: String, in rect: CGRect? = nil) throws -> CGPath {
        try from(SVGPath(string: svgPath), in: rect)
    }

    /// Create a `CGPath` from an `SVGPath` instance.
    /// - Parameters:
    ///   - svgPath: The `SVGPath` instance to convert to a `CGPath`.
    ///   - rect: An optional rectangle that the path should be scaled to fit inside.
    static func from(_ svgPath: SVGPath, in rect: CGRect? = nil) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        svgPath.commands.forEach(path.addCommand)
        guard let rect else {
            return path
        }
        let bounds = path.boundingBoxOfPath
        let target = bounds.scaledToFit(in: rect)
        var transform = CGAffineTransform.identity
            .translatedBy(x: target.minX - bounds.minX, y: target.minY - bounds.minY)
            .scaledBy(x: target.width / bounds.width, y: target.height / bounds.height)
        return path.copy(using: &transform) ?? path
    }

    /// Deprecated.
    @available(*, deprecated, renamed: "from(_:)")
    static func from(svgPath: SVGPath) -> CGPath {
        from(svgPath)
    }
}

public extension CGPoint {
    /// Create a `CGPoint` from an `SVGPoint`.
    /// - Parameter svgPoint: The `SVGPoint` to convert.
    init(_ svgPoint: SVGPoint) {
        self.init(x: svgPoint.x, y: svgPoint.y)
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

private extension CGRect {
    func scaledToFit(in rect: CGRect) -> CGRect {
        var scale = rect.width / width
        if height * scale > rect.height {
            scale = rect.height / height
        }
        let width = width * scale
        let height = height * scale
        return .init(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

// MARK: CGPath to SVGPath

public extension SVGPath {
    /// Create an `SVGPath` from a `CGPath`.
    /// - Parameter cgPath: The `CGPath` to convert.
    init(_ cgPath: CGPath) {
        var commands = [SVGCommand]()
        cgPath.applyWithBlock {
            let points = $0.pointee.points
            let command: SVGCommand
            switch $0.pointee.type {
            case .moveToPoint:
                command = .moveTo(SVGPoint(points[0]))
            case .closeSubpath:
                command = .end
            case .addLineToPoint:
                command = .lineTo(SVGPoint(points[0]))
            case .addQuadCurveToPoint:
                let p1 = points[0], p2 = points[1]
                command = .quadratic(SVGPoint(p1), SVGPoint(p2))
            case .addCurveToPoint:
                let p1 = points[0], p2 = points[1], p3 = points[2]
                command = .cubic(SVGPoint(p1), SVGPoint(p2), SVGPoint(p3))
            @unknown default:
                return
            }
            commands.append(command)
        }
        self.init(commands: commands)
    }

    @available(*, deprecated, renamed: "init(_:)")
    init(cgPath: CGPath) {
        self.init(cgPath)
    }
}

public extension SVGPoint {
    /// Create an `SVGPoint` from a `CGPoint`.
    /// - Parameter cgPoint: The `CGPoint` to convert.
    init(_ cgPoint: CGPoint) {
        self.init(x: Double(cgPoint.x), y: Double(cgPoint.y))
    }
}

#endif
