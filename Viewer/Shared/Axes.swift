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

struct Axes {
    let geometry: Geometry

    init(
        scale: Double,
        camera: Camera,
        background: MaterialProperty?,
        backgroundColor: Color?
    ) {
        let textScale = 0.1
        let distance = 1 + textScale
        let color = backgroundColor ?? .gray
        let background = camera.background ?? background
        let brightness = background?.brightness(over: color) ?? color.brightness
        let lineColor = brightness > 0.5 ? Color.black : .white
        let material = Material(color: lineColor)
        self.geometry = Geometry(transform: .scale(scale), children: [
            Geometry(type: .path(.line(-.unitX, .unitX, color: lineColor))),
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
            Geometry(type: .path(.line(-.unitY, .unitY, color: lineColor))),
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
            Geometry(type: .path(.line(-.unitZ, .unitZ, color: lineColor))),
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
        _ = geometry.build { true }
        var options = Scene.OutputOptions.default
        options.lineColor = lineColor
        geometry.scnBuild(with: options)
    }
}

extension SCNNode {
    convenience init(_ axes: Axes) {
        self.init(axes.geometry)
    }
}

private extension Geometry {
    convenience init(
        type: GeometryType = .group,
        transform: Transform = .identity,
        material: Material = .default,
        smoothing: Angle? = nil,
        wrapMode: WrapMode? = nil,
        children: [Geometry] = []
    ) {
        self.init(
            type: type,
            name: nil,
            transform: transform,
            material: material,
            smoothing: smoothing,
            wrapMode: wrapMode,
            children: children,
            sourceLocation: nil
        )
    }

    convenience init(
        label: String,
        offset: Vector,
        rotation: Rotation,
        scale: Double,
        material: Material
    ) {
        let paths = Path.text(label)
        self.init(type: .fill(paths), transform: Transform(
            offset: offset - paths.bounds.size.rotated(by: rotation) * (scale / 2),
            rotation: rotation,
            scale: Vector(size: [scale])
        ), material: material)
    }
}
