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

#if canImport(AppKit)
public typealias OSColor = NSColor
#else
public typealias OSColor = UIColor
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
    convenience init(mesh: Mesh, for geometry: Geometry) {
        self.init(mesh, materialLookup: {
            SCNMaterial($0 as? Material ?? geometry.material, isOpaque: geometry.isOpaque)
        })
    }
}

public extension SCNNode {
    convenience init(_ geometry: Geometry) {
        self.init(geometry: geometry.scnGeometry)
        setTransform(geometry.transform)
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

        if geometry.renderChildren || geometry.childDebug {
            geometry.children.forEach { addChildNode(SCNNode($0)) }
        }
    }

    convenience init(merged geometry: Geometry) {
        let mesh = geometry.merged()
        self.init(geometry: SCNGeometry(mesh: mesh, for: geometry))
    }
}

private extension Geometry {
    typealias SCNData = (
        options: Scene.OutputOptions,
        geometry: SCNGeometry,
        wireframe: SCNGeometry?
    )

    var scnData: SCNData? {
        get { associatedData as? SCNData }
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
        options.lineWidth = min(0.05, 0.002 * max(size.x, size.y, size.z))
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

public extension Geometry {
    var scnGeometry: SCNGeometry {
        scnData?.geometry ?? SCNGeometry()
    }

    func scnBuild(with options: Scene.OutputOptions) {
        if renderChildren || childDebug {
            children.scnBuild(with: options, debug: !renderChildren)
        }

        if let scnData = scnData, scnData.options == options {
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
                    let opposite = tan(light.spread / 2) * adjacent
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
                scnData = (options: options, geometry: geometry, wireframe: nil)
            }
        } else if let path = path {
            if options.wireframe {
                let wireframe = scnData?.wireframe ?? SCNGeometry(.stroke(
                    path.removingColors(),
                    width: options.lineWidth,
                    detail: 5
                ))

                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = OSColor(options.lineColor)
                wireframe.materials = [material]

                scnData = (
                    options: options,
                    geometry: wireframe,
                    wireframe: wireframe
                )
            } else {
                let geometry: SCNGeometry
                if debug, let material = options.debugMaterial {
                    geometry = scnData?.wireframe ?? SCNGeometry(.stroke(
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

                scnData = (
                    options: options,
                    geometry: geometry,
                    wireframe: scnData?.wireframe
                )
            }
        } else if let mesh = mesh {
            if options.wireframe {
                let wireframe = scnData?.wireframe ?? (
                    options.wireframeLineWidth > 0 ? SCNGeometry(.stroke(
                        mesh.uniqueEdges,
                        width: options.wireframeLineWidth,
                        detail: 3
                    )) : SCNGeometry(wireframe: mesh)
                )

                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = OSColor(options.lineColor)
                wireframe.materials = [material]

                scnData = (
                    options: options,
                    geometry: wireframe,
                    wireframe: wireframe
                )
            } else {
                var geometry: SCNGeometry
                if debug, let material = options.debugMaterial {
                    let m = SCNMaterial(material, isOpaque: false)
                    geometry = SCNGeometry(mesh.scaled(by: 1.001)) { _ in m }
                } else {
                    geometry = SCNGeometry(mesh: mesh, for: self)
                }
                scnData = (
                    options: options,
                    geometry: geometry,
                    wireframe: scnData?.wireframe
                )
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

// MARK: import

public extension MaterialProperty {
    init?(scnMaterialProperty: SCNMaterialProperty) {
        switch scnMaterialProperty.contents {
        case let color as OSColor:
            self = .color(Color(color))
        case let data as Data:
            self = .texture(.data(data))
        case let url as URL:
            self = .texture(.file(name: url.lastPathComponent, url: url))
        default:
            return nil
        }
    }
}

public extension Material {
    init?(scnMaterial: SCNMaterial) {
        opacity = Double(scnMaterial.transparency)
        switch MaterialProperty(scnMaterialProperty: scnMaterial.diffuse) {
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
}

public extension Geometry {
    convenience init(scnNode: SCNNode) throws {
        let type: GeometryType
        if let scnGeometry = scnNode.geometry {
            guard let mesh = Mesh(
                scnGeometry,
                materialLookup: Material.init(scnMaterial:)
            ) else {
                throw ImportError.unknownError
            }
            type = .mesh(mesh)
        } else {
            type = .group
        }
        self.init(
            type: type,
            name: scnNode.name,
            transform: .transform(from: scnNode),
            material: .default,
            smoothing: nil,
            children: try scnNode.childNodes.map(Geometry.init(scnNode:)),
            sourceLocation: nil
        )
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

#endif
