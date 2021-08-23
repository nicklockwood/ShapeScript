//
//  Axis.swift
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

    init(scale: Double, background: MaterialProperty?) {
        let textScale = 0.1
        let color = Color(.underPageBackgroundColor)
        let brightness = background?.brightness(over: color) ?? color.brightness
        let lineColor = brightness > 0.5 ? Color.black : .white
        var material = Material.default
        material.color = lineColor
        geometry = Geometry(transform: Transform(scale: Vector(size: [scale])), children: [
            Geometry(type: .path(.line(-.x, .x))),
            Geometry(type: .fill(Path.text("+X")), transform: Transform(
                offset: .x - Vector(-0.5, 0.25, 0) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
            Geometry(type: .fill(Path.text("-X")), transform: Transform(
                offset: -.x - Vector(1.5, 0.25, 0) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
            Geometry(type: .path(.line(-.y, .y))),
            Geometry(type: .fill(Path.text("+Y")), transform: Transform(
                offset: .y - Vector(0.6, -0.5, 0) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
            Geometry(type: .fill(Path.text("-Y")), transform: Transform(
                offset: -.y - Vector(0.5, 1.25, 0) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
            Geometry(type: .path(.line(-.z, .z))),
            Geometry(type: .fill(Path.text("+Z")), transform: Transform(
                offset: .z - Vector(0.6, 0.25, -0.5) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
            Geometry(type: .fill(Path.text("-Z")), transform: Transform(
                offset: -.z - Vector(0.5, 0.25, 0.5) * textScale,
                scale: Vector(size: [textScale])
            ), material: material),
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

private extension Vector {
    static let x = Vector(1, 0, 0)
    static let y = Vector(0, 1, 0)
    static let z = Vector(0, 0, 1)
}

private extension Geometry {
    convenience init(
        type: GeometryType = .group,
        transform: Transform = .identity,
        material: Material = .default,
        children: [Geometry] = []
    ) {
        self.init(
            type: type,
            name: nil,
            transform: transform,
            material: material,
            children: children,
            sourceLocation: nil
        )
    }
}
