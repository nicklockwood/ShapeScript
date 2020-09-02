//
//  Scene+SceneKit.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 27/09/2018.
//  Copyright © 2018 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit

public extension SCNMaterial {
    convenience init(_ m: Material, isOpaque: Bool) {
        self.init()
        if let texture = m.texture {
            switch texture {
            case let .file(_, url):
                diffuse.contents = url
            case let .data(data):
                diffuse.contents = data
            }
        } else if let color = m.color {
            diffuse.contents = NSColor(
                red: CGFloat(color.r),
                green: CGFloat(color.g),
                blue: CGFloat(color.b),
                alpha: CGFloat(color.a)
            )
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
        if geometry.transform.isFlipped, let mesh = geometry.mesh {
            // TODO: less hacky solution than regenerating geometry at render time
            // possibly something like flipping SCNMaterial.cullMode ?
            // TODO: this doesn't take cumulative transform into account, so it won't
            // work correctly if the parent node is flipped
            let mesh = mesh.scaleCorrected(for: geometry.transform.scale)
            self.init(geometry: SCNGeometry(mesh: mesh, for: geometry))
        } else {
            self.init(geometry: geometry.scnGeometry)
        }
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

        //        scnNode.geometry?.firstMaterial?.isDoubleSided = true
        if geometry.renderChildren {
            for child in geometry.children {
                addChildNode(SCNNode(child))
            }
        }
    }

    convenience init(merged geometry: Geometry) {
        let mesh = geometry.merged()
        self.init(geometry: SCNGeometry(mesh: mesh, for: geometry))
    }
}

public extension Geometry {
    var scnGeometry: SCNGeometry {
        return associatedData as? SCNGeometry ?? SCNGeometry()
    }

    func scnBuild() {
        // SCNGeometry should never be constructed on the main thread
        // TODO: should we guarantee this for paths also?
        assert(!Thread.isMainThread)

        if renderChildren {
            children.forEach { $0.scnBuild() }
        }

        if associatedData != nil {
            return
        } else if let path = self.path {
            associatedData = SCNGeometry(path)
        } else if let mesh = self.mesh {
            associatedData = SCNGeometry(mesh: mesh, for: self)
        }
    }

    func select(with scnGeometry: SCNGeometry?) -> Geometry? {
        isSelected = (self.scnGeometry == scnGeometry)
        for material in self.scnGeometry.materials {
            material.emission.contents = isSelected ? NSColor.red : .black
            material.multiply.contents = isSelected ? NSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1) : .white
        }
        var selected = isSelected ? self : nil
        for child in children {
            let g = child.select(with: scnGeometry)
            selected = selected ?? g
        }
        return selected
    }
}

// MARK: import

public extension Color {
    init(cgColor: CGColor) {
        let components = cgColor.components ?? [1]
        self.init(unchecked: components.map(Double.init))
    }

    init(nsColor: NSColor) {
        self.init(cgColor: nsColor.cgColor)
    }
}

public extension Material {
    init?(scnMaterial: SCNMaterial) {
        opacity = Double(scnMaterial.transparency)
        color = (scnMaterial.diffuse.contents as? NSColor).map(Color.init(nsColor:)) ?? .white
        switch scnMaterial.diffuse.contents {
        case let data as Data:
            texture = .data(data)
        case let url as URL:
            texture = .file(name: url.lastPathComponent, url: url)
        default:
            texture = nil
        }
    }
}

public extension Geometry {
    convenience init(scnNode: SCNNode) {
        var type = GeometryType.none
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
