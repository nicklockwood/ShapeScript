//
//  SVGImport.swift
//  ShapeScript
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import SVGPath
#if canImport(CoreText)
import CoreText
#endif
#if canImport(FoundationXML)
import FoundationXML
#endif

struct SVGImportOptions {
    var id: String?
    var layer: String?
    var center = false
    var dpi = 96.0
    var detail = 16
    var csg = false
    var segments: ((Double) throws -> Int)?
}

enum SVGImportError: Error, LocalizedError {
    case invalidDocument(message: String, hint: String?, line: Int, column: Int)
    case missingElement(String, options: [String])

    init(message: String, hint: String? = nil, line: Int, column: Int = 1) {
        self = .invalidDocument(message: message, hint: hint, line: line, column: column)
    }

    // XMLParser reports libxml2 codes, but older swift-corelibs-foundation releases
    // assign different raw values to XMLParser.ErrorCode. Keep the wire values here.
    private enum XMLSyntaxErrorCode: Int {
        case emptyDocumentError = 4
        case prematureDocumentEndError = 5
        case entityReferenceWithoutNameError = 22
        case entityReferenceMissingSemiError = 23
        case undeclaredEntityError = 26
        case stringNotStartedError = 33
        case stringNotClosedError = 34
        case attributeNotStartedError = 39
        case attributeNotFinishedError = 40
        case attributeHasNoValueError = 41
        case attributeRedefinedError = 42
        case commentNotFinishedError = 45
        case gtRequiredError = 73
        case tagNameMismatchError = 76
        case unfinishedTagError = 77
    }

    init(parser: XMLParser, error: Error?) {
        let error = error as NSError?
        let message: String
        var hint: String?
        switch error.flatMap({ XMLSyntaxErrorCode(rawValue: $0.code) }) {
        case .emptyDocumentError:
            message = "SVG document is empty"
        case .prematureDocumentEndError, .unfinishedTagError:
            message = "Unexpected end of SVG document"
            hint = "A tag may be incomplete or missing its closing tag."
        case .tagNameMismatchError:
            message = "SVG opening and closing tags do not match"
        case .attributeNotStartedError, .stringNotStartedError:
            message = "SVG attribute values must be enclosed in quotes"
        case .attributeNotFinishedError, .stringNotClosedError:
            message = "SVG attribute value is missing its closing quote"
        case .attributeHasNoValueError:
            message = "SVG attribute is missing a value"
        case .attributeRedefinedError:
            message = "SVG element has a duplicate attribute"
        case .undeclaredEntityError:
            message = "Unknown XML entity in SVG"
            hint = "Use &amp; for a literal '&'."
        case .entityReferenceWithoutNameError, .entityReferenceMissingSemiError:
            message = "Invalid XML entity in SVG"
            hint = "Use &amp; for a literal '&'."
        case .commentNotFinishedError:
            message = "SVG comment is missing its closing '-->'"
        case .gtRequiredError:
            message = "SVG tag is missing its closing '>'"
        default:
            let detail = (error?.userInfo["NSXMLParserErrorMessage"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            message = detail.flatMap { $0.isEmpty ? nil : "Invalid SVG XML: " + $0 } ?? "Invalid SVG XML syntax"
        }
        self.init(message: message, hint: hint, line: parser.lineNumber, column: parser.columnNumber)
    }

    var message: String {
        switch self {
        case let .invalidDocument(message, _, _, _): message
        case let .missingElement(id, _): "SVG element '#\(id)' not found"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case let .invalidDocument(_, hint, _, _): hint
        case .missingElement: nil
        }
    }

    var errorDescription: String? {
        switch self {
        case let .invalidDocument(message, _, line, _): "\(message) on line \(line)."
        case .missingElement: message
        }
    }
}

/// XML callbacks only collect nodes. Geometry conversion and reference resolution happen
/// after parse() returns: XMLParser must never be reentered from a delegate callback.
final class SVGDocument {
    private let root: SVGElement
    private let elementsByID: [String: SVGElement]

    init(data: Data, isCancelled: @escaping CancellationHandler) throws {
        let delegate = SVGXMLDelegate(isCancelled: isCancelled)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        let succeeded = parser.parse()
        if isCancelled() { throw CancellationError() }
        if let error = delegate.error { throw error }
        guard succeeded, let root = delegate.root else {
            throw SVGImportError(parser: parser, error: parser.parserError)
        }
        guard root.name == "svg" else {
            throw SVGImportError(message: "Expected an SVG document", line: root.line)
        }
        self.root = root
        self.elementsByID = delegate.elementsByID
    }

    func geometry(
        options: SVGImportOptions,
        fileURL: URL? = nil,
        isCancelled: @escaping CancellationHandler,
        warn: @escaping (String, Int) -> Void
    ) throws -> Geometry {
        guard options.dpi.isFinite, options.dpi > 0 else {
            throw SVGImportError(message: "SVG DPI must be positive", line: root.line)
        }
        var foundSelection = options.id == nil && options.layer == nil
        func warning(_ message: String, _ element: SVGElement) {
            warn(message, element.line)
        }
        let page = try root.pageMatrix(dpi: options.dpi, csg: options.csg)
        let clipping = SVGClipping(
            elements: elementsByID,
            detail: options.detail,
            isCancelled: isCancelled,
            warn: warning
        )
        var hierarchy: [[Geometry]] = [[]]
        func visit(
            _ element: SVGElement, matrix parentMatrix: SVGMatrix, style inherited: [String: String],
            selected parentSelected: Bool, inLayer parentInLayer: Bool, references: Set<String>, depth: Int
        ) throws {
            if isCancelled() { throw CancellationError() }
            guard depth < 256 else { throw SVGImportError(message: "SVG nesting is too deep", line: element.line) }
            let a = element.attributes
            var shapePaths: [Path]?
            var includeInHierarchy = options.id == nil
            hierarchy.append([])
            defer {
                let children = hierarchy.removeLast()
                if !includeInHierarchy {
                    // Ancestor transforms are already baked into the selected paths.
                    hierarchy[hierarchy.count - 1].append(contentsOf: children)
                } else if shapePaths != nil || !children.isEmpty {
                    let type = shapePaths.map { GeometryType.path(Path(subpaths: $0)) } ?? .group
                    let location = SourceLocation(at: element.line, in: fileURL)
                    hierarchy[hierarchy.count - 1].append(Geometry(
                        type: type, name: a["id"], transform: .identity, material: .default,
                        smoothing: .zero, children: children, sourceLocation: { location }
                    ))
                }
            }
            func build() throws {
                let style = element.style(inheriting: inherited)
                let inLayer = parentInLayer || (options.layer != nil && a["inkscape:label"] == options.layer)
                var selected = parentSelected ||
                    (options.id != nil && a["id"] == options.id && (options.layer == nil || inLayer)) ||
                    (options.id == nil && options.layer != nil && inLayer)
                includeInHierarchy = options.id == nil || selected
                if selected { foundSelection = true }
                if style["display"] == "none" || style["visibility"] == "hidden" { return }
                let matrix = try parentMatrix * SVGMatrix.parse(a["transform"] ?? "", line: element.line)
                if options.csg, style["clip-path"] != nil || style["mask"] != nil {
                    warning("SVG clipping and masking are not supported", element)
                } else if style["mask"] != nil {
                    warning("SVG masking is not supported", element)
                }
                switch element.name {
                case "defs", "symbol":
                    // Definitions are instantiated by <use>, or explicitly selected by ID.
                    if references.isEmpty {
                        guard let id = options.id else { return }
                        selected = a["id"] == id
                    }
                case "svg", "g", "a": break
                case "title", "desc", "metadata", "clipPath": return
                case "use":
                    guard selected else { return }
                    let href = a["href"] ?? a["xlink:href"] ?? ""
                    guard href.hasPrefix("#") else {
                        warning("External SVG references are not supported", element)
                        return
                    }
                    let id = String(href.dropFirst()).removingPercentEncoding ?? String(href.dropFirst())
                    guard !references.contains(id) else {
                        throw SVGImportError(message: "Circular SVG reference '#\(id)'", line: element.line)
                    }
                    guard let target = elementsByID[id] else {
                        warning("SVG element '#\(id)' not found", element)
                        return
                    }
                    let offset = try SVGMatrix.translation(element.length("x"), element.length("y"))
                    try visit(
                        target,
                        matrix: matrix * offset,
                        style: style,
                        selected: true,
                        inLayer: inLayer,
                        references: references.union([id]),
                        depth: depth + 1
                    )
                    return
                case "text":
                    guard selected else { return }
                    guard !options.csg else {
                        warning("Unsupported SVG element 'text'", element)
                        return
                    }
                    #if canImport(CoreText)
                    shapePaths = try element.textPaths(
                        style: style,
                        detail: options.detail,
                        isCancelled: isCancelled,
                        warn: warning
                    ).map { path in
                        let positions = path.points.map { matrix.apply($0.position) }
                        guard positions.allSatisfy(\.isFinite) else {
                            throw SVGImportError(message: "SVG transform overflow", line: element.line)
                        }
                        return path.mapPoints { $0.withPosition(matrix.apply($0.position)) }
                    }
                    #else
                    warning("SVG text is not supported on this platform", element)
                    #endif
                    return
                case "path", "rect", "circle", "ellipse", "polygon", "polyline", "line":
                    guard selected else { return }
                    let path = try element.path(detail: options.detail, segments: options.segments)
                    let paths: [Path]
                    if options.csg {
                        var closed = [Path]()
                        for subpath in path.subpaths {
                            if subpath.isClosed {
                                closed.append(subpath)
                            } else {
                                let width = try SVGElement.length(style["stroke-width"] ?? "1", line: element.line)
                                closed += try svgStroke(
                                    subpath,
                                    width: width < 0.01 ? 1 : width,
                                    cap: style["stroke-linecap"] ?? "butt",
                                    join: style["stroke-linejoin"] ?? "miter",
                                    detail: options.segments?(width / 2) ?? options.detail,
                                    isCancelled: isCancelled
                                ).subpaths
                            }
                        }
                        paths = [Path(subpaths: closed)]
                    } else {
                        paths = [path]
                    }
                    shapePaths = try paths.filter { !$0.isEmpty }.map { path in
                        let positions = path.points.map { matrix.apply($0.position) }
                        guard positions.allSatisfy(\.isFinite) else {
                            throw SVGImportError(message: "SVG transform overflow", line: element.line)
                        }
                        return path.mapPoints { $0.withPosition(matrix.apply($0.position)) }
                    }
                    return
                default:
                    if selected { warning("Unsupported SVG element '\(element.name)'", element) }
                    return
                }
                for child in element.children {
                    try visit(
                        child,
                        matrix: matrix,
                        style: style,
                        selected: selected,
                        inLayer: inLayer,
                        references: references,
                        depth: depth + 1
                    )
                }
            }
            try build()
            if !options.csg, element.name != "clipPath", shapePaths != nil || !hierarchy.last!.isEmpty {
                let style = element.style(inheriting: inherited)
                if let value = style["clip-path"], value != "none" {
                    let localBounds = try Bounds(clipping.contents(
                        element, style: style, references: references, depth: depth, applyClips: false
                    ))
                    if let boundary = try clipping.region(
                        value,
                        bounds: localBounds,
                        element: element,
                        references: references,
                        depth: depth
                    ) {
                        let matrix = try parentMatrix * SVGMatrix.parse(a["transform"] ?? "", line: element.line)
                        let boundary = try clipping.transformed(boundary, by: matrix, element: element)
                        shapePaths = try shapePaths.map { try $0.map { try clipping.clip($0, to: boundary) } }
                        hierarchy[hierarchy.count - 1] = try hierarchy.last!.map { try clipping.clip($0, to: boundary) }
                    }
                }
            }
        }
        try visit(root, matrix: page, style: [:], selected: foundSelection, inLayer: false, references: [], depth: 0)
        if !foundSelection, let id = options.id {
            throw SVGImportError.missingElement(id, options: elementsByID.keys.sorted())
        }
        if !foundSelection {
            warning("SVG selection '\(options.id.map { "#" + $0 } ?? options.layer ?? "")' not found", root)
        }
        var geometry = hierarchy[0].first ?? Geometry(
            type: .group, name: root.attributes["id"], transform: .identity, material: .default,
            smoothing: .zero, children: [], sourceLocation: nil
        )
        if options.center {
            geometry = geometry.transformed(by: .translation(-geometry.overestimatedBounds.center))
        }
        if options.csg {
            guard let union = Path.union(geometry.paths(pretransformed: true), isCancelled: isCancelled) else {
                throw SVGImportError(message: "Unable to combine SVG shapes", line: root.line)
            }
            geometry = Geometry(
                type: .path(union),
                name: nil,
                transform: .identity,
                material: .default,
                smoothing: .zero,
                children: [],
                sourceLocation: nil
            )
        }
        if isCancelled() { throw CancellationError() }
        return geometry
    }
}

/// Resolves clip definitions separately from scene selection, so fragment imports retain
/// ancestor clips and object bounds include unselected siblings.
private struct SVGClipping {
    let elements: [String: SVGElement]
    let detail: Int
    let isCancelled: CancellationHandler
    let warn: (String, SVGElement) -> Void

    func transformed(_ path: Path, by matrix: SVGMatrix, element: SVGElement) throws -> Path {
        guard path.points.allSatisfy({ matrix.apply($0.position).isFinite }) else {
            throw SVGImportError(message: "SVG transform overflow", line: element.line)
        }
        return path.mapPoints { $0.withPosition(matrix.apply($0.position)) }
    }

    func clip(_ path: Path, to boundary: Path) throws -> Path {
        if isCancelled() { throw CancellationError() }
        if boundary.isEmpty { return .empty }
        let closed = Path(subpaths: path.subpaths.filter(\.isClosed))
        let open = Path(subpaths: path.subpaths.filter { !$0.isClosed })
        guard let region = closed.intersection(boundary, isCancelled: isCancelled),
              let fragments = open.split(along: boundary, isCancelled: isCancelled)
        else { throw SVGImportError(message: "Unable to clip SVG geometry", line: 1) }
        return Path(subpaths: region.subpaths + fragments.inside.subpaths)
    }

    func clip(_ geometry: Geometry, to boundary: Path) throws -> Geometry {
        let type: GeometryType = if case let .path(path) = geometry.type {
            try .path(clip(path, to: boundary))
        } else { geometry.type }
        return try Geometry(
            type: type, name: geometry.name, transform: geometry.transform,
            material: geometry.material, smoothing: geometry.smoothing,
            children: geometry.children.map { try clip($0, to: boundary) },
            sourceLocation: { geometry.sourceLocation }
        )
    }

    func region(
        _ value: String,
        bounds: Bounds,
        element: SVGElement,
        references: Set<String>,
        depth: Int
    ) throws -> Path? {
        if isCancelled() { throw CancellationError() }
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "none" { return nil }
        guard value.hasPrefix("url("), value.hasSuffix(")") else {
            warn("Unsupported SVG clip-path '\(value)'", element)
            return nil
        }
        let reference = value.dropFirst(4).dropLast()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
        guard reference.hasPrefix("#") else {
            warn("External SVG clip references are not supported", element)
            return nil
        }
        let id = String(reference.dropFirst()).removingPercentEncoding ?? String(reference.dropFirst())
        guard !references.contains(id) else {
            throw SVGImportError(message: "Circular SVG clip reference '#\(id)'", line: element.line)
        }
        guard let target = elements[id], target.name == "clipPath" else {
            warn("SVG clipPath '#\(id)' not found", element)
            return nil
        }
        let units = target.attributes["clipPathUnits"] ?? "userSpaceOnUse"
        let matrix: SVGMatrix
        switch units {
        case "userSpaceOnUse": matrix = .identity
        case "objectBoundingBox":
            // SVG ignores object-bounding-box effects on zero-width or zero-height geometry.
            guard bounds.size.x > 0, bounds.size.y > 0 else { return nil }
            matrix = SVGMatrix(a: bounds.size.x, d: bounds.size.y, e: bounds.min.x, f: bounds.min.y)
        default:
            warn("Unsupported SVG clipPathUnits '\(units)'", target)
            return nil
        }
        var ancestors = [SVGElement]()
        var parent = target.parent
        while let element = parent {
            ancestors.append(element)
            parent = element.parent
        }
        let inherited = ancestors.reversed().reduce([String: String]()) { $1.style(inheriting: $0) }
        let paths = try elementPaths(
            target,
            inherited: inherited,
            references: references.union([id]),
            depth: depth + 1,
            applyClips: true
        )
        guard let path = Path.union(paths, isCancelled: isCancelled) else {
            throw SVGImportError(message: "Unable to combine SVG clip shapes", line: target.line)
        }
        return try transformed(path, by: matrix, element: target)
    }

    func elementPaths(
        _ element: SVGElement,
        inherited: [String: String],
        references: Set<String>,
        depth: Int,
        applyClips: Bool
    ) throws -> [Path] {
        let style = element.style(inheriting: inherited)
        var paths = try contents(element, style: style, references: references, depth: depth, applyClips: applyClips)
        if applyClips, let value = style["clip-path"],
           let boundary = try region(
               value,
               bounds: Bounds(paths),
               element: element,
               references: references,
               depth: depth
           )
        {
            paths = try paths.map { try clip($0, to: boundary) }
        }
        let matrix = try SVGMatrix.parse(element.attributes["transform"] ?? "", line: element.line)
        return try paths.map { try transformed($0, by: matrix, element: element) }
    }

    /// Local-space geometry before the element's own transform or clip.
    func contents(
        _ element: SVGElement,
        style: [String: String],
        references: Set<String>,
        depth: Int,
        applyClips: Bool
    ) throws -> [Path] {
        if isCancelled() { throw CancellationError() }
        guard depth < 256 else { throw SVGImportError(message: "SVG nesting is too deep", line: element.line) }
        if style["display"] == "none" || style["visibility"] == "hidden" { return [] }
        switch element.name {
        case "clipPath", "svg", "g", "a", "symbol":
            return try element.children.flatMap { child in
                // Clip definitions are resources, never visible child geometry.
                if child.name == "clipPath" || child.name == "defs" { return [Path]() }
                return try elementPaths(
                    child,
                    inherited: style,
                    references: references,
                    depth: depth + 1,
                    applyClips: applyClips
                )
            }
        case "use":
            let href = element.attributes["href"] ?? element.attributes["xlink:href"] ?? ""
            guard href.hasPrefix("#") else {
                if applyClips { warn("External SVG references are not supported", element) }
                return []
            }
            let id = String(href.dropFirst()).removingPercentEncoding ?? String(href.dropFirst())
            guard !references.contains(id) else {
                throw SVGImportError(message: "Circular SVG reference '#\(id)'", line: element.line)
            }
            guard let target = elements[id] else {
                if applyClips { warn("SVG element '#\(id)' not found", element) }
                return []
            }
            let paths = try elementPaths(
                target,
                inherited: style,
                references: references.union([id]),
                depth: depth + 1,
                applyClips: applyClips
            )
            let matrix = try SVGMatrix.translation(element.length("x"), element.length("y"))
            return try paths.map { try transformed($0, by: matrix, element: element) }
        case "text":
            #if canImport(CoreText)
            return try element.textPaths(
                style: style,
                detail: detail,
                isCancelled: isCancelled,
                warn: applyClips ? warn : { _, _ in }
            )
            #else
            if applyClips { warn("SVG text is not supported on this platform", element) }
            return []
            #endif
        case "path", "rect", "circle", "ellipse", "polygon", "polyline", "line":
            let path = try element.path(detail: detail, segments: nil)
            return try applyClips ? [filledRegion(path, rule: style["clip-rule"] ?? "nonzero", element: element)] :
                [path]
        case "defs", "title", "desc", "metadata": return []
        default:
            if applyClips { warn("Unsupported SVG clip element '\(element.name)'", element) }
            return []
        }
    }

    func filledRegion(_ path: Path, rule: String, element: SVGElement) throws -> Path {
        let contours = path.subpaths.map { $0.closed() }.filter { $0.points.count > 3 }
        if rule == "evenodd" {
            return Path.symmetricDifference(contours, isCancelled: isCancelled) ?? .empty
        }
        if rule != "nonzero" { warn("Unsupported SVG clip-rule '\(rule)'", element) }
        // Track disjoint regions by winding count. A compound nonzero path is not
        // simply the union (or XOR) of its contours: opposing windings cancel.
        var regions = [(winding: Int, path: Path)]()
        for contour in contours {
            if isCancelled() { throw CancellationError() }
            let points = contour.points.map(\.position)
            let area = zip(points, points.dropFirst()).reduce(0.0) { $0 + $1.0.x * $1.1.y - $1.1.x * $1.0.y }
            let sign = area < 0 ? -1 : 1
            var remainder = contour
            var next = [(winding: Int, path: Path)]()
            for region in regions {
                guard let inside = region.path.intersection(contour, isCancelled: isCancelled),
                      let outside = region.path.subtracting(contour, isCancelled: isCancelled),
                      let rest = remainder.subtracting(region.path, isCancelled: isCancelled)
                else { throw SVGImportError(message: "Unable to resolve SVG clip region", line: element.line) }
                if !outside.isEmpty { next.append((region.winding, outside)) }
                if !inside.isEmpty { next.append((region.winding + sign, inside)) }
                remainder = rest
            }
            if !remainder.isEmpty { next.append((sign, remainder)) }
            regions = next
        }
        return Path.union(regions.filter { $0.winding != 0 }.map(\.path), isCancelled: isCancelled) ?? .empty
    }
}

private final class SVGElement {
    let name: String
    let attributes: [String: String]
    let line: Int
    weak var parent: SVGElement?
    var children = [SVGElement]()
    var content = [Content]()

    enum Content {
        case text(String)
        case element(SVGElement)
    }

    init(name: String, attributes: [String: String], line: Int) {
        self.name = name.split(separator: ":").last.map(String.init) ?? name
        self.attributes = attributes
        self.line = line
    }

    func style(inheriting inherited: [String: String]) -> [String: String] {
        var style = inherited
        style.removeValue(forKey: "clip-path")
        style.removeValue(forKey: "mask")
        for key in ["clip-path", "mask"] {
            if let value = attributes[key] { style[key] = value }
        }
        for key in [
            "display",
            "visibility",
            "stroke-width",
            "stroke-linecap",
            "stroke-linejoin",
            "fill-rule",
            "clip-rule",
            "font-family",
            "font-size",
            "font-weight",
            "font-style",
            "letter-spacing",
            "text-anchor",
            "xml:space",
        ] {
            if let value = attributes[key] { style[key] = value }
        }
        for declaration in (attributes["style"] ?? "").split(separator: ";") {
            let parts = declaration.split(separator: ":", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if parts.count == 2 { style[parts[0]] = parts[1] }
        }
        return style
    }

    func length(_ name: String, default fallback: Double = 0) throws -> Double {
        try attributes[name].map { try Self.length($0, line: line) } ?? fallback
    }

    /// Converts explicit physical units to SVG user units (96 units per inch).
    static func length(_ text: String, line: Int) throws -> Double {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let units: [(String, Double)] = [
            ("px", 1),
            ("mm", 96 / 25.4),
            ("cm", 96 / 2.54),
            ("in", 96),
            ("pt", 96 / 72),
            ("pc", 16),
        ]
        for (suffix, scale) in units where text.hasSuffix(suffix) {
            guard let value = Double(text.dropLast(suffix.count)), value.isFinite else {
                throw SVGImportError(message: "Invalid SVG length '\(text)'", line: line)
            }
            return value * scale
        }
        guard let value = Double(text), value.isFinite else {
            throw SVGImportError(message: "Unsupported SVG length '\(text)'", line: line)
        }
        return value
    }

    func path(detail: Int, segments: ((Double) throws -> Int)?) throws -> Path {
        switch name {
        case "path":
            do {
                return try Path(
                    SVGPath(string: attributes["d"] ?? "", with: .init(invertYAxis: false)),
                    detail: max(1, detail / 4)
                )
            } catch {
                throw SVGImportError(message: "Invalid SVG path: \(error.localizedDescription)", line: line)
            }
        case "line":
            return try .line([length("x1"), length("y1")], [length("x2"), length("y2")])
        case "polygon", "polyline":
            let numbers = try svgNumbers(attributes["points"] ?? "", line: line)
            guard numbers.count.isMultiple(of: 2)
            else { throw SVGImportError(message: "Invalid SVG points", line: line) }
            let path = Path(stride(from: 0, to: numbers.count, by: 2).map { .point(numbers[$0], numbers[$0 + 1]) })
            return name == "polygon" ? path.closed() : path
        case "circle", "ellipse":
            let rx = try length(name == "circle" ? "r" : "rx")
            let ry = try name == "circle" ? rx : length("ry")
            guard rx >= 0, ry >= 0 else { throw SVGImportError(message: "SVG radius must be non-negative", line: line) }
            if rx == 0 || ry == 0 { return .empty }
            return try .ellipse(width: rx * 2, height: ry * 2, segments: max(3, segments?(max(rx, ry)) ?? detail))
                .translated(by: [
                    length("cx"),
                    length("cy"),
                ])
        case "rect":
            let w = try length("width"), h = try length("height")
            guard w >= 0,
                  h >= 0 else { throw SVGImportError(message: "SVG dimensions must be non-negative", line: line) }
            if w == 0 || h == 0 { return .empty }
            let x = try length("x"), y = try length("y")
            let rx = try min(w / 2, length("rx", default: length("ry")))
            let ry = try min(h / 2, length("ry", default: length("rx")))
            guard rx >= 0, ry >= 0 else { throw SVGImportError(message: "SVG radius must be non-negative", line: line) }
            if rx == 0 || ry == 0 { return .rectangle(width: w, height: h).translated(by: [x + w / 2, y + h / 2]) }
            let d = "M\(x + rx) \(y)H\(x + w - rx)A\(rx) \(ry) 0 0 1 \(x + w) \(y + ry)V\(y + h - ry)A\(rx) \(ry) 0 0 1 \(x + w - rx) \(y + h)H\(x + rx)A\(rx) \(ry) 0 0 1 \(x) \(y + h - ry)V\(y + ry)A\(rx) \(ry) 0 0 1 \(x + rx) \(y)Z"
            return try Path(SVGPath(string: d, with: .init(invertYAxis: false)), detail: max(1, detail / 4))
        default: return .empty
        }
    }

    func pageMatrix(dpi: Double, csg: Bool) throws -> SVGMatrix {
        let viewBox = try attributes["viewBox"].map { try svgNumbers($0, line: line) }
        if let viewBox, viewBox.count != 4 || viewBox[2] <= 0 || viewBox[3] <= 0 {
            throw SVGImportError(message: "Invalid SVG viewBox", line: line)
        }
        func dimension(_ name: String, fallback: Double) throws -> Double {
            guard let value = attributes[name] else { return fallback * 25.4 / dpi }
            if value.hasSuffix("%"), let percent = Double(value.dropLast()), percent.isFinite {
                return fallback * percent / 100 * 25.4 / dpi
            }
            let n = try Self.length(value, line: line)
            return n * 25.4 / (Double(value) == nil ? 96 : dpi)
        }
        let width = try dimension("width", fallback: viewBox?[2] ?? 0)
        let height = try dimension("height", fallback: viewBox?[3] ?? 0)
        guard width >= 0, height >= 0 else { throw SVGImportError(
            message: "SVG dimensions must be non-negative",
            line: line
        ) }
        guard let v = viewBox else {
            // OpenSCAD leaves user coordinates unscaled when viewBox is absent.
            let scale = csg ? 1 : 25.4 / dpi
            return SVGMatrix(a: scale, d: -scale, f: height)
        }
        var sx = width / v[2], sy = height / v[3]
        var ax = 0.0, ay = 0.0
        let aspect = attributes["preserveAspectRatio"] ?? "xMidYMid meet"
        if !aspect.contains("none") {
            sx = aspect.contains("slice") ? max(sx, sy) : min(sx, sy)
            sy = sx
            ax = (width - v[2] * sx) * (aspect.contains("xMin") ? 0 : aspect.contains("xMax") ? 1 : 0.5)
            ay = (height - v[3] * sy) * (aspect.contains("YMin") ? 0 : aspect.contains("YMax") ? 1 : 0.5)
        }
        return SVGMatrix(a: sx, d: -sy, e: ax - sx * v[0], f: height - ay + sy * v[1] * (csg ? -1 : 1))
    }
}

#if canImport(CoreText)
private extension SVGElement {
    func textLengths(_ value: String) throws -> [Double] {
        let scanner = Scanner(string: value)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        scanner.charactersToBeSkipped = nil
        let separators = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ","))
        var values = [Double]()
        while true {
            _ = scanner.scanCharacters(from: separators)
            if scanner.isAtEnd { return values }
            guard let number = scanner.scanDouble(), number.isFinite else {
                throw SVGImportError(message: "Invalid SVG text position list", line: line)
            }
            let unit = scanner.scanCharacters(from: .letters) ?? ""
            try values.append(Self.length(String(number) + unit, line: line))
        }
    }

    func textPaths(
        style: [String: String], detail: Int, isCancelled: @escaping CancellationHandler,
        warn: (String, SVGElement) -> Void
    ) throws -> [Path] {
        let text = NSMutableAttributedString(string: "")
        var previousWasSpace = true
        var x = 0.0, y = 0.0
        var chunkStart = 0.0
        var anchor = style["text-anchor"] ?? "start"
        var paths = [Path]()
        var chunk = [Path]()
        var preserveSpace = false
        var rotation = 0.0
        struct PositionList {
            var values: [String: [Double]]
            var index = 0
        }
        var positions = [PositionList]()
        func position(_ name: String) -> Double? {
            for list in positions.reversed() {
                guard let values = list.values[name], !values.isEmpty else { continue }
                if list.index < values.count { return values[list.index] }
                if name == "rotate" { return values.last }
            }
            return nil
        }
        func flushRun(trimTrailingSpace: Bool = false) {
            if trimTrailingSpace, !preserveSpace, text.string.hasSuffix(" ") {
                text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
            }
            guard text.length > 0 else { return }
            let line = CTLineCreateWithAttributedString(text)
            let advance = CTLineGetTypographicBounds(line, nil, nil, nil)
            chunk += Path.text(text, detail: max(1, detail / 8), isCancelled: isCancelled).map { path in
                let angle = rotation * .pi / 180
                return path.mapPoints {
                    let p = $0.position
                    return $0.withPosition([
                        x + cos(angle) * p.x + sin(angle) * p.y,
                        y + sin(angle) * p.x - cos(angle) * p.y,
                        0,
                    ])
                }
            }
            x += advance
            text.deleteCharacters(in: NSRange(location: 0, length: text.length))
        }
        func flushChunk() {
            flushRun(trimTrailingSpace: true)
            let advance = x - chunkStart
            let offset = anchor == "middle" ? advance / 2 : anchor == "end" ? advance : 0
            paths += chunk.map { $0.translated(by: [-offset, 0, 0]) }
            chunk.removeAll()
        }
        func append(_ node: SVGElement, style inherited: [String: String], size parentSize: Double) throws {
            if isCancelled() { throw CancellationError() }
            var style = inherited
            for key in [
                "font-family",
                "font-size",
                "font-weight",
                "font-style",
                "letter-spacing",
                "xml:space",
                "display",
                "visibility",
                "text-anchor",
            ] {
                if let value = node.attributes[key] { style[key] = value }
            }
            for declaration in (node.attributes["style"] ?? "").split(separator: ";") {
                let parts = declaration.split(separator: ":", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if parts.count == 2 { style[parts[0]] = parts[1] }
            }
            if style["display"] == "none" || style["visibility"] == "hidden" { return }
            var lists = [String: [Double]]()
            for key in ["x", "y", "dx", "dy", "rotate"] {
                if let value = node.attributes[key] {
                    lists[key] = try key == "rotate" ? svgNumbers(value, line: node.line) : node.textLengths(value)
                }
            }
            positions.append(PositionList(values: lists))
            defer { positions.removeLast() }
            if lists["x"]?.isEmpty == false || lists["y"]?.isEmpty == false {
                previousWasSpace = true
            }
            for key in ["textLength", "lengthAdjust", "dominant-baseline", "alignment-baseline"] {
                if node.attributes[key] != nil || style[key] != nil {
                    warn("Unsupported SVG text attribute '\(key)'", node)
                }
            }
            let size: Double = if let value = style["font-size"] {
                if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
                    parentSize * percent / 100
                } else if value.hasSuffix("em"), let factor = Double(value.dropLast(2)) {
                    parentSize * factor
                } else {
                    try Self.length(value, line: node.line)
                }
            } else { parentSize }
            guard size.isFinite, size >= 0 else {
                throw SVGImportError(message: "Invalid SVG font size", line: node.line)
            }
            // Resolve relative sizes once before passing the computed style to children.
            style["font-size"] = String(size)
            let families = (style["font-family"] ?? "serif").split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
            }
            var font = CTFontCreateWithName("Times" as CFString, max(size, 0.001), nil)
            var matchedFont = false
            for family in families {
                let name = ["serif": "Times", "sans-serif": "Helvetica", "monospace": "Courier"][family] ?? family
                let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontNameAttribute: name] as CFDictionary)
                if let match = CTFontDescriptorCreateMatchingFontDescriptor(
                    descriptor, [kCTFontNameAttribute as String] as Set as CFSet
                ) {
                    font = CTFontCreateWithFontDescriptor(match, max(size, 0.001), nil)
                    matchedFont = true
                    break
                }
            }
            if !matchedFont {
                warn("Unknown SVG font '\(families.joined(separator: ", "))'", node)
            }
            var traits: CTFontSymbolicTraits = []
            if style["font-weight"] == "bold" || (Double(style["font-weight"] ?? "") ?? 400) >= 600 {
                traits.insert(.traitBold)
            }
            if ["italic", "oblique"].contains(style["font-style"] ?? "") { traits.insert(.traitItalic) }
            font = CTFontCreateCopyWithSymbolicTraits(
                font,
                max(size, 0.001),
                nil,
                traits,
                [.traitBold, .traitItalic]
            ) ?? font
            var attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
            ]
            if let spacing = style["letter-spacing"], spacing != "normal" {
                attributes[NSAttributedString.Key(kCTKernAttributeName as String)] = try Self.length(
                    spacing,
                    line: node.line
                )
            }
            for item in node.content {
                switch item {
                case let .text(value):
                    var value = value.replacingOccurrences(of: "\t", with: " ")
                        .replacingOccurrences(of: "\n", with: style["xml:space"] == "preserve" ? " " : "")
                        .replacingOccurrences(of: "\r", with: style["xml:space"] == "preserve" ? " " : "")
                    if style["xml:space"] != "preserve" {
                        value = String(value.filter { character in
                            let space = character == " "
                            defer { previousWasSpace = space }
                            return !space || !previousWasSpace
                        })
                    } else if let last = value.last { previousWasSpace = last == " " }
                    for scalar in value.unicodeScalars {
                        if isCancelled() { throw CancellationError() }
                        let absoluteX = position("x"), absoluteY = position("y")
                        let dx = position("dx"), dy = position("dy")
                        let angle = position("rotate") ?? 0
                        if absoluteX != nil || absoluteY != nil {
                            flushChunk()
                            if let absoluteX { x = absoluteX }
                            if let absoluteY { y = absoluteY }
                            x += dx ?? 0
                            y += dy ?? 0
                            chunkStart = x
                            anchor = style["text-anchor"] ?? "start"
                        } else if dx != nil || dy != nil || angle != 0 || rotation != 0 {
                            // Keep unpositioned text in one shaped run. Explicit character
                            // adjustments and rotations require a new glyph origin.
                            flushRun()
                            x += dx ?? 0
                            y += dy ?? 0
                        }
                        rotation = angle
                        if size > 0 {
                            text.append(NSAttributedString(string: String(scalar), attributes: attributes))
                            preserveSpace = style["xml:space"] == "preserve"
                        }
                        // Ancestor lists count descendant characters too.
                        // Child values override only the corresponding entries in those lists
                        for index in positions.indices {
                            positions[index].index += 1
                        }
                    }
                case let .element(child):
                    guard child.name == "tspan" else {
                        warn("Unsupported SVG text element '\(child.name)'", child)
                        continue
                    }
                    if child.attributes["transform"] != nil {
                        warn("SVG tspan transforms are not supported", child)
                    }
                    try append(child, style: style, size: size)
                }
            }
        }
        try append(self, style: style, size: 16)
        flushChunk()
        return paths
    }
}
#endif

private final class SVGXMLDelegate: NSObject, XMLParserDelegate {
    let isCancelled: CancellationHandler
    var root: SVGElement?
    var error: SVGImportError?
    var elementsByID = [String: SVGElement]()
    private var stack = [SVGElement]()

    init(isCancelled: @escaping CancellationHandler) {
        self.isCancelled = isCancelled
    }

    func parser(
        _ parser: XMLParser,
        didStartElement name: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        guard !isCancelled() else { return parser.abortParsing() }
        guard stack.count < 256 else {
            error = SVGImportError(message: "SVG nesting is too deep", line: parser.lineNumber)
            parser.abortParsing()
            return
        }
        let node = SVGElement(name: name, attributes: attributes, line: parser.lineNumber)
        if let parent = stack.last {
            node.parent = parent
            parent.children.append(node)
            parent.content.append(.element(node))
        } else { root = node }
        if let id = attributes["id"] { elementsByID[id] = node }
        stack.append(node)
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard let node = stack.last else { return }
        if case let .text(previous)? = node.content.last {
            node.content[node.content.count - 1] = .text(previous + string)
        } else {
            node.content.append(.text(string))
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let string = String(data: CDATABlock, encoding: .utf8) {
            self.parser(parser, foundCharacters: string)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        // Keep the original diagnostic: parserError may later become a generic "parsing stopped" error.
        if error == nil { error = SVGImportError(parser: parser, error: parseError) }
    }

    func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
        stack.removeLast()
    }
}

/// SVG matrices include skew, so cannot in general be represented by Euclid.Transform.
private struct SVGMatrix {
    var a = 1.0, b = 0.0, c = 0.0, d = 1.0, e = 0.0, f = 0.0
    static let identity = Self()
    static func translation(_ x: Double, _ y: Double) -> Self { .init(e: x, f: y) }
    func apply(_ p: Vector) -> Vector { [a * p.x + c * p.y + e, b * p.x + d * p.y + f, p.z] }
    static func * (l: Self, r: Self) -> Self {
        .init(
            a: l.a * r.a + l.c * r.b,
            b: l.b * r.a + l.d * r.b,
            c: l.a * r.c + l.c * r.d,
            d: l.b * r.c + l.d * r.d,
            e: l.a * r.e + l.c * r.f + l.e,
            f: l.b * r.e + l.d * r.f + l.f
        )
    }

    static func parse(_ text: String, line: Int) throws -> Self {
        var result = Self.identity
        var remaining = text[...]
        while !remaining.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ","))).isEmpty {
            guard let open = remaining.firstIndex(of: "("), let close = remaining.firstIndex(of: ")"),
                  open < close
            else {
                throw SVGImportError(message: "Invalid SVG transform", line: line)
            }
            let name = remaining[..<open]
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ",")))
            let n = try svgNumbers(String(remaining[remaining.index(after: open) ..< close]), line: line)
            let matrix: Self
            switch (name, n.count) {
            case ("matrix", 6): matrix = .init(a: n[0], b: n[1], c: n[2], d: n[3], e: n[4], f: n[5])
            case ("translate", 1), ("translate", 2): matrix = .translation(n[0], n.count == 2 ? n[1] : 0)
            case ("scale", 1), ("scale", 2): matrix = .init(a: n[0], d: n.count == 2 ? n[1] : n[0])
            case ("rotate", 1), ("rotate", 3):
                let r = n[0] * .pi / 180
                let rotation = Self(a: cos(r), b: sin(r), c: -sin(r), d: cos(r))
                matrix = n.count == 3 ? .translation(n[1], n[2]) * rotation * .translation(-n[1], -n[2]) : rotation
            case ("skewX", 1): matrix = .init(c: tan(n[0] * .pi / 180))
            case ("skewY", 1): matrix = .init(b: tan(n[0] * .pi / 180))
            default: throw SVGImportError(message: "Invalid SVG transform '\(name)'", line: line)
            }
            result = result * matrix
            remaining = remaining[remaining.index(after: close)...]
        }
        return result
    }
}

private func svgNumbers(_ text: String, line: Int) throws -> [Double] {
    let scanner = Scanner(string: text)
    scanner.charactersToBeSkipped = .whitespacesAndNewlines.union(.init(charactersIn: ","))
    scanner.locale = Locale(identifier: "en_US_POSIX")
    var numbers = [Double]()
    while !scanner.isAtEnd {
        guard let number = scanner.scanDouble(), number.isFinite else {
            throw SVGImportError(message: "Invalid SVG number list", line: line)
        }
        numbers.append(number)
    }
    return numbers
}

private func svgStroke(
    _ path: Path,
    width: Double,
    cap: String,
    join: String,
    detail: Int,
    isCancelled: CancellationHandler
) throws -> Path {
    let points = path.points.map(\.position)
    guard points.count > 1 else { return .empty }
    let radius = width / 2
    var pieces = [Path]()
    var directions = [Vector]()
    for (a, b) in zip(points, points.dropFirst()) {
        if isCancelled() { throw CancellationError() }
        let delta = b - a
        guard delta.length > 0 else { continue }
        let direction = delta / delta.length
        directions.append(direction)
        let normal = Vector(-direction.y, direction.x) * radius
        let start = cap == "square" && a == points.first ? a - direction * radius : a
        let end = cap == "square" && b == points.last ? b + direction * radius : b
        pieces.append(Path([start + normal, end + normal, end - normal, start - normal].map { PathPoint($0) }).closed())
    }
    if cap == "round" {
        for p in [points[0], points[points.count - 1]] {
            pieces.append(.circle(radius: radius, segments: max(8, detail)).translated(by: p))
        }
    }
    if directions.count == points.count - 1, points.count > 2 {
        for i in 1 ..< points.count - 1 {
            let p = points[i], a = directions[i - 1], b = directions[i]
            if join == "round" {
                pieces.append(.circle(radius: radius, segments: max(8, detail)).translated(by: p))
                continue
            }
            let cross = a.x * b.y - a.y * b.x
            if abs(cross) < 1e-10 { continue }
            let signedRadius = cross > 0 ? -radius : radius
            let n1 = Vector(-a.y, a.x).scaled(by: signedRadius)
            let n2 = Vector(-b.y, b.x).scaled(by: signedRadius)
            let q1 = p + n1, q2 = p + n2
            let delta = q2 - q1
            let tip = q1 + a * ((delta.x * b.y - delta.y * b.x) / cross)
            var corner = [p, q1]
            if join == "miter", (tip - p).length <= radius * 2 { corner.append(tip) }
            corner.append(q2)
            pieces.append(Path(corner.map { PathPoint($0) }).closed())
        }
    }
    return Path.union(pieces, isCancelled: isCancelled) ?? .empty
}

/// A fragment belongs to the SVG selection, not the filesystem path.
struct SVGFileReference {
    let path: String
    let id: String?

    init(_ path: String) {
        if let hash = path.firstIndex(of: "#"), path[..<hash].lowercased().hasSuffix(".svg") {
            self.path = String(path[..<hash])
            let fragment = String(path[path.index(after: hash)...])
            self.id = fragment.isEmpty ? nil : fragment.removingPercentEncoding ?? fragment
        } else {
            self.path = path
            self.id = nil
        }
    }
}
