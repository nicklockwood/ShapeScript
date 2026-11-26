//
//  Euclid+OpenSCAD.swift
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

func openSCADCircularSegments(
    radius: Double,
    fragments: Double,
    fragmentAngle: Double,
    fragmentSize: Double,
    sweep: Double = 360,
    roundingExplicitCount: FloatingPointRoundingRule = .up
) -> Int? {
    let fullTurn = fragments > 0 ? max(3, fragments.rounded(roundingExplicitCount)) :
        ceil(max(5, min(360 / max(0.01, fragmentAngle), abs(radius) * 2 * .pi / max(0.01, fragmentSize))))
    return Int(exactly: max(1, ceil(fullTurn * abs(sweep) / 360)))
}

func openSCADRevolution(
    angle: Double,
    start: Double,
    bounds: Bounds,
    fragments: Double,
    fragmentAngle: Double,
    fragmentSize: Double
) -> (sweep: Double, slices: Int, rotation: Rotation)? {
    let sweep = abs(angle) >= 360 ? 360 : angle
    guard let slices = openSCADCircularSegments(
        radius: max(abs(bounds.min.x), abs(bounds.max.x)),
        fragments: fragments, fragmentAngle: fragmentAngle, fragmentSize: fragmentSize,
        sweep: sweep
    ) else { return nil }
    let startAngle = start.truncatingRemainder(dividingBy: 360)
    // Euclid revolves around Y and begins on -X. OpenSCAD starts on the profile's original side.
    let offset = (bounds.max.x <= 0 ? 0 : 180) - startAngle
    let rotation = Rotation.roll(.degrees(offset)) * Rotation(from: .unitY, to: .unitZ)
    return (sweep, slices, rotation)
}

extension Mesh {
    static func openSCADSphere(
        radius: Double,
        segments n: Int,
        octahedral: Bool,
        isCancelled: CancellationHandler
    ) -> Mesh {
        guard radius > 0, n >= 3, !isCancelled() else { return .empty }
        if octahedral {
            return openSCADOctahedralSphere(radius: radius, divisions: (n + 3) / 4, isCancelled: isCancelled)
        }
        let rings = (n + 1) / 2
        var points: [[Vector]] = []
        for i in 0 ..< rings {
            if isCancelled() { return .empty }
            let latitude = Double.pi * (Double(i) + 0.5) / Double(rings)
            points.append((0 ..< n).map { j in
                let longitude = 2 * Double.pi * Double(j) / Double(n)
                return Vector(
                    radius * sin(latitude) * cos(longitude),
                    radius * sin(latitude) * sin(longitude),
                    radius * cos(latitude)
                )
            })
        }
        var polygons: [Polygon] = []
        func append(_ positions: [Vector]) {
            if let polygon = Polygon(positions.map { Vertex($0) }) {
                polygons.append(polygon)
            }
        }
        append(points[0])
        for i in 1 ..< rings {
            if isCancelled() { return .empty }
            for j in 0 ..< n {
                let next = (j + 1) % n
                append([points[i][j], points[i][next], points[i - 1][j]])
                append([points[i][next], points[i - 1][next], points[i - 1][j]])
            }
        }
        append(points[rings - 1].reversed())
        return Mesh(polygons)
    }

    static func openSCADCylinder(
        height: Double,
        bottom: Double,
        top: Double,
        segments n: Int,
        center: Bool,
        isCancelled: CancellationHandler
    ) -> Mesh {
        guard height > 0, bottom >= 0, top >= 0, max(bottom, top) > 0, n >= 3, !isCancelled() else { return .empty }
        let z = center ? -height / 2 : 0
        let lower = (0 ..< n).map { j in Vector(
            bottom * cos(Double(j) * 2 * Double.pi / Double(n)),
            bottom * sin(Double(j) * 2 * Double.pi / Double(n)),
            z
        ) }
        let upper = (0 ..< n).map { j in Vector(
            top * cos(Double(j) * 2 * Double.pi / Double(n)),
            top * sin(Double(j) * 2 * Double.pi / Double(n)),
            z + height
        ) }
        var polygons: [Polygon] = []
        func append(_ positions: [Vector]) {
            if let polygon = Polygon(positions.map { Vertex($0) }) {
                polygons.append(polygon)
            }
        }
        append(lower.reversed())
        append(upper)
        for j in 0 ..< n {
            if isCancelled() { return .empty }
            let k = (j + 1) % n
            if top == 0 {
                append([lower[j], lower[k], upper[j]])
            } else if bottom == 0 {
                append([lower[j], upper[k], upper[j]])
            } else if bottom == top {
                append([lower[j], lower[k], upper[k], upper[j]])
            } else {
                append([lower[k], upper[j], lower[j]])
                append([lower[k], upper[k], upper[j]])
            }
        }
        return Mesh(polygons)
    }

    private static func openSCADOctahedralSphere(
        radius: Double,
        divisions: Int,
        isCancelled: CancellationHandler
    ) -> Mesh {
        let distances = (0 ... divisions).map { index in
            index == divisions ? 1 : sin(Double(index) * Double.pi / (2 * Double(divisions)))
        }
        func point(_ i: Int, _ j: Int, _ k: Int) -> Vector {
            let position = Vector(distances[i], distances[j], distances[k])
            guard i > 0, j > 0, k > 0 else { return position * radius }
            // Each edge sample defines a plane through the sphere center and its two
            // corresponding points on the octant boundary. Average their intersections.
            let x = Vector(distances[divisions - i], -position.x, -position.x)
            let y = Vector(-position.y, distances[divisions - j], -position.y)
            let z = Vector(-position.z, -position.z, distances[divisions - k])
            let direction = x.cross(y).normalized() + y.cross(z).normalized() + z.cross(x).normalized()
            return direction.normalized() * radius
        }
        var grid = [[Vector]]()
        for i in 0 ... divisions {
            if isCancelled() { return .empty }
            grid.append((0 ... divisions - i).map { j in point(i, j, divisions - i - j) })
        }
        var polygons = [Polygon]()
        for sx in [-1.0, 1.0] {
            for sy in [-1.0, 1.0] {
                for sz in [-1.0, 1.0] {
                    let signs = Vector(sx, sy, sz)
                    func append(_ a: Vector, _ b: Vector, _ c: Vector) {
                        let corners = sx * sy * sz > 0 ? [a, b, c] : [a, c, b]
                        if let polygon = Polygon(corners.map { $0.scaled(by: signs) }) {
                            polygons.append(polygon)
                        }
                    }
                    for i in 0 ..< divisions {
                        if isCancelled() { return .empty }
                        for j in 0 ..< divisions - i {
                            append(grid[i][j], grid[i + 1][j], grid[i][j + 1])
                            if j + 1 < divisions - i {
                                append(grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
                            }
                        }
                    }
                }
            }
        }
        return Mesh(polygons)
    }
}

extension Path {
    static func openSCADCircle(radius: Double, segments: Int, color: Color? = nil) -> Path {
        guard radius > 0, segments >= 3 else { return .empty }
        return Path((0 ..< segments).map { index in
            let angle = Double(index) * 2 * Double.pi / Double(segments)
            return .point(radius * cos(angle), radius * sin(angle), color: color)
        }).closed()
    }

    /// Calculates the default number of slices for an OpenSCAD extrusion of an XY profile.
    /// Twist and fragment angle are in degrees.
    func openSCADSliceCount(
        height: Double,
        twist: Double,
        taper: Vector,
        fragments: Double,
        fragmentAngle: Double,
        fragmentSize: Double
    ) -> Int? {
        let twist = abs(twist)
        let nonuniformTaper = taper.x != taper.y
        if isEmpty || (twist == 0 && !nonuniformTaper) {
            return 1
        }

        let minimumDistance = 1.0 / 1_048_576
        let fragmentSize = max(0.01, fragmentSize)
        let change = taper - .one
        var radius = 0.0, taperDistance = 0.0
        for point in points {
            let p = point.position
            radius = max(radius, hypot(p.x, p.y))
            if nonuniformTaper {
                taperDistance = max(taperDistance, hypot(p.x * change.x, p.y * change.y))
            }
        }

        var count = max(1, ceil(twist / 120))
        if twist > 0, radius >= minimumDistance {
            let followsSpiral = !nonuniformTaper && taper.x != 1
            if fragments > 0 {
                let twistCount = followsSpiral ? twist * fragments / 360 : twist / 360 * fragments
                count = max(count, ceil(twistCount))
            } else {
                let angularCount = ceil(twist / max(0.01, fragmentAngle))
                if angularCount > count {
                    let angle = twist * (Double.pi / 180)
                    let travel = followsSpiral ? spiralTravel(radius: radius, angle: angle, scale: taper.x) :
                        radius * angle
                    count = max(count, min(angularCount, ceil(hypot(height, travel) / fragmentSize)))
                }
            }
        }
        if nonuniformTaper, taperDistance >= minimumDistance {
            let diagonalCount = fragments > 0 ? floor(fragments) : ceil(hypot(height, taperDistance) / fragmentSize)
            count = max(count, diagonalCount)
        }
        return Int(exactly: count)
    }

    /// Subdivides each contour using OpenSCAD's explicit or automatic extrusion detail.
    /// The caller decides whether to subdivide when the segment count is omitted or zero.
    func withOpenSCADSegments(
        segments: Int,
        fragments: Double,
        fragmentAngle: Double,
        fragmentSize: Double,
        pointLimit: Int,
        twist: Angle,
        taper: Vector,
        sections: Int,
        isCancelled: CancellationHandler
    ) -> Path? {
        guard !isCancelled() else { return .empty }
        let maxLength: Double?
        let limit: Int
        if segments > 0 || fragments > 0 {
            let target = segments > 0 ? segments : Int(exactly: max(3, floor(fragments)))
            guard let target, target < Int.max else { return nil }
            var remaining = pointLimit
            for contour in subpaths {
                let count = max(contour.points.count, target + 1)
                guard count <= remaining else { return nil }
                remaining -= count
            }
            limit = target
            maxLength = nil
        } else {
            limit = Int(ceil(360 / max(0.01, fragmentAngle)))
            maxLength = max(0.01, fragmentSize)
        }
        let taper = Vector(taper.x, taper.y, 1)
        guard isClosed, let plane, twist.isFinite, taper.isFinite else {
            return points.count <= pointLimit ? self : nil
        }
        let contours = subpaths.map { contour -> Path in
            // Planar Booleans can leave collinear points without distinct vertex attributes.
            let closedPoints = contour.points
            let points = closedPoints.dropLast()
            let corners = points.indices.compactMap { index -> PathPoint? in
                let point = points[index]
                let previous = points[index == points.startIndex ? points.endIndex - 1 : index - 1]
                let next = closedPoints[index + 1]
                guard point.color == previous.color, point.color == next.color,
                      point.texcoord == previous.texcoord, point.texcoord == next.texcoord
                else { return point }
                return isCollinearOutlinePoint(point.position, previous.position, next.position) ? nil : point
            }
            return corners.count >= 3 && corners.count < points.count ?
                Path(corners, windingRule: contour.windingRule).closed() : contour
        }
        let pointCount = contours.reduce(0) { $0 + $1.points.count }
        guard pointCount <= pointLimit else { return nil }
        var remaining = pointLimit - pointCount
        guard contours.contains(where: { $0.points.count - 1 < limit }) else {
            return Path(subpaths: contours, windingRule: windingRule)
        }
        // For nonuniform taper, an edge may be longest at an intermediate slice.
        let orientation = Rotation(from: .unitZ, to: plane.normal)
        let slices: [(Rotation, Vector)] = taper.x == taper.y ? [] : (0 ... sections).map {
            let fraction = Double($0) / Double(sections)
            return (Rotation.roll(twist * fraction), Vector.one + (taper - .one) * fraction)
        }
        var subdivided = [Path]()
        for contour in contours {
            let points = contour.points
            let edgeCount = points.count - 1
            guard edgeCount > 0, edgeCount < limit else {
                subdivided.append(contour)
                continue
            }
            var lengths = [Double]()
            lengths.reserveCapacity(edgeCount)
            for (start, end) in zip(points, points.dropFirst()) {
                if isCancelled() { return .empty }
                let edge = end.position - start.position
                let length: Double
                if slices.isEmpty {
                    length = edge.length * (maxLength == nil ? 1 : max(1, taper.x))
                } else {
                    let localEdge = edge.rotated(by: -orientation)
                    length = slices.lazy.map { rotation, scale in
                        localEdge.rotated(by: rotation).scaled(by: scale).length
                    }.max() ?? edge.length
                }
                guard length.isFinite else { return .empty }
                lengths.append(length)
            }
            let counts = maxLength.flatMap { segmentCounts(for: lengths, maxLength: $0, limit: limit) } ??
                segmentCounts(for: lengths, limit: limit, isCancelled: isCancelled)
            guard !isCancelled() else { return .empty }
            let total = counts.reduce(0, +)
            let added = total - edgeCount
            guard added <= remaining else { return nil }
            remaining -= added
            guard added > 0 else {
                subdivided.append(contour)
                continue
            }
            var result = [PathPoint]()
            result.reserveCapacity(total + 1)
            for (index, count) in counts.enumerated() {
                if isCancelled() { return .empty }
                let start = points[index], end = points[index + 1]
                result.append(start)
                for step in 1 ..< count {
                    result.append(start.lerp(end, Double(step) / Double(count)).curved())
                }
            }
            subdivided.append(Path(result, windingRule: contour.windingRule).closed())
        }
        return isCancelled() ? .empty : Path(subpaths: subdivided, windingRule: windingRule)
    }
}

private func spiralTravel(radius: Double, angle: Double, scale: Double) -> Double {
    // The XY projection follows part of an Archimedean spiral whose outer radius is `radius`.
    let fraction = min(1, scale) / max(1, scale)
    let relativeChange = abs(1 - scale) / max(1, scale)
    let end = angle / relativeChange
    if !end.isFinite {
        return radius * angle
    }
    let start = end * fraction
    let startSlope = hypot(1 / end, fraction), endSlope = hypot(1 / end, 1)
    // Factor the difference of θ * hypot(1, θ) to avoid cancellation for nearly uniform scale.
    let slopeTerm = endSlope + fraction * (1 + fraction) / (endSlope + startSlope)
    return radius * 0.5 * (angle * slopeTerm + (asinh(end) - asinh(start)) / end)
}

private func segmentCounts(for lengths: [Double], maxLength: Double, limit: Int) -> [Int]? {
    var counts = [Int]()
    var remaining = limit
    for length in lengths {
        guard let count = Int(exactly: max(1, ceil(length / maxLength))), count < remaining else { return nil }
        remaining -= count
        counts.append(count)
    }
    return counts
}

private func segmentCounts(for lengths: [Double], limit: Int, isCancelled: CancellationHandler) -> [Int] {
    var queue = ExtrusionProfileEdgeQueue()
    for (index, length) in lengths.enumerated() {
        queue.insert(.init(index: index, length: length))
    }
    var counts = Array(repeating: 1, count: lengths.count)
    var remaining = limit - lengths.count
    var group = [ExtrusionProfileEdge]()
    while remaining > 0, let longest = queue.first, !isCancelled() {
        // Keep near-equal subdivisions in step, even if that leaves the target just out of reach.
        while let candidate = queue.first, candidate.priority >= longest.priority * 0.999 {
            group.append(queue.removeFirst())
        }
        guard group.count <= remaining else { break }
        remaining -= group.count
        for var edge in group {
            edge.count += 1
            counts[edge.index] = edge.count
            queue.insert(edge)
        }
        group.removeAll(keepingCapacity: true)
    }
    return counts
}

private func isCollinearOutlinePoint(_ point: Vector, _ start: Vector, _ end: Vector) -> Bool {
    // Use coordinates relative to the test point and the same precision as Euclid's path points.
    let a = start - point, b = end - point
    guard a.dot(b) < 0, let segment = LineSegment(start: a, end: b) else { return false }
    let tolerance = max(4e-12 * (a.length + b.length), a.length * b.length * 1e-10)
    return segment.distance(from: .zero) <= tolerance / segment.length
}

private struct ExtrusionProfileEdge {
    let index: Int
    let length: Double
    var count = 1

    var priority: Double { length / (Double(count) + 0.5) }
}

private struct ExtrusionProfileEdgeQueue {
    private var edges = [ExtrusionProfileEdge]()

    var first: ExtrusionProfileEdge? { edges.first }

    mutating func insert(_ edge: ExtrusionProfileEdge) {
        edges.append(edge)
        var child = edges.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard edge.priority > edges[parent].priority else { break }
            edges.swapAt(child, parent)
            child = parent
        }
    }

    mutating func removeFirst() -> ExtrusionProfileEdge {
        edges.swapAt(0, edges.count - 1)
        let first = edges.removeLast()
        var parent = 0
        while parent * 2 + 1 < edges.count {
            let left = parent * 2 + 1, right = left + 1
            let child = right < edges.count && edges[right].priority > edges[left].priority ? right : left
            guard edges[child].priority > edges[parent].priority else { break }
            edges.swapAt(parent, child)
            parent = child
        }
        return first
    }
}
