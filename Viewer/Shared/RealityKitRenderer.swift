//
//  RealityKitRenderer.swift
//  ShapeScript Viewer
//
//  Created by Nick Lockwood on 06/09/2026.
//  Copyright © 2026 Nick Lockwood. All rights reserved.
//

import Euclid
import Foundation
import RealityKit
import ShapeScript
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

let volumeDefaultWidth = 1.0
let volumeDefaultHeight = 1.0
let volumeDefaultDepth = 3.0
private let volumeContentMargin = 0.05
private let volumeMinimumContentDimension = 0.05

struct VolumeSize {
    let width: Double
    let height: Double
    let depth: Double

    static let volume = Self(
        width: volumeDefaultWidth,
        height: volumeDefaultHeight,
        depth: volumeDefaultDepth
    )

    static let flat = Self(
        width: volumeDefaultWidth,
        height: volumeDefaultHeight,
        depth: 0
    )
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
@MainActor
final class RealityKitRenderer: @unchecked Sendable {
    #if canImport(UIKit)
    let hostingController: UIHostingController<RealityKitView>
    #elseif canImport(AppKit)
    let hostingController: NSHostingController<RealityKitView>
    #endif

    private(set) var realityKitView: RealityKitView
    #if os(visionOS)
    var onVolumeSizeChanged: ((VolumeSize) -> Void)?
    #endif
    var onSelectGeometry: ((Geometry?) -> Void)?
    private let tapHandler = RealityKitTapHandler()
    private let rootEntity = Entity()
    private let contentEntity = Entity()
    #if !os(visionOS)
    let cameraEntity = Entity()
    private let defaultLightEntity = Entity()
    private var viewportSize = CGSize.zero
    private var isOrthographic = false
    #endif
    private var axesEntity: Entity?
    private var geometriesByEntityID = [Entity.ID: Geometry]()
    private var entitiesByGeometryID = [ObjectIdentifier: [Entity]]()
    private var geometriesByID = [ObjectIdentifier: Geometry]()
    private var materialsByEntityID = [Entity.ID: [RealityKit.Material]]()
    private var collisionTask: Task<Void, Never>?
    private weak var selectedGeometry: Geometry?
    private var hasAuthoredLights = false
    private var showAxes = false
    private var isQuickLook = false
    private var camera = Camera.default
    private var visibleBounds = Bounds.empty
    private var interfaceColor = OSColor.white
    private var volumeBottomMargin = volumeContentMargin

    init() {
        rootEntity.addChild(contentEntity)
        #if !os(visionOS)
        cameraEntity.components.set(PerspectiveCameraComponent())
        rootEntity.addChild(cameraEntity)
        cameraEntity.addChild(defaultLightEntity)
        #endif
        self.realityKitView = RealityKitView(rootEntity: rootEntity) { [tapHandler] entity in
            tapHandler.selectGeometry(entity)
        }
        #if canImport(UIKit)
        self.hostingController = UIHostingController(rootView: realityKitView)
        #elseif canImport(AppKit)
        self.hostingController = NSHostingController(rootView: realityKitView)
        #endif
        #if !os(visionOS)
        updateDefaultLighting(usesPhysicallyBasedMaterials: false)
        realityKitView.onViewportSizeChanged = { [weak self] size in
            self?.updateViewportSize(size)
        }
        hostingController.rootView = realityKitView
        #endif
        tapHandler.renderer = self
        #if canImport(UIKit)
        hostingController.view.backgroundColor = .clear
        #endif
    }

    #if canImport(UIKit)
    var view: UIView {
        hostingController.view
    }
    #elseif canImport(AppKit)
    var view: NSView {
        hostingController.view
    }
    #endif

    deinit {
        collisionTask?.cancel()
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
extension RealityKitRenderer: SceneRenderer {
    nonisolated var supportsIncrementalGeometryUpdates: Bool { false }

    nonisolated func validate(_: ShapeScript.Scene, source _: String) throws {
        // RealityKit does not have SceneKit's eight-light limit.
    }

    nonisolated func prepare(_ scene: ShapeScript.Scene, options: ShapeScript.Scene.OutputOptions) {
        let descriptors = scene.realityKitEntityDescriptors(with: options)
        if Thread.isMainThread {
            Task {
                await prepareAsync(
                    scene,
                    options: options,
                    descriptors: descriptors
                )
            }
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await prepareAsync(
                scene,
                options: options,
                descriptors: descriptors
            )
            semaphore.signal()
        }
        semaphore.wait()
    }

    nonisolated func prepareAsync(
        _ scene: ShapeScript.Scene,
        options: ShapeScript.Scene.OutputOptions
    ) async {
        let descriptors = scene.realityKitEntityDescriptors(with: options)
        await prepareAsync(
            scene,
            options: options,
            descriptors: descriptors
        )
    }

    private nonisolated func prepareAsync(
        _ scene: ShapeScript.Scene,
        options _: ShapeScript.Scene.OutputOptions,
        descriptors: [RealityKitEntityDescriptor]
    ) async {
        do {
            try await applyAsync(
                scene,
                descriptors: descriptors
            )
        } catch {
            print(error.localizedDescription)
        }
    }

    private func applyAsync(
        _ scene: ShapeScript.Scene,
        descriptors: [RealityKitEntityDescriptor]
    ) async throws {
        let references = try await scene.realityKitEntityReferences(from: descriptors)
        let lighting: Entity? = if #available(visionOS 2.0, *) {
            try await scene.realityKitLightingEntity()
        } else {
            nil
        }
        visibleBounds = scene.visibleBounds
        collisionTask?.cancel()
        collisionTask = nil
        contentEntity.children.removeAll()
        contentEntity.components.remove(ImageBasedLightReceiverComponent.self)
        hasAuthoredLights = lighting?.components[ImageBasedLightComponent.self] != nil
        if hasAuthoredLights, let lighting {
            contentEntity.addChild(lighting)
            contentEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: lighting))
        }
        geometriesByEntityID.removeAll()
        entitiesByGeometryID.removeAll()
        geometriesByID.removeAll()
        materialsByEntityID.removeAll()
        for reference in references {
            reference.entity.enableTapTarget(with: reference.collisionMesh)
            contentEntity.addChild(reference.entity)
            geometriesByEntityID[reference.entity.id] = reference.geometry
            let geometryID = ObjectIdentifier(reference.geometry)
            geometriesByID[geometryID] = reference.geometry
            entitiesByGeometryID[geometryID, default: []].append(reference.entity)
            reference.entity.storeMaterials(in: &materialsByEntityID)
        }
        #if !os(visionOS)
        updateDefaultLighting(usesPhysicallyBasedMaterials: descriptors.contains(where: \.usesPhysicallyBasedMaterials))
        #endif
        updateSelection()
        fitContent(axesBounds: updateAxesEntity())
        collisionTask = collisionTask(for: references)
    }

    nonisolated func updateAxesAndCamera(
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        isOrthographic: Bool,
        visibleBounds: Bounds,
        interfaceColor: OSColor
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                updateAxesAndCameraOnMainActor(
                    showAxes: showAxes,
                    isQuickLook: isQuickLook,
                    camera: camera,
                    isOrthographic: isOrthographic,
                    visibleBounds: visibleBounds,
                    interfaceColor: interfaceColor
                )
            }
            return
        }
        Task { @MainActor in
            updateAxesAndCameraOnMainActor(
                showAxes: showAxes,
                isQuickLook: isQuickLook,
                camera: camera,
                isOrthographic: isOrthographic,
                visibleBounds: visibleBounds,
                interfaceColor: interfaceColor
            )
        }
    }

    private func updateAxesAndCameraOnMainActor(
        showAxes: Bool,
        isQuickLook: Bool,
        camera: Camera,
        isOrthographic: Bool,
        visibleBounds: Bounds,
        interfaceColor: OSColor
    ) {
        self.showAxes = showAxes
        self.isQuickLook = isQuickLook
        self.camera = camera
        #if !os(visionOS)
        self.isOrthographic = isOrthographic
        #endif
        self.visibleBounds = visibleBounds
        self.interfaceColor = interfaceColor
        fitContent(axesBounds: updateAxesEntity())
    }

    private func updateAxesEntity() -> Bounds {
        axesEntity?.removeFromParent()
        axesEntity = nil
        guard showAxes, !isQuickLook else {
            return .empty
        }
        do {
            let scale = axesSize(for: visibleBounds)
            let axes = Axes(
                scale: scale,
                camera: camera,
                color: Color(interfaceColor)
            )
            let entity = try Entity(axes, lineWidth: scale * 0.005)
            contentEntity.addChild(entity)
            axesEntity = entity
            return axes.geometry.overestimatedBounds
        } catch {
            print(error.localizedDescription)
            return .empty
        }
    }

    #if !os(visionOS)
    private func updateDefaultLighting(usesPhysicallyBasedMaterials: Bool) {
        // PBR surfaces need environment reflections as well as a softer camera light.
        // Plain materials retain the camera-facing lighting that matches SceneKit.
        defaultLightEntity.components.set(DirectionalLightComponent(
            color: .white, intensity: usesPhysicallyBasedMaterials ? 1000 : 3000,
            isRealWorldProxy: false
        ))
        defaultLightEntity.isEnabled = !hasAuthoredLights
        if usesPhysicallyBasedMaterials, !hasAuthoredLights {
            rootEntity.components.remove(ImageBasedLightReceiverComponent.self)
            rootEntity.components.remove(ImageBasedLightComponent.self)
        } else {
            rootEntity.components.set(ImageBasedLightComponent(source: .none))
            rootEntity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: rootEntity))
        }
    }

    func updateViewportSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0, size != viewportSize else { return }
        viewportSize = size
        updateWindowCamera()
    }

    private func updateWindowCamera() {
        guard viewportSize.width > 0, viewportSize.height > 0, !visibleBounds.isEmpty else { return }
        let framing = camera.framing(
            visibleBounds: visibleBounds, viewSize: viewportSize, showAxes: showAxes
        )
        cameraEntity.transform = RealityKit.Transform(framing.transform)
        if camera.isOrthographic ?? (isOrthographic && !isQuickLook) {
            var projection = OrthographicCameraComponent()
            projection.scale = Float(framing.orthographicScale)
            projection.scaleDirection = .vertical
            projection.near = 0.001
            projection.far = Float(max(100, visibleBounds.size.length * 100))
            cameraEntity.components.remove(PerspectiveCameraComponent.self)
            cameraEntity.components.set(projection)
        } else {
            cameraEntity.components.remove(OrthographicCameraComponent.self)
            cameraEntity.components.set(PerspectiveCameraComponent(
                near: 0.001, far: .infinity,
                fieldOfViewInDegrees: Float(camera.fov.degrees),
                fieldOfViewOrientation: .vertical
            ))
        }
    }
    #endif

    private func fitContent(axesBounds: Bounds) {
        #if !os(visionOS)
        contentEntity.transform = .identity
        updateWindowCamera()
        #else
        let bounds = visibleBounds.union(axesBounds)
        let maximumHeight = max(
            volumeMinimumContentDimension,
            volumeDefaultHeight - volumeContentMargin - volumeBottomMargin
        )
        let maximumSize = Vector(
            volumeDefaultWidth - volumeContentMargin * 2,
            maximumHeight,
            volumeDefaultDepth - volumeContentMargin * 2
        )
        let volumeSize = contentEntity.fit(
            inVolumeWithMaximumSize: maximumSize,
            topMargin: volumeContentMargin,
            bottomMargin: volumeBottomMargin,
            bounds: bounds
        )
        rootEntity.position.z = 0
        onVolumeSizeChanged?(volumeSize)
        #endif
    }

    #if os(visionOS)
    func setVolumeBottomPadding(_ padding: Double) {
        let margin = volumeContentMargin + max(0, padding)
        guard margin != volumeBottomMargin else {
            return
        }
        volumeBottomMargin = margin
        fitContent(axesBounds: updateAxesEntity())
    }
    #endif

    fileprivate func selectGeometry(_ entity: Entity?) {
        var entity = entity
        while let currentEntity = entity {
            if let geometry = geometriesByEntityID[currentEntity.id] {
                onSelectGeometry?(geometry)
                return
            }
            entity = currentEntity.parent
        }
        onSelectGeometry?(nil)
    }

    private func collisionTask(for references: [RealityKitEntityReference]) -> Task<Void, Never>? {
        #if os(visionOS)
        guard #available(visionOS 2.0, *) else {
            references.forEach { $0.entity.enableBoxTapTarget() }
            return nil
        }
        #endif
        return Task { @MainActor [weak self, references] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            for reference in references {
                guard !Task.isCancelled else {
                    return
                }
                guard let collisionMesh = reference.collisionMesh else {
                    reference.entity.enableBoxTapTarget()
                    continue
                }
                do {
                    let shape = try await ShapeResource.generateStaticMesh(from: collisionMesh)
                    guard !Task.isCancelled,
                          self?.geometriesByEntityID[reference.entity.id] != nil
                    else {
                        return
                    }
                    reference.entity.components.set(CollisionComponent(shapes: [shape]))
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    print(error.localizedDescription)
                }
            }
        }
    }

    func select(_ geometry: Geometry?) {
        selectedGeometry = geometry
        updateSelection()
    }

    private func updateSelection() {
        contentEntity.restoreMaterials(from: materialsByEntityID)
        guard let selectedGeometry else {
            return
        }
        for (id, entities) in entitiesByGeometryID {
            guard let geometry = geometriesByID[id],
                  geometry === selectedGeometry || geometry.isDescendant(of: selectedGeometry)
            else {
                continue
            }
            for entity in entities {
                entity.applySelectionHighlight()
            }
        }
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
@MainActor
private final class RealityKitTapHandler {
    weak var renderer: RealityKitRenderer?

    func selectGeometry(_ entity: Entity?) {
        renderer?.selectGeometry(entity)
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
struct RealityKitView: View {
    let rootEntity: Entity
    let onTapEntity: (Entity?) -> Void
    var onViewportSizeChanged: ((CGSize) -> Void)?
    #if !os(visionOS)
    @State private var cameraContent: RealityViewCameraContent?
    #endif

    fileprivate init(
        rootEntity: Entity,
        onTapEntity: @escaping (Entity?) -> Void
    ) {
        self.rootEntity = rootEntity
        self.onTapEntity = onTapEntity
    }

    var body: some View {
        RealityView { content in
            content.add(rootEntity)
            #if !os(visionOS)
            content.camera = .virtual
            cameraContent = content
            #endif
        }
        #if os(macOS)
        .backgroundStyle(SwiftUI.Color(nsColor: .underPageBackgroundColor))
        #endif
        #if os(visionOS)
        .frame(maxDepth: .infinity, alignment: .center)
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background {
            GeometryReader { proxy in
                SwiftUI.Color.clear
                    .onAppear { onViewportSizeChanged?(proxy.size) }
                    .onChange(of: proxy.size) { _, size in onViewportSizeChanged?(size) }
            }
        }
        #endif
        #if os(visionOS)
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    onTapEntity(value.entity)
                }
        )
        #else
        .gesture(
            SpatialTapGesture().onEnded { value in
                guard let ray = cameraContent?.ray(through: value.location, in: .local, to: .scene) else {
                    return
                }
                onTapEntity(rootEntity.selectionTarget(origin: ray.origin, direction: ray.direction))
            }
        )
        #endif
        #if os(iOS)
        .ignoresSafeArea(.container)
        #endif
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
extension Entity {
    func selectionTarget(origin: SIMD3<Float>, direction: SIMD3<Float>) -> Entity? {
        // Targeted taps use a limited ray length, which can miss large CAD scenes.
        // Reach the far edge of the scene's bounds regardless of the camera distance.
        let bounds = visualBounds(relativeTo: nil)
        guard !bounds.isEmpty else { return nil }
        let length = simd_distance(origin, bounds.center) + simd_length(bounds.extents)
        return scene?.raycast(
            origin: origin, direction: direction, length: length, query: .nearest
        ).first?.entity
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
private extension Entity {
    func enableTapTarget(with collisionMesh: MeshResource?) {
        if collisionMesh == nil {
            enableBoxTapTarget()
        }
        components.set(InputTargetComponent())
    }

    func enableBoxTapTarget() {
        let bounds = visualBounds(relativeTo: self)
        guard !bounds.isEmpty else { return }
        let shape = ShapeResource.generateBox(size: bounds.extents)
            .offsetBy(translation: bounds.center)
        components.set(CollisionComponent(shapes: [shape]))
    }

    func storeMaterials(in materialsByEntityID: inout [Entity.ID: [RealityKit.Material]]) {
        if let modelEntity = self as? ModelEntity,
           let model = modelEntity.model
        {
            materialsByEntityID[id] = model.materials
        }
        children.forEach { $0.storeMaterials(in: &materialsByEntityID) }
    }

    @discardableResult
    func restoreMaterials(from materialsByEntityID: [Entity.ID: [RealityKit.Material]]) -> Int {
        var count = 0
        if let modelEntity = self as? ModelEntity,
           var model = modelEntity.model,
           let materials = materialsByEntityID[id]
        {
            model.materials = materials.map { material in
                if var shader = material as? ShaderGraphMaterial {
                    for name in ["baseColor", "emissiveColor", "emissiveIntensity"] {
                        if let value = shader.getParameter(name: name) {
                            try? shader.setParameter(name: name, value: value)
                        }
                    }
                    return shader
                }
                guard var material = material as? PhysicallyBasedMaterial else { return material }
                // Explicitly reset emission: restoring a saved material alone can leave
                // RealityKit's rendered selection emission active.
                let emission = material.emissiveColor
                let intensity = material.emissiveIntensity
                material.emissiveColor = emission
                material.emissiveIntensity = intensity
                return material
            }
            modelEntity.model = model
            count += materials.count
        }
        for child in children {
            count += child.restoreMaterials(from: materialsByEntityID)
        }
        return count
    }

    @discardableResult
    func applySelectionHighlight() -> Int {
        var count = 0
        if let modelEntity = self as? ModelEntity,
           var model = modelEntity.model,
           !model.materials.isEmpty
        {
            model.materials = model.materials.map { $0.addingSelectionHighlight() }
            modelEntity.model = model
            count += model.materials.count
        }
        for child in children {
            count += child.applySelectionHighlight()
        }
        return count
    }
}

@available(macOS 15.0, iOS 18.0, tvOS 26.0, visionOS 1.0, *)
private extension RealityKit.Material {
    func addingSelectionHighlight() -> RealityKit.Material {
        switch self {
        case var material as PhysicallyBasedMaterial:
            material.baseColor.tint = material.baseColor.tint.multiplied(
                by: OSColor(red: 1, green: 0.7, blue: 0.7, alpha: 1)
            )
            material.emissiveColor = .init(color: .red)
            material.emissiveIntensity = 1
            return material
        case var material as UnlitMaterial:
            let color = Euclid.Color(material.color.tint.cgColor)
            material.color.tint = OSColor(Euclid.Color(
                red: 1, green: color.green * 0.7, blue: color.blue * 0.7, alpha: color.alpha
            ))
            return material
        case var material as ShaderGraphMaterial:
            guard case let .color(color) = material.getParameter(name: "baseColor"),
                  material.getParameter(name: "emissiveColor") != nil
            else { return self }
            let tint = OSColor(Euclid.Color(color)).multiplied(by: OSColor(
                red: 1,
                green: 0.7,
                blue: 0.7,
                alpha: 1
            ))
            try? material.setParameter(name: "baseColor", value: .color(tint.cgColor))
            try? material.setParameter(name: "emissiveColor", value: .color(OSColor.red.cgColor))
            try? material.setParameter(name: "emissiveIntensity", value: .float(1))
            return material
        default:
            return self
        }
    }
}

private extension OSColor {
    func multiplied(by color: OSColor) -> OSColor {
        OSColor((Euclid.Color(self).toLinear() * Euclid.Color(color).toLinear()).toSRGB())
    }
}

private extension Entity {
    @discardableResult
    func fit(
        inVolumeWithMaximumSize maximumSize: Vector,
        topMargin: Double,
        bottomMargin: Double,
        bounds: Bounds
    ) -> VolumeSize {
        guard !bounds.isEmpty else {
            return .init(
                width: volumeDefaultWidth,
                height: volumeDefaultHeight,
                depth: volumeDefaultDepth
            )
        }
        let size = bounds.size
        let scaleX = maximumSize.x / max(size.x, .leastNonzeroMagnitude)
        let scaleY = maximumSize.y / max(size.y, .leastNonzeroMagnitude)
        let scaleZ = maximumSize.z / max(size.z, .leastNonzeroMagnitude)
        let maxDimension = max(size.x, size.y, size.z)
        let center = bounds.center
        guard maxDimension > 0,
              [center.x, center.y, center.z, maxDimension, scaleX, scaleY, scaleZ]
                  .allSatisfy(\.isFinite)
        else {
            return .init(
                width: volumeDefaultWidth,
                height: volumeDefaultHeight,
                depth: volumeDefaultDepth
            )
        }
        let scale = Float(min(scaleX, scaleY, scaleZ))
        let targetCenterY = (bottomMargin - topMargin) / 2
        self.scale = .init(repeating: scale)
        position = .init(
            -Float(center.x) * scale,
            Float(targetCenterY) - Float(center.y) * scale,
            -Float(center.z) * scale
        )
        return .init(
            width: Double(size.x) * Double(scale) + volumeContentMargin * 2,
            height: Double(size.y) * Double(scale) + topMargin + bottomMargin,
            depth: Double(size.z) * Double(scale) + volumeContentMargin * 2
        )
    }
}

private func axesSize(for visibleBounds: Bounds) -> Double {
    guard !visibleBounds.isEmpty else {
        return 1
    }
    let m = max(-visibleBounds.min, visibleBounds.max)
    return max(m.x, m.y, m.z) * 1.1
}
