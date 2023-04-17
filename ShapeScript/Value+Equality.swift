//
//  Value+Equality.swift
//  ShapeScript Lib
//
//  Created by Nick Lockwood on 17/04/2023.
//  Copyright © 2023 Nick Lockwood. All rights reserved.
//

import Euclid

extension Value {
    static let epsilon: Double = 1e-8

    func isAlmostEqual(to other: Value) -> Bool {
        switch (self, other) {
        case let (.number(lhs), .number(rhs)),
             let (.radians(lhs), .radians(rhs)),
             let (.halfturns(lhs), .halfturns(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.vector(lhs), .vector(rhs)),
             let (.size(lhs), .size(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.color(lhs), .color(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.rotation(lhs), .rotation(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.point(lhs), .point(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.range(lhs), .range(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case let (.tuple(lhs), .tuple(rhs)):
            return zip(lhs, rhs).allSatisfy { $0.isAlmostEqual(to: $1) }
        case let (.object(lhs), .object(rhs)):
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                rhs[key]?.isAlmostEqual(to: value) == true
            }
        case (.number, _),
             (.radians, _),
             (.halfturns, _),
             (.vector, _),
             (.size, _),
             (.color, _),
             (.rotation, _),
             (.texture, _),
             (.material, _), // TODO: fuzzy opacity/color property comparisons?
             (.boolean, _),
             (.string, _),
             (.text, _),
             (.path, _),
             (.mesh, _),
             (.polygon, _),
             (.point, _),
             (.range, _),
             (.bounds, _),
             (.tuple, _),
             (.object, _):
            return value == other.value
        }
    }
}

private extension Double {
    func isAlmostEqual(to other: Double) -> Bool {
        abs(self - other) < Value.epsilon
    }
}

private extension Color {
    func isAlmostEqual(to other: Color) -> Bool {
        zip(components, other.components).allSatisfy {
            $0.isAlmostEqual(to: $1)
        }
    }
}

private extension MaterialProperty {
    func isAlmostEqual(to other: MaterialProperty) -> Bool {
        switch (self, other) {
        case let (.color(lhs), .color(rhs)):
            return lhs.isAlmostEqual(to: rhs)
        case (.texture, _), (.color, _):
            return self == other
        }
    }
}

private extension Vector {
    func isAlmostEqual(to other: Vector) -> Bool {
        x.isAlmostEqual(to: other.x)
            && y.isAlmostEqual(to: other.y)
            && z.isAlmostEqual(to: other.z)
    }
}

private extension Rotation {
    func isAlmostEqual(to other: Rotation) -> Bool {
        angle.radians.isAlmostEqual(to: other.angle.radians)
            && axis.isAlmostEqual(to: other.axis)
    }
}

private extension PathPoint {
    func isAlmostEqual(to other: PathPoint) -> Bool {
        isCurved == other.isCurved
            && position.isAlmostEqual(to: other.position)
            && (color == nil) == (other.color == nil)
            && color.map { $0.isAlmostEqual(to: other.color!) } ?? false
    }
}

private extension Path {
    func isAlmostEqual(to other: Path) -> Bool {
        points.count == other.points.count
            && zip(points, other.points).allSatisfy { $0.isAlmostEqual(to: $1) }
    }
}

private extension RangeValue {
    func isAlmostEqual(to other: RangeValue) -> Bool {
        start.isAlmostEqual(to: other.start)
            && end.isAlmostEqual(to: other.end)
            && step.isAlmostEqual(to: other.step)
    }
}
