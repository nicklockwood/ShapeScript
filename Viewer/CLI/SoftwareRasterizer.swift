//
//  SoftwareRasterizer.swift
//  CLI
//
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import ShapeScript

struct SoftwareImage {
    let pixels: [Color]
    let width: Int
    let height: Int
}

extension ShapeScript.Camera {
    var pixelSize: (width: Int, height: Int) {
        get throws {
            guard let width, let height, width > 0, height > 0 else {
                throw CLIError("Invalid software image dimensions")
            }
            return (width, height)
        }
    }
}

extension Color {
    func writeRGBA(to pointer: UnsafeMutablePointer<UInt8>) {
        pointer[0] = UInt8((red.clamped() * 255).rounded())
        pointer[1] = UInt8((green.clamped() * 255).rounded())
        pointer[2] = UInt8((blue.clamped() * 255).rounded())
        pointer[3] = UInt8((alpha.clamped() * 255).rounded())
    }
}

extension Double {
    func clamped() -> Double {
        min(max(self, 0), 1)
    }
}

func render(mesh: Mesh, camera: ShapeScript.Camera, background: Color) throws -> SoftwareImage {
    let (width, height) = try camera.pixelSize
    guard width <= Int.max / height / MemoryLayout<Color>.stride else {
        throw CLIError("Image is too large for software rendering")
    }
    var pixels = Array(repeating: background, count: width * height)
    var depth = Array(repeating: Double.infinity, count: pixels.count)
    let light = Vector(-0.3, 0.8, 1).normalized().rotated(by: camera.orientation ?? .identity)
    for polygon in mesh.triangulate().polygons {
        let vertices = polygon.vertices.compactMap { project($0.position, using: camera) }
        guard vertices.count == 3 else { continue }
        let material = polygon.material as? Material ?? .default
        let shade = 0.45 + 0.55 * max(0, polygon.plane.normal.dot(light))
        let albedo = material.albedo?.color ?? .white
        let vertexColor = polygon.vertices[0].color
        let opacity = material.opacity?.color?.alpha ?? 1
        let color = (albedo * vertexColor)
            .withAlphaComponent(albedo.alpha * opacity * vertexColor.alpha) * Color(white: shade)
        rasterize(vertices, color: color, pixels: &pixels, depth: &depth, width: width, height: height)
    }
    return SoftwareImage(pixels: pixels, width: width, height: height)
}

private func project(_ position: Vector, using camera: ShapeScript.Camera) -> Vector? {
    guard let width = camera.width, let height = camera.height else { return nil }
    let pixelWidth = Double(width), pixelHeight = Double(height)
    let view = (-(camera.orientation ?? .identity)).rotate(position - (camera.position ?? .zero))
    guard view.z < -Double.ulpOfOne else { return nil }
    let fov = camera.fov ?? .degrees(60)
    if fov <= .zero {
        let scale = camera.scale.map { max($0.x, $0.y, $0.z) } ?? 1
        let pointsPerPixel = scale / pixelHeight
        return Vector(
            pixelWidth / 2 + view.x / pointsPerPixel,
            pixelHeight / 2 - view.y / pointsPerPixel,
            -view.z
        )
    }
    let focal = pixelHeight / (2 * tan(fov.radians / 2))
    return Vector(
        pixelWidth / 2 + view.x * focal / -view.z,
        pixelHeight / 2 - view.y * focal / -view.z,
        -view.z
    )
}

private func rasterize(
    _ vertices: [Vector],
    color: Color,
    pixels: inout [Color],
    depth: inout [Double],
    width: Int,
    height: Int
) {
    // Clamp before integer conversion, including triangles far outside the viewport.
    guard vertices.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { return }
    let minX = Int(max(0, min(Double(width), floor(vertices.map(\.x).min() ?? 0))))
    let maxX = Int(max(-1, min(Double(width - 1), ceil(vertices.map(\.x).max() ?? 0))))
    let minY = Int(max(0, min(Double(height), floor(vertices.map(\.y).min() ?? 0))))
    let maxY = Int(max(-1, min(Double(height - 1), ceil(vertices.map(\.y).max() ?? 0))))
    guard minX <= maxX, minY <= maxY else { return }
    let a = vertices[0], b = vertices[1], c = vertices[2]
    let area = (c - a).cross(b - a).z
    guard abs(area) > Double.ulpOfOne else { return }
    for y in minY ... maxY {
        for x in minX ... maxX {
            let p = Vector(Double(x) + 0.5, Double(y) + 0.5)
            let w0 = (p - b).cross(c - b).z / area
            let w1 = (p - c).cross(a - c).z / area
            let w2 = (p - a).cross(b - a).z / area
            guard w0 >= 0, w1 >= 0, w2 >= 0 else { continue }
            let z = w0 * a.z + w1 * b.z + w2 * c.z
            let index = y * width + x
            guard z < depth[index] else { continue }
            depth[index] = z
            pixels[index] = color.composited(over: pixels[index])
        }
    }
}
