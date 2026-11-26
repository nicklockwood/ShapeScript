//
//  Euclid+OpenSCAD.swift
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(CoreText)
import CoreText
#endif

#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

func openSCADCircularSegments(
    radius: Double,
    fragments: Double,
    fragmentAngle: Double,
    fragmentSize: Double,
    fragmentError: Double = 0,
    sweep: Double = 360,
    roundingExplicitCount: FloatingPointRoundingRule = .up
) -> Int? {
    let circumference = abs(radius) * 2 * Double.pi
    let fullTurn: Double
    if fragments > 0 {
        fullTurn = max(3, fragments.rounded(roundingExplicitCount))
    } else if fragmentError >= 1.0 / 1_048_576, radius != 0 {
        // The error is the maximum distance from an arc to its approximating chord.
        let ratio = fragmentError / abs(radius)
        let limit = max(5, min(36_000, circumference / 0.01))
        fullTurn = ratio >= 1 - cos(Double.pi / 5) ? 5 : min(limit, Double.pi / acos(1 - ratio))
    } else {
        fullTurn = ceil(max(5, min(360 / max(0.01, fragmentAngle), circumference / max(0.01, fragmentSize))))
    }
    return Int(exactly: max(1, ceil(fullTurn * abs(sweep) / 360)))
}

func openSCADRevolution(
    angle: Double,
    start: Double,
    bounds: Bounds,
    fragments: Double,
    fragmentAngle: Double,
    fragmentSize: Double,
    fragmentError: Double = 0
) -> (sweep: Double, slices: Int, rotation: Rotation)? {
    let sweep = abs(angle) >= 360 ? 360 : angle
    guard let slices = openSCADCircularSegments(
        radius: max(abs(bounds.min.x), abs(bounds.max.x)),
        fragments: fragments, fragmentAngle: fragmentAngle, fragmentSize: fragmentSize, fragmentError: fragmentError,
        sweep: sweep
    ) else { return nil }
    let startAngle = start.truncatingRemainder(dividingBy: 360)
    // Euclid revolves around Y and begins on -X. OpenSCAD starts on the profile's original side.
    let offset = (bounds.max.x <= 0 ? 0 : 180) - startAngle
    let rotation = Rotation.roll(.degrees(offset)) * Rotation(from: .unitY, to: .unitZ)
    return (sweep, slices, rotation)
}

func openSCADExtrusionDisplacement(height: Double?, direction: Vector?, defaultHeight: Double) -> Vector {
    if let height {
        return (direction ?? .unitZ).normalized() * height
    }
    return direction ?? .unitZ * defaultHeight
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

    /// Shears a centered Z extrusion while keeping its profile in XY.
    func positionedForOpenSCADExtrusion(
        along displacement: Vector,
        centered: Bool,
        isCancelled: CancellationHandler
    ) throws -> Mesh {
        let mesh: Mesh
        if !isEmpty, displacement.x != 0 || displacement.y != 0 {
            let height = displacement.z
            let x = displacement.x / height, y = displacement.y / height
            mesh = try Mesh(polygons.flatMap { polygon in
                if isCancelled() { throw CancellationError() }
                return polygon.mapVertices { vertex in
                    let p = vertex.position, n = vertex.normal
                    let t = p.z / height
                    return Vertex(
                        [p.x + displacement.x * t, p.y + displacement.y * t, p.z],
                        [n.x, n.y, n.z - x * n.x - y * n.y], vertex.texcoord, vertex.color
                    )
                }
            })
        } else {
            mesh = self
        }
        if isCancelled() { throw CancellationError() }
        return centered ? mesh : mesh.translated(by: displacement / 2)
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

    /// Expands or erodes a resolved XY region using offset edges and rounded corners.
    func openSCADRoundedOffset(
        by radius: Double,
        segments: Int,
        isCancelled: CancellationHandler
    ) throws -> Path? {
        guard radius != 0, !isEmpty else { return self }
        let outline = faceNormal.z < 0 ? inverted() : self
        let step = 2 * Double.pi / Double(segments)
        var paths = [outline]
        for contour in outline.subpaths {
            let points = contour.points
            guard contour.isClosed, points.count >= 4 else { continue }
            func normal(from p: PathPoint, to q: PathPoint) -> Vector {
                let edge = q.position - p.position
                return Vector(edge.y, -edge.x).normalized() * radius
            }
            var previous = normal(from: points[points.count - 2], to: points[0])
            for (p, q) in zip(points, points.dropFirst()) {
                if isCancelled() { throw CancellationError() }
                let current = normal(from: p, to: q)
                paths.append(Path([p, p.translated(by: current), q.translated(by: current), q]).closed())
                let turn = atan2(previous.cross(current).z, previous.dot(current))
                if turn * radius > 0 {
                    // Step from the incoming edge normal and always include the outgoing normal.
                    let steps = max(1, Int(ceil(abs(turn) / step)))
                    let signedStep = turn < 0 ? -step : step
                    var corner = [p, p.translated(by: previous)]
                    for index in 1 ..< steps {
                        let angle = signedStep * Double(index)
                        let direction = Vector(
                            previous.x * cos(angle) - previous.y * sin(angle),
                            previous.x * sin(angle) + previous.y * cos(angle)
                        )
                        corner.append(p.translated(by: direction))
                    }
                    corner.append(p.translated(by: current))
                    paths.append(Path(corner).closed())
                }
                previous = current
            }
        }
        let offset = radius > 0 ? Path.union(paths, isCancelled: isCancelled) :
            Path.difference(paths, isCancelled: isCancelled)
        if isCancelled() { throw CancellationError() }
        return offset.map { path in
            Path(subpaths: path.subpaths.map { $0.removingCollinearOutlinePoints() }, windingRule: path.windingRule)
        }
    }

    /// Calculates the default number of slices for an OpenSCAD extrusion of an XY profile.
    /// Twist and fragment angle are in degrees.
    func openSCADSliceCount(
        height: Double,
        twist: Double,
        taper: Vector,
        fragments: Double,
        fragmentAngle: Double,
        fragmentSize: Double,
        fragmentError: Double = 0
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
            } else if fragmentError > 0, !followsSpiral {
                if fragmentError < radius {
                    let chordAngle = 2 * acos(1 - fragmentError / radius)
                    count = max(count, ceil(twist * (Double.pi / 180) / chordAngle))
                }
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
        let contours = subpaths.map { $0.removingCollinearOutlinePoints() }
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

    private func removingCollinearOutlinePoints() -> Path {
        // Planar Booleans can leave collinear points without distinct vertex attributes.
        let closedPoints = points
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
            Path(corners, windingRule: windingRule).closed() : self
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

private struct OpenSCADSurfaceError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { self.errorDescription = message }
}

private func openSCADScriptTag(_ script: String) -> String? {
    guard script.utf8.count == 4, script.utf8.allSatisfy({
        (65 ... 90).contains($0) || (97 ... 122).contains($0)
    }) else { return nil }
    return script.prefix(1).uppercased() + script.dropFirst().lowercased()
}

func openSCADDefaultTextLanguage(script: String) -> String {
    // CoreText needs a matching language to choose localized CJK glyphs.
    switch openSCADScriptTag(script) {
    case "Hans", "Hant", "Hanb": "zh"
    case "Jpan": "ja"
    case "Kore": "ko"
    default: "en"
    }
}

#if canImport(CoreText)

func openSCADTextScriptWarning(_ script: String, text: String) -> String? {
    guard !script.isEmpty, !text.isEmpty else { return nil }
    guard let tag = openSCADScriptTag(script) else {
        return "Invalid script '\(script)' (expected a four-letter script code)"
    }
    // Some locale script codes describe a group of Unicode scripts or a variant.
    let scripts: [String] = switch tag {
    case "Hans", "Hant": ["Hani"]
    case "Jpan": ["Hani", "Hira", "Kana"]
    case "Kore": ["Hang", "Hani"]
    case "Hanb": ["Hani", "Bopo"]
    case "Hrkt": ["Hira", "Kana"]
    case "Latf", "Latg": ["Latn"]
    case "Cyrs": ["Cyrl"]
    case "Jamo": ["Hang"]
    default: [tag]
    }
    let allowed = scripts.map { "\\p{scx=\($0)}" }.joined()
    guard let pattern = try? NSRegularExpression(pattern: "[^\(allowed)\\p{sc=Common}\\p{sc=Inherited}]") else {
        return "Unknown text script '\(script)'"
    }
    if pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
        return "Characters outside script '\(tag)' keep their original writing system"
    }
    return nil
}

private func openSCADTextLanguage(_ language: String, script: String) -> String {
    guard let script = openSCADScriptTag(script) else { return language }
    let identifier = CFLocaleIdentifier(rawValue: language as CFString)
    var components = CFLocaleCreateComponentsFromLocaleIdentifier(nil, identifier) as? [String: String] ?? [:]
    let languageKey = CFLocaleKey.languageCode.rawValue as String
    components[languageKey] = components[languageKey] ?? "und"
    components[CFLocaleKey.scriptCode.rawValue as String] = script
    return CFLocaleCreateLocaleIdentifierFromComponents(nil, components as CFDictionary)?
        .rawValue as String? ?? language
}

func openSCADTextOptions(
    _ text: NSAttributedString,
    direction: String,
    language: String,
    script: String
) -> NSAttributedString {
    guard text.length > 0 else { return text }
    let attributed = NSMutableAttributedString(attributedString: text)
    let range = NSRange(location: 0, length: text.length)
    // CoreText uses the locale for localized glyph selection and font fallback.
    let language = openSCADTextLanguage(language, script: script)
    if !language.isEmpty {
        attributed.addAttribute(.init(kCTLanguageAttributeName as String), value: language, range: range)
    }
    if direction == "rtl" {
        attributed.addAttribute(.init(kCTWritingDirectionAttributeName as String), value: [1], range: range)
    } else if direction == "ttb" || direction == "btt" {
        attributed.addAttribute(.init(kCTVerticalFormsAttributeName as String), value: true, range: range)
    }
    return attributed
}

func openSCADVerticalText(
    _ text: NSAttributedString,
    bottomToTop: Bool,
    spacing: Double,
    detail: Int,
    color: Color?,
    isCancelled: CancellationHandler
) -> [Path] {
    let line = CTLineCreateWithAttributedString(text)
    let direction = bottomToTop ? 1.0 : -1.0
    var y = 0.0
    var paths = [Path]()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        let font = attributes[kCTFontAttributeName] as! CTFont
        for index in 0 ..< CTRunGetGlyphCount(run) {
            if isCancelled() { return [] }
            let range = CFRange(location: index, length: 1)
            var glyph = CGGlyph()
            var advance = CGSize.zero
            CTRunGetGlyphs(run, range, &glyph)
            CTRunGetAdvances(run, range, &advance)
            if let outline = CTFontCreatePathForGlyph(font, glyph, nil) {
                let path = Path(outline, windingRule: .nonZero, detail: detail, color: color)
                let oriented = path.faceNormal.z > 0 ? path.inverted() : path
                paths.append(oriented.translated(by: [0, y]))
            }
            let step = advance.height == 0 ? advance.width : advance.height
            y += direction * abs(Double(step)) * spacing
        }
    }
    return paths
}

#endif

extension Mesh {
    static func openSCADSurface(
        data: Data,
        centered: Bool,
        inverted: Bool,
        isCancelled: CancellationHandler
    ) throws -> Mesh {
        let maximumSamples = 20_000
        let isPNG = data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
        let grid: [[Double]]
        if isPNG {
            #if canImport(ImageIO)
            grid = try openSCADPNGHeights(
                data,
                maximumSamples: maximumSamples,
                inverted: inverted,
                isCancelled: isCancelled
            )
            #else
            throw OpenSCADSurfaceError("PNG surfaces require Image I/O.")
            #endif
        } else {
            guard let text = String(data: data, encoding: .utf8)
            else { throw OpenSCADSurfaceError("Surface data must be UTF-8 numbers or a PNG.") }
            grid = try text.split(whereSeparator: \.isNewline).compactMap { line in
                if isCancelled() { throw CancellationError() }
                let content = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                let fields = content.split(whereSeparator: \.isWhitespace)
                if fields.isEmpty {
                    return nil
                }
                return try fields.map { field in
                    guard let n = Double(field), n.isFinite,
                          abs(n) <= 1e9 else { throw OpenSCADSurfaceError("Invalid surface height.") }
                    return n
                }
            }
        }
        let width = grid.map(\.count).max() ?? 0
        let height = grid.count
        guard width >= 2, height >= 2, width <= maximumSamples / height
        else {
            throw OpenSCADSurfaceError("Surface needs a grid of at least 2x2 and at most 20,000 samples.")
        }
        // DAT caps the minimum at one before padding missing samples with zero.
        let minimum = grid.joined().min() ?? 0
        let bottom = (isPNG ? minimum : min(1, minimum)) - 1
        let offset = centered ? Vector(-Double(width - 1) / 2, -Double(height - 1) / 2, 0) : .zero
        func point(_ x: Int, _ y: Int) -> Vector {
            Vector(Double(x), Double(y), x < grid[y].count ? grid[y][x] : 0) + offset
        }
        var polygons: [Polygon] = []
        func append(_ points: [Vector]) {
            if let p = Polygon(points) {
                polygons.append(p)
            }
        }
        for y in 0 ..< height - 1 {
            if isCancelled() { throw CancellationError() }
            for x in 0 ..< width - 1 {
                let p = [point(x, y), point(x + 1, y), point(x + 1, y + 1), point(x, y + 1)]
                let center = p.reduce(.zero, +) / 4
                for i in 0 ..< 4 {
                    append([p[i], p[(i + 1) % 4], center])
                }
            }
        }
        let boundary = (0 ..< width).map { point($0, 0) }
            + (1 ..< height).map { point(width - 1, $0) }
            + (0 ..< width - 1).reversed().map { point($0, height - 1) }
            + (1 ..< height - 1).reversed().map { point(0, $0) }
        for i in boundary.indices {
            let p = boundary[i], q = boundary[(i + 1) % boundary.count]
            var side = [q, p]
            if p.z != bottom { side.append(Vector(p.x, p.y, bottom)) }
            if q.z != bottom { side.append(Vector(q.x, q.y, bottom)) }
            append(side)
        }
        append(boundary.reversed().map { Vector($0.x, $0.y, bottom) })
        return Mesh(polygons)
    }
}

#if canImport(ImageIO)

private func openSCADPNGHeights(
    _ data: Data,
    maximumSamples: Int,
    inverted: Bool,
    isCancelled: CancellationHandler
) throws -> [[Double]] {
    if isCancelled() { throw CancellationError() }
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width >= 2, height >= 2, width <= maximumSamples / height
    else { throw OpenSCADSurfaceError("Invalid PNG or surface exceeds \(maximumSamples) samples.") }

    // Read the decoded samples directly. Drawing into a bitmap context can apply a color
    // profile, premultiply the colors by alpha, or reduce the sample precision.
    let invalid = OpenSCADSurfaceError("Cannot decode PNG surface samples.")
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
          image.width == width, image.height == height, let space = image.colorSpace,
          let provider = image.dataProvider?.data, let pixels = CFDataGetBytePtr(provider),
          image.bytesPerRow <= CFDataGetLength(provider) / height
    else { throw invalid }
    defer { withExtendedLifetime(provider) {} }
    let colorComponents: Int
    let palette: [UInt8]?
    switch space.model {
    case .monochrome: (colorComponents, palette) = (1, nil)
    case .rgb: (colorComponents, palette) = (3, nil)
    case .indexed:
        guard let colors = space.colorTable else { throw invalid }
        colorComponents = 1
        palette = colors
    default: throw invalid
    }
    let firstColor: Int, components: Int
    switch image.alphaInfo {
    case .none: (firstColor, components) = (0, colorComponents)
    case .last, .noneSkipLast: (firstColor, components) = (0, colorComponents + 1)
    case .first, .noneSkipFirst: (firstColor, components) = (1, colorComponents + 1)
    default: throw invalid
    }
    let depth = image.bitsPerComponent
    guard [1, 2, 4, 8, 16].contains(depth), depth >= 8 || components == 1,
          image.bitsPerPixel == components * depth, image.bytesPerRow >= (width * image.bitsPerPixel + 7) / 8
    else { throw invalid }

    let order = image.bitmapInfo.intersection(.byteOrderMask)
    let reversed = depth == 8 && (order == .byteOrder32Little || order == .byteOrder16Little)
    let littleEndian = order == .byteOrder16Little
    let maximum = Double(palette == nil ? (1 << depth) - 1 : 255)
    let scale = inverted ? -100.0 : 100
    return try (0 ..< height).reversed().map { y in
        if isCancelled() { throw CancellationError() }
        let row = pixels + y * image.bytesPerRow
        return try (0 ..< width).map { x in
            func sample(_ color: Int) -> Int {
                if depth < 8 {
                    let bit = x * depth
                    return Int(row[bit / 8] >> (8 - depth - bit % 8)) & ((1 << depth) - 1)
                }
                let component = firstColor + color
                let index = x * components + (reversed ? components - 1 - component : component)
                if depth == 8 { return Int(row[index]) }
                let value = UInt16(row[index * 2]) << 8 | UInt16(row[index * 2 + 1])
                return Int(littleEndian ? value.byteSwapped : value)
            }
            let firstSample = sample(0)
            let (red, green, blue): (Int, Int, Int)
            if let palette {
                let index = firstSample * 3
                guard index + 2 < palette.count else { throw invalid }
                (red, green, blue) = (Int(palette[index]), Int(palette[index + 1]), Int(palette[index + 2]))
            } else if colorComponents == 1 {
                return Double(firstSample) / maximum * scale
            } else {
                (red, green, blue) = (firstSample, sample(1), sample(2))
            }
            return Color(
                red: Double(red) / maximum,
                green: Double(green) / maximum,
                blue: Double(blue) / maximum
            ).luminance * scale
        }
    }
}

#endif
