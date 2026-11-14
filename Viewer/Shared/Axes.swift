//
//  Axes.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 23/08/2021.
//  Copyright © 2021 Nick Lockwood. All rights reserved.
//

import Euclid
import SceneKit
import ShapeScript
import RealityKit

struct Axes {
    let geometry: Geometry

    init(
        scale: Double,
        camera: Camera,
        color: Color
    ) {
        let textScale = 0.1
        let distance = 1 + textScale
        let material = Material(color: color)
        self.geometry = Geometry(transform: .scale(scale), material: material, children: [
            Geometry(type: .path(.line(-.unitX, .unitX)), material: material),
            Geometry(
                label: "+X",
                offset: .unitX * distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
            Geometry(
                label: "-X",
                offset: .unitX * -distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
            Geometry(type: .path(.line(-.unitY, .unitY)), material: material),
            Geometry(
                label: "+Y",
                offset: .unitY * distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
            Geometry(
                label: "-Y",
                offset: .unitY * -distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
            Geometry(type: .path(.line(-.unitZ, .unitZ)), material: material),
            Geometry(
                label: "+Z",
                offset: .unitZ * distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
            Geometry(
                label: "-Z",
                offset: .unitZ * -distance,
                rotation: camera.orientation,
                scale: textScale,
                material: material
            ),
        ])
        _ = geometry.build { false }
    }
}

extension SCNNode {
    convenience init(_ axes: Axes) {
        var options = Scene.OutputOptions.default
        options.lineColor = axes.geometry.material.color ?? options.lineColor
        axes.geometry.scnBuild(with: options)
        self.init(axes.geometry)
        enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] {
                material.lightingModel = .constant
            }
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
extension Entity {
    convenience init(_ axes: Axes, lineWidth: Double) throws {
        self.init()
        let scale = axes.geometry.transform.scale.x
        var options = Scene.OutputOptions.default
        // Path strokes are built in local coordinates, then scaled with the axes.
        options.lineWidth = scale > 0 ? lineWidth / scale : 0
        let scene = Scene(
            background: .color(.clear),
            children: [axes.geometry],
            cache: nil
        )
        for reference in try scene.realityKitEntityReferences(with: options) {
            if var model = reference.entity.components[ModelComponent.self] {
                model.materials = model.materials.map { material in
                    guard let material = material as? PhysicallyBasedMaterial else { return material }
                    var unlit = UnlitMaterial(color: material.baseColor.tint)
                    switch material.blending {
                    case .opaque: break
                    case let .transparent(opacity): unlit.blending = .transparent(opacity: opacity)
                    @unknown default: break
                    }
                    return unlit
                }
                reference.entity.components.set(model)
            }
            addChild(reference.entity)
        }
    }
}

private extension Geometry {
    convenience init(
        type: GeometryType = .group,
        transform: Euclid.Transform = .identity,
        material: ShapeScript.Material = .default,
        smoothing: Angle? = nil,
        children: [Geometry] = []
    ) {
        self.init(
            type: type,
            name: nil,
            transform: transform,
            material: material,
            smoothing: smoothing,
            children: children,
            sourceLocation: nil
        )
    }

    convenience init(
        label: String,
        offset: Vector,
        rotation: Rotation,
        scale: Double,
        material: ShapeScript.Material
    ) {
        let paths = Path.text(label)
        self.init(type: .fill(paths), transform: Transform(
            scale: Vector(size: [scale]),
            rotation: rotation,
            translation: offset - Bounds(paths).size.rotated(by: rotation) * (scale / 2)
        ), material: material)
    }
}
