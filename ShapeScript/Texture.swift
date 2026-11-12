//
//  Texture.swift
//  ShapeScript
//
//  Created by Nick Lockwood on 04/08/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation

#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
#endif

public struct Texture: Hashable, Sendable {
    private let info: Info

    public let name: String?
    public var intensity: Double
    public var url: URL? { info.url }
    public var data: Data { info.data }
}

/// Encodes the texture name and content identity, not the resolved image payload.
/// Used for preserving unique material identity in `GeometryCache` keys.
/// Decoded textures cannot be rendered directly.
extension Texture: Codable {
    private enum CodingKeys: CodingKey {
        case name, intensity, contentKey
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decodeIfPresent(String.self, forKey: .name)
        let intensity = try container.decode(Double.self, forKey: .intensity)
        let contentKey = try container.decodeIfPresent(String.self, forKey: .contentKey)
        self.init(info: Info(url: nil, data: Data(), contentKey: contentKey), name: name, intensity: intensity)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(info.contentKey, forKey: .contentKey)
    }
}

private extension Texture {
    final class Info: Hashable, @unchecked Sendable {
        let url: URL?
        let data: Data
        let contentKey: String

        #if canImport(CoreGraphics) && canImport(ImageIO)
        fileprivate typealias OpacityValues = (
            averageOpacity: Double,
            averageLuminance: Double,
            luminanceAlphaMaskData: Data?
        )

        private let colorLock = NSLock()
        private var hasLoadedAverageColor = false
        private var averageColorIfSet: Color?
        private let opacityLock = NSLock()
        private var hasLoadedOpacityValues = false
        private var opacityValuesIfSet: OpacityValues?
        #endif

        init(url: URL?, data: Data, contentKey: String? = nil) {
            self.url = url
            self.data = data
            if let contentKey {
                self.contentKey = contentKey
            } else {
                // Stable cache identity, computed once instead of hashing image bytes per polygon.
                var hash1: UInt64 = 0xCBF29CE484222325
                var hash2: UInt64 = 0x84222325CBF29CE4
                for byte in data {
                    hash1 = (hash1 ^ UInt64(byte)) &* 0x100000001B3
                    hash2 = (hash2 ^ (UInt64(byte) &+ 0x9E3779B97F4A7C15)) &* 0x100000001B3
                }
                self.contentKey = "\(data.count):\(String(hash1, radix: 16)):\(String(hash2, radix: 16))"
            }
        }

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs === rhs || lhs.contentKey == rhs.contentKey
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(contentKey)
        }
    }

    init(
        name: String?,
        url: URL?,
        data: Data,
        intensity: Double
    ) {
        self.name = name
        self.info = Info(url: url, data: data)
        self.intensity = intensity
    }
}

public extension Texture {
    static func file(name: String, url: URL?, intensity: Double = 1) throws -> Self {
        let url = url ?? URL(fileURLWithPath: name)
        try url.validateFileSize(limit: FileSizeLimit.image)
        let data = try Data(contentsOf: url)
        return .init(name: name, url: url, data: data, intensity: intensity)
    }

    static func data(_ data: Data, intensity: Double = 1) -> Texture {
        .init(name: nil, url: nil, data: data, intensity: intensity)
    }

    func withIntensity(_ intensity: Double) -> Self {
        .init(info: info, name: name, intensity: intensity)
    }
}

extension Texture {
    /// Bake an sRGB material tint into color pixels in linear light, preserving texture alpha and intensity.
    func tinted(by tint: Color) throws -> Texture {
        guard tint != .white else { return self }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw CocoaError(.fileReadCorruptFile) }
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(
            data: &pixels, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CocoaError(.fileReadCorruptFile) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let linearTint = tint.withAlphaComponent(1).toLinear()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3])
            guard alpha > 0 else { continue }
            let color = Color(
                red: Double(pixels[index]) / alpha,
                green: Double(pixels[index + 1]) / alpha,
                blue: Double(pixels[index + 2]) / alpha
            )
            let tinted = (color.toLinear() * linearTint).toSRGB()
            for (channel, value) in [tinted.red, tinted.green, tinted.blue].enumerated() {
                pixels[index + channel] = UInt8((min(1, max(0, value)) * alpha).rounded())
            }
        }
        guard let image = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return .data(output as Data, intensity: intensity)
        #else
        return self
        #endif
    }
}

#if canImport(CoreGraphics) && canImport(ImageIO)

extension Texture {
    static let checkerboard: Texture = {
        let data = NSMutableData()
        if let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) {
            CGImageDestinationAddImage(destination, .checkerboard(), nil)
            CGImageDestinationFinalize(destination)
        }
        return .data(data as Data)
    }()

    var averageColor: Color? {
        info.averageColor
    }

    var averageOpacity: Double {
        info.averageOpacity
    }

    var averageLuminance: Double {
        info.averageLuminance
    }

    var opacityMaskData: Data? {
        info.luminanceAlphaMaskData
    }
}

extension Texture.Info {
    var averageColor: Color? {
        colorLock.lock()
        defer { colorLock.unlock() }
        if !hasLoadedAverageColor {
            averageColorIfSet = cgImage?.averageColor
            hasLoadedAverageColor = true
        }
        return averageColorIfSet
    }

    var averageOpacity: Double {
        opacityValues.averageOpacity
    }

    var averageLuminance: Double {
        opacityValues.averageLuminance
    }

    var luminanceAlphaMaskData: Data? {
        opacityValues.luminanceAlphaMaskData
    }

    private var opacityValues: OpacityValues {
        opacityLock.lock()
        defer { opacityLock.unlock() }
        if !hasLoadedOpacityValues {
            opacityValuesIfSet = cgImage?.opacityValues ?? (
                averageOpacity: 1,
                averageLuminance: 1,
                luminanceAlphaMaskData: nil
            )
            hasLoadedOpacityValues = true
        }
        return opacityValuesIfSet ?? (
            averageOpacity: 1,
            averageLuminance: 1,
            luminanceAlphaMaskData: nil
        )
    }

    private var cgImage: CGImage? {
        let source: CGImageSource? = if let url {
            CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            CGImageSourceCreateWithData(data as CFData, nil)
        }
        return source.flatMap {
            CGImageSourceCreateImageAtIndex($0, 0, nil)
        }
    }
}

private extension CGImage {
    var averageColor: Color? {
        // Average premultiplied linear RGB so transparent pixels contribute in proportion
        // to their coverage, then return the unpremultiplied sRGB convention used by Color.
        guard let space = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        // Process strips to avoid allocating a floating-point copy of the entire texture.
        let stripHeight = min(height, 64)
        var components = [Float](repeating: 0, count: width * stripHeight * 4)
        guard let context = CGContext(
            data: &components,
            width: width,
            height: stripHeight,
            bitsPerComponent: 32,
            bytesPerRow: width * 4 * MemoryLayout<Float>.size,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setBlendMode(.copy)
        var red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0
        for row in stride(from: 0, to: height, by: stripHeight) {
            context.draw(self, in: CGRect(x: 0, y: stripHeight - height + row, width: width, height: height))
            let count = width * min(stripHeight, height - row) * 4
            for index in stride(from: 0, to: count, by: 4) {
                red += Double(components[index])
                green += Double(components[index + 1])
                blue += Double(components[index + 2])
                alpha += Double(components[index + 3])
            }
        }
        guard alpha > 0 else { return .clear }
        return Color(
            red: red / alpha,
            green: green / alpha,
            blue: blue / alpha,
            alpha: alpha / Double(width * height)
        ).toSRGB()
    }

    var opacityValues: Texture.Info.OpacityValues {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var components = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return (
                averageOpacity: 1,
                averageLuminance: 1,
                luminanceAlphaMaskData: nil
            )
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(self, in: rect)

        var alphaTotal = 0
        var luminanceTotal = 0
        var hasTransparentAlpha = false
        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Double(components[index]) / 255
            let green = Double(components[index + 1]) / 255
            let blue = Double(components[index + 2]) / 255
            let alpha = Int(components[index + 3])
            let color = Color(red: red, green: green, blue: blue)
            let luminance = Int(color.luminance * 255)
            alphaTotal += alpha
            luminanceTotal += luminance
            hasTransparentAlpha = hasTransparentAlpha || alpha < 255
        }

        let pixelCount = max(width * height, 1)
        let averageOpacity: Double
        let averageLuminance = Double(luminanceTotal) / Double(pixelCount * 255)
        if hasTransparentAlpha {
            averageOpacity = Double(alphaTotal) / Double(pixelCount * 255)
            return (
                averageOpacity: averageOpacity,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        for index in stride(from: 0, to: components.count, by: bytesPerPixel) {
            let red = Double(components[index]) / 255
            let green = Double(components[index + 1]) / 255
            let blue = Double(components[index + 2]) / 255
            let color = Color(red: red, green: green, blue: blue)
            let luminance = UInt8(color.luminance * 255)
            components[index] = luminance
            components[index + 1] = luminance
            components[index + 2] = luminance
            components[index + 3] = luminance
        }

        guard let context = CGContext(
            data: &components,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else {
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            return (
                averageOpacity: 1,
                averageLuminance: averageLuminance,
                luminanceAlphaMaskData: nil
            )
        }

        return (
            averageOpacity: 1,
            averageLuminance: averageLuminance,
            luminanceAlphaMaskData: data as Data
        )
    }
}

#else

extension Texture {
    static let checkerboard: Texture = .init(
        name: nil,
        url: nil,
        data: .init(),
        intensity: 0
    )

    var averageColor: Color? {
        Color(white: 0.5)
    }

    var averageOpacity: Double {
        averageColor?.alpha ?? 1
    }

    var averageLuminance: Double {
        averageColor?.luminance ?? 1
    }

    var opacityMaskData: Data? {
        nil
    }
}

#endif
