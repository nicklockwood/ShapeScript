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

        for child in geometry.children {
            addChildNode(SCNNode(child))
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

        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = OSColor(options.lineColor)

        if let scnData = scnData, scnData.options == options {
            return
        } else if let path = path {
            let wireframe = SCNGeometry(.stroke(
                path,
                width: options.lineWidth,
                detail: 5
            ))
            wireframe.materials = [material]
            scnData = (
                options: options,
                geometry: wireframe,
                wireframe: wireframe
            )
        } else if let mesh = mesh {
            if options.wireframe {
                let wireframe = scnData?.wireframe ?? (
                    options.wireframeLineWidth > 0 ? SCNGeometry(.stroke(
                        mesh.uniqueEdges,
                        width: options.wireframeLineWidth,
                        detail: 3
                    )) : SCNGeometry(wireframe: mesh)
                )
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
    convenience init(scnNode: SCNNode) {
        var type = GeometryType.group
        if let scnGeometry = scnNode.geometry, let mesh = Mesh(
            scnGeometry, materialLookup: Material.init(scnMaterial:)
        ) {
            type = .mesh(mesh)
        }
        self.init(
            type: type,
            name: scnNode.name,
            transform: .transform(from: scnNode),
            material: .default,
            children: scnNode.childNodes.map(Geometry.init(scnNode:)),
            sourceLocation: nil
        )
    }
}

#endif
