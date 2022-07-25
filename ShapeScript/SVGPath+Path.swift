//
//  SVGPath+Path.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 11/04/2022.
//  Copyright © 2022 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(SVGPath)
import SVGPath
#endif

extension Vector {
    init(_ svgPoint: SVGPoint) {
        self.init(svgPoint.x, svgPoint.y)
    }
}

extension SVGPoint {
    init(_ point: Vector) {
        self.init(x: point.x, y: point.y)
    }
}

extension Path {
    /// Creates a path from an SVGPath
    init(_ svgPath: SVGPath, detail: Int = 4, color: Color? = nil) {
        self.init(subpaths: svgPath.paths(detail: detail, color: color))
    }
}

extension SVGPath {
    /// Creates an array of paths from an SVGPath
    func paths(detail: Int = 4, color: Color? = nil) -> [Path] {
        var paths = [Path]()
        var points = [PathPoint]()
        var startingPoint = Vector.zero
        var firstCommand: SVGCommand?
        var lastCommand: SVGCommand?
        func endPath() {
            if points.count > 1 {
                if points.count > 2, points.first == points.last,
                   let firstCommand = firstCommand
                {
                    updateLastPoint(nextCommand: firstCommand)
                }
                paths.append(Path(points))
            }
            points.removeAll()
            firstCommand = nil
        }
        func updateLastPoint(nextCommand: SVGCommand) {
            if points.isEmpty {
                points.append(.point(startingPoint, color: color))
                return
            }
            guard let lastElement = lastCommand else {
                return
            }
            let p0, p1, p2: Vector, isCurved: Bool
            switch nextCommand {
            case .moveTo:
                points[points.count - 1].isCurved = false
                return
            case .end:
                if let firstElement = firstCommand {
                    updateLastPoint(nextCommand: firstElement)
                }
                return
            case let .lineTo(point):
                p2 = Vector(point)
                isCurved = false
            case let .quadratic(control, _), let .cubic(control, _, _):
                p2 = Vector(control)
                isCurved = true
            case .arc:
                preconditionFailure()
            }
            switch lastElement {
            case .moveTo, .end:
                return
            case let .lineTo(point):
                guard points.count > 1, isCurved else {
                    return
                }
                p0 = points[points.count - 2].position
                p1 = Vector(point)
            case let .quadratic(control, point), let .cubic(_, control, point):
                p0 = Vector(control)
                p1 = Vector(point)
            case .arc:
                preconditionFailure()
            }
            let d0 = (p1 - p0).normalized()
            let d1 = (p2 - p1).normalized()
            let isTangent = abs(d0.dot(d1)) > 0.99
            points[points.count - 1].isCurved = isTangent
        }
        func addCommand(_ command: SVGCommand) {
            switch command {
            case let .moveTo(point):
                endPath()
                startingPoint = Vector(point)
            case let .lineTo(point):
                updateLastPoint(nextCommand: command)
                points.append(.point(Vector(point), color: color))
            case let .quadratic(p1, p2):
                updateLastPoint(nextCommand: command)
                guard detail > 0 else {
                    points.append(.curve(Vector(p1), color: color))
                    points.append(.point(Vector(p2), color: color))
                    break
                }
                let detail = max(detail, 2)
                var t = 0.0
                let step = 1 / Double(detail)
                let p0 = points.last?.position ?? startingPoint
                for _ in 1 ..< detail {
                    t += step
                    points.append(.curve(
                        quadraticBezier(p0.x, p1.x, p2.x, t),
                        quadraticBezier(p0.y, p1.y, p2.y, t),
                        color: color
                    ))
                }
                points.append(.point(Vector(p2), color: color))
            case let .cubic(p1, p2, p3):
                updateLastPoint(nextCommand: command)
                guard detail > 0 else {
                    points.append(.curve(Vector(p1), color: color))
                    points.append(.curve(Vector(p2), color: color))
                    points.append(.point(Vector(p3), color: color))
                    break
                }
                let detail = max(detail * 2, 3)
                var t = 0.0
                let step = 1 / Double(detail)
                let p0 = points.last?.position ?? startingPoint
                for _ in 1 ..< detail {
                    t += step
                    points.append(.curve(
                        cubicBezier(p0.x, p1.x, p2.x, p3.x, t),
                        cubicBezier(p0.y, p1.y, p2.y, p3.y, t),
                        color: color
                    ))
                }
                points.append(.point(Vector(p3), color: color))
            case let .arc(arc):
                let p0 = points.last?.position ?? startingPoint
                arc.asBezierPath(from: SVGPoint(p0)).forEach(addCommand)
                return
            case .end:
                if points.last?.position != points.first?.position {
                    points.append(points[0])
                }
                startingPoint = points.first?.position ?? .zero
                endPath()
            }
            switch command {
            case .moveTo, .end:
                break
            default:
                firstCommand = command
            }
            lastCommand = command
        }
        commands.forEach(addCommand)
        endPath()
        return paths
    }
}

private func quadraticBezier(
    _ p0: Double, _ p1: Double,
    _ p2: Double, _ t: Double
) -> Double {
    let oneMinusT = 1 - t
    let c0 = oneMinusT * oneMinusT * p0
    let c1 = 2 * oneMinusT * t * p1
    let c2 = t * t * p2
    return c0 + c1 + c2
}

private func cubicBezier(
    _ p0: Double, _ p1: Double,
    _ p2: Double, _ p3: Double, _ t: Double
) -> Double {
    let oneMinusT = 1 - t
    let oneMinusTSquared = oneMinusT * oneMinusT
    let c0 = oneMinusTSquared * oneMinusT * p0
    let c1 = 3 * oneMinusTSquared * t * p1
    let c2 = 3 * oneMinusT * t * t * p2
    let c3 = t * t * t * p3
    return c0 + c1 + c2 + c3
}
