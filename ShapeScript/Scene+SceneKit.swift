//
//  Scene+SceneKit.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid

#if canImport(SceneKit)

import SceneKit

#if canImport(UIKit)
typealias OSColor = UIColor
typealias OSImage = UIImage
#else
typealias OSColor = NSColor
typealias OSImage = NSImage
#endif

public extension MaterialProperty {
    func configureProperty(_ property: SCNMaterialProperty) {
        switch self {
        case let .color(color):
            property.contents = OSColor(color)
        case let .texture(texture):
            switch texture {
            case let .file(_, url):
                property.contents = url
            case let .data(data):
                property.contents = data
            }
        }
    }
}

public extension SCNMaterial {
    convenience init(_ m: Material, isOpaque: Bool) {
        self.init()
        if let texture = m.texture {
            MaterialProperty.texture(texture).configureProperty(diffuse)
        } else if let color = m.color {
            MaterialProperty.color(color).configureProperty(diffuse)
        }
        transparency = CGFloat(m.opacity)

        isDoubleSided = !isOpaque
        transparencyMode = isOpaque ? .default : .dualLayer
    }
}

private extension SCNGeometry {
    convenience init(_ mesh: Mesh, for geometry: Geometry) {
        self.init(mesh, materialLookup: {
            SCNMaterial($0 as? Material ?? geometry.material, isOpaque: geometry.isOpaque)
        })
    }
}

public extension SCNNode {
    convenience init(_ geometry: Geometry) {
        self.init(geometry: geometry.scnGeometry)
        setTransform(geometry.transform)
        geometry.scnNode = self
        name = geometry.name

        if let light = geometry.light {
            self.light = SCNLight(light)
        }

        // debug wireframe
//        geometry.mesh.map { self.addChildNode(SCNNode(
//            geometry: SCNGeometry(wireframe: $0)
//        )) }

        // debug normals
//        geometry.mesh.map { self.addChildNode(SCNNode(
//            geometry: SCNGeometry(normals: $0, scale: 0.1)
//        )) }

        // debug bounds
//        self.addChildNode(SCNNode(
//            geometry: SCNGeometry(bounds: geometry.bounds)
//        ))

        // debug holes
//        geometry.mesh.map { self.addChildNode(SCNNode(
//            geometry: SCNGeometry($0.polygons.holeEdges)
//        )) }

        if geometry.renderChildren || geometry.childDebug {
            geometry.children.forEach { addChildNode(SCNNode($0)) }
        }
    }

    convenience init(merged geometry: Geometry) {
        let mesh = geometry.merged()
        self.init(geometry: SCNGeometry(mesh, for: geometry))
    }
}

private struct DataKey: Hashable {
    var debug: Bool
    var options: Scene.OutputOptions
}

private extension Geometry {
    var scnData: [DataKey: SCNGeometry] {
        get { associatedData as? [DataKey: SCNGeometry] ?? [:] }
        set { associatedData = newValue }
    }
}

public extension Scene {
    struct OutputOptions: Hashable {
        public static let `default` = OutputOptions()

        /// Line width to use for path drawing
        public var lineWidth: Double = 0.005

        /// Color to use for line or wireframe drawing
        public var lineColor: Color = .black

        /// Material to use for debug geometry
        public var debugMaterial: Material? = Material(
            color: Color.green.withAlpha(0.5)
        )

        /// Should mesh be drawn using wireframe
        public var wireframe: Bool = false

        /// Line width to use for wireframe drawing
        /// The default value of zero uses native line drawing
        public var wireframeLineWidth: Double = 0
    }

    func outputOptions(
        for camera: Camera?,
        backgroundColor: Color?,
        wireframe: Bool
    ) -> OutputOptions {
        var options = OutputOptions.default
        let color = backgroundColor ?? .gray
        let size = bounds.size
        options.lineWidth = max(0.005, 0.002 * max(size.x, size.y, size.z))
        let background = camera?.background ?? self.background
        options.lineColor = background.brightness(over: color) > 0.5 ? .black : .white
        options.wireframe = wireframe
        #if arch(x86_64)
        // Use stroke on x86 as line rendering looks bad
        options.wireframeLineWidth = options.lineWidth / 2
        #endif
        return options
    }

    func scnBuild(with options: OutputOptions) {
        children.scnBuild(with: options, debug: false)
    }
}

private var scnNodeKey: UInt8 = 1
private var scnGeometryKey: UInt8 = 1

public extension Geometry {
    fileprivate(set) var scnNode: SCNNode? {
        get { objc_getAssociatedObject(self, &scnNodeKey) as? SCNNode }
        set {
            objc_setAssociatedObject(
                self,
                &scnNodeKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    fileprivate(set) var scnGeometry: SCNGeometry {
        get {
            objc_getAssociatedObject(
                self,
                &scnGeometryKey
            ) as? SCNGeometry ?? SCNGeometry()
        }
        set {
            objc_setAssociatedObject(
                self,
                &scnGeometryKey,
                newValue,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }

    func scnBuild(with options: Scene.OutputOptions) {
        if renderChildren || childDebug {
            children.scnBuild(with: options, debug: !renderChildren)
        }

        let key = DataKey(debug: debug, options: options)
        if let scnGeometry = scnData[key] {
            self.scnGeometry = scnGeometry
            return
        } else if let light = light {
            if debug, let material = options.debugMaterial, !options.wireframe {
                let mesh: Mesh
                switch (light.hasPosition, light.hasOrientation) {
                case (false, _):
                    return
                case (true, false):
                    mesh = .sphere(radius: 0.1)
                case (true, true):
                    let adjacent = 10000.0
                    let opposite = tan(min(light.spread, .pi * 0.999) / 2) * adjacent
                    mesh = Mesh.lathe(Path([
                        .point(0, 0, 0),
                        .point(0, -opposite, adjacent),
                        .point(0, 0, adjacent),
                    ]), slices: 64).rotated(by: transform.rotation)
                }
                let geometry = SCNGeometry(mesh)
                let material = SCNMaterial(material, isOpaque: false)
                material.lightingModel = .constant
                geometry.materials = [material]
                scnData[key] = geometry
                scnGeometry = geometry
            }
        } else if let path = path {
            if options.wireframe {
                let wireframe = SCNGeometry(.stroke(
                    path.removingColors(),
                    width: options.lineWidth,
                    detail: 5
                ))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = OSColor(options.lineColor)
                wireframe.materials = [material]
                scnData[key] = wireframe
                scnGeometry = wireframe
            } else {
                let geometry: SCNGeometry
                if debug, let material = options.debugMaterial {
                    geometry = SCNGeometry(.stroke(
                        path.removingColors(),
                        width: options.lineWidth,
                        detail: 5
                    ))
                    geometry.materials = [SCNMaterial(material, isOpaque: false)]
                } else {
                    geometry = SCNGeometry(.stroke(
                        path,
                        width: options.lineWidth,
                        detail: 5
                    ))
                    let lineColor = path.hasColors ?
                        Color.white : self.material.color ?? options.lineColor
                    let material = SCNMaterial()
                    material.lightingModel = .constant
                    material.diffuse.contents = OSColor(lineColor)
                    geometry.materials = [material]
                }
                scnData[key] = geometry
                scnGeometry = geometry
            }
        } else if let mesh = mesh {
            if options.wireframe {
                let wireframe = options.wireframeLineWidth > 0 ? SCNGeometry(.stroke(
                    mesh.uniqueEdges,
                    width: options.wireframeLineWidth,
                    detail: 3
                )) : SCNGeometry(wireframe: mesh)
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = OSColor(options.lineColor)
                wireframe.materials = [material]
                scnData[key] = wireframe
                scnGeometry = wireframe
            } else {
                var geometry: SCNGeometry
                if debug, let material = options.debugMaterial {
                    let m = SCNMaterial(material, isOpaque: false)
                    geometry = SCNGeometry(mesh.scaled(by: 1.001)) { _ in m }
                } else {
                    geometry = SCNGeometry(mesh, for: self)
                }
                scnData[key] = geometry
                scnGeometry = geometry
            }
        }
    }
}

private extension Array where Element == Geometry {
    func scnBuild(with options: Scene.OutputOptions, debug: Bool) {
        for child in self {
            if debug, !child.debug {
                child.children.scnBuild(with: options, debug: true)
            } else {
                child.scnBuild(with: options)
            }
        }
    }
}

public extension MaterialProperty {
    init?(_ scnMaterialProperty: SCNMaterialProperty) {
        switch scnMaterialProperty.contents {
        case let color as OSColor:
            self = .color(Color(color))
        case let image as OSImage:
            guard let texture = Texture(image) else {
                return nil
            }
            self = .texture(texture)
        case let data as Data:
            self = .texture(.data(data))
        case let url as URL:
            self = .texture(.file(name: url.lastPathComponent, url: url))
        default:
            return nil
        }
    }

    @available(*, renamed: "init(_:)")
    init?(scnMaterialProperty: SCNMaterialProperty) {
        self.init(scnMaterialProperty)
    }
}

public extension Material {
    init?(_ scnMaterial: SCNMaterial) {
        opacity = Double(scnMaterial.transparency)
        switch MaterialProperty(scnMaterial.diffuse) {
        case let .color(color)?:
            self.color = color
            texture = nil
        case let .texture(texture)?:
            color = .white
            self.texture = texture
        default:
            color = .white
            texture = nil
        }
    }

    @available(*, renamed: "init(_:)")
    init?(scnMaterial: SCNMaterial) {
        self.init(scnMaterial)
    }
}

public extension Geometry {
    convenience init(_ scnNode: SCNNode) throws {
        let type: GeometryType
        var transform = Transform.transform(from: scnNode)
        if let scnCamera = scnNode.camera {
            let isOrtho = scnCamera.usesOrthographicProjection
            if isOrtho {
                transform.scale *= scnCamera.orthographicScale
            }
            type = .camera(Camera(
                position: transform.offset,
                orientation: transform.rotation,
                scale: isOrtho ? transform.scale : nil,
                background: nil,
                fov: .degrees(isOrtho ? 0 : Double(scnCamera.fieldOfView)),
                width: nil,
                height: nil
            ))
        } else if let scnGeometry = scnNode.geometry {
            guard let mesh = Mesh(
                scnGeometry,
                materialLookup: Material.init(_:)
            ) else {
                throw ProgramError.unknownError
            }
            type = .mesh(mesh)
        } else {
            type = .group
        }
        self.init(
            type: type,
            name: scnNode.name,
            transform: transform,
            material: .default,
            smoothing: nil,
            children: try scnNode.childNodes.map(Geometry.init(_:)),
            sourceLocation: nil
        )
    }

    @available(*, renamed: "init(_:)")
    convenience init(scnNode: SCNNode) throws {
        try self.init(scnNode)
    }
}

public extension SCNLight {
    convenience init(_ light: Light) {
        self.init()
        switch (light.hasPosition, light.hasOrientation) {
        case (false, false):
            type = .ambient
        case (false, true):
            type = .directional
        case (true, false):
            type = .omni
        case (true, true):
            type = .spot
        }
        color = OSColor(light.color)
        intensity = CGFloat(light.color.a * 1000)
        spotOuterAngle = CGFloat(light.spread.degrees)
        spotInnerAngle = CGFloat(1 - max(0, min(1, light.penumbra))) * spotOuterAngle
    }
}

extension Texture {
    init?(_ image: OSImage) {
        #if canImport(UIKit)
        guard let data = image.pngData() else {
            return nil
        }
        #else
        guard let cgImage = image
            .cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .png, properties: [:])
        else {
            return nil
        }
        #endif
        self = .data(data)
    }
}

extension OSImage {
    convenience init?(_ texture: Texture) {
        switch texture {
        case let .data(data):
            self.init(data: data)
        case let .file(name: _, url: url):
            self.init(contentsOfFile: url.path)
        }
    }
}

#endif
