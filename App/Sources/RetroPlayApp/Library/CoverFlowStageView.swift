// SPDX-License-Identifier: GPL-3.0-or-later
import RealityKit
import RetroPlayCore
import SwiftUI
import UIKit

/// The Cover Flow row drawn as a RealityKit scene: one rounded box mesh per game, its front,
/// spine and top as textures (drawn once per game and kept), seen through one camera. Each
/// frame only moves the boxes to where the scroll puts them; nothing in SwiftUI redraws. The
/// invisible scroll view in front of it takes the swipes, taps and VoiceOver.
struct CoverFlowStageView: View {
    let scene: CoverFlowScene
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            stage
                // The camera is set from the size the scene is really drawn at.
                .onChange(of: geo.size, initial: true) { _, size in scene.viewSize = size }
        }
        .frame(height: height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var stage: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(scene.root)
            scene.subscription = content.subscribe(to: SceneEvents.Update.self) { [scene] _ in
                MainActor.assumeIsolated { scene.frame() }
            }
        } update: { _ in
            scene.frame()
        }
    }
}

/// What the scene draws and how far the row is scrolled; the library view keeps it up to date.
@MainActor
final class CoverFlowScene {
    /// Scene units per point (RealityKit works in metres; a row hundreds of points wide is
    /// kept to a few units).
    static let unit: Float = 0.01

    let root = Entity()
    private let camera = Entity()
    var subscription: EventSubscription?

    struct Input: Equatable {
        var games: [LibraryGame]
        var stage: CoverFlow.Stage
        /// The view the scene is drawn in.
        var size: CGSize
        var missing: Set<UUID>
        var liveIndex: Int
        var dark: Bool
        /// Bumped when covers change on disk (box art downloaded).
        var artRevision: Int
    }

    var input: Input? {
        didSet {
            guard input != oldValue else { return }
            if input?.size != oldValue?.size || input?.stage != oldValue?.stage
                || input?.artRevision != oldValue?.artRevision || input?.dark != oldValue?.dark {
                clear()
            }
            placeCamera()
            needsTint = true
        }
    }

    /// The size the scene's view is really drawn at (its camera is fitted to it).
    var viewSize: CGSize = .zero {
        didSet {
            guard viewSize != oldValue else { return }
            placeCamera()
        }
    }

    /// The scroll position (content offset from the first cover centred).
    var offset: () -> Double = { 0 }
    var artwork: (LibraryGame) -> CoverArt? = { _ in nil }

    private var boxes: [UUID: CoverBoxEntity] = [:]
    private var needsTint = true

    init() {
        root.addChild(camera)
        camera.components.set(PerspectiveCameraComponent(near: 0.05, far: 400, fieldOfViewInDegrees: 30))
    }

    private func placeCamera() {
        guard let input else { return }
        let stage = input.stage
        let u = Self.unit
        camera.position = [0, Float(stage.eyeHeight) * u, Float(stage.eyeDistance) * u]
        var lens = camera.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        let height = viewSize.height > 0 ? viewSize.height : input.size.height
        lens.fieldOfViewInDegrees = Float(stage.fieldOfView(height: Double(height)))
        lens.fieldOfViewOrientation = .vertical
        lens.far = Float(stage.eyeDistance * 4) * u
        camera.components.set(lens)
        // The view is centred on the eye, which is level with the slot's top.
        root.position = .zero
    }

    private func clear() {
        for box in boxes.values { box.entity.removeFromParent() }
        boxes.removeAll()
    }

    /// Moves every box to where the scroll puts it this frame; builds the ones coming into
    /// view and drops the ones that left.
    func frame() {
        guard let input, !input.games.isEmpty else {
            clear()
            return
        }
        let stage = input.stage
        let metrics = stage.metrics
        let offset = offset()
        let window = stage.window(offset: offset, count: input.games.count, width: Double(input.size.width))
        let wanted = Set(window.map { input.games[$0].id })
        for (id, box) in boxes where !wanted.contains(id) {
            box.entity.removeFromParent()
            boxes[id] = nil
        }
        let u = Self.unit
        for index in window {
            let game = input.games[index]
            let box = boxes[game.id] ?? makeBox(game, input: input)
            boxes[game.id] = box
            let place = stage.place(distance: Double(index) * metrics.step - offset,
                                    height: box.size.height, depth: box.size.depth)
            box.entity.position = [Float(place.x) * u, Float(place.y) * u, Float(place.z) * u]
            box.entity.scale = SIMD3(repeating: Float(place.scale))
            box.entity.orientation = simd_quatf(angle: Float(CoverFlow.pitch * .pi / 180), axis: [1, 0, 0])
                * simd_quatf(angle: Float(place.yaw * .pi / 180), axis: [0, 1, 0])
            if needsTint {
                box.tint(dimming: metrics.pose(distance: Double(index - input.liveIndex) * metrics.step).dimming)
            }
        }
        needsTint = false
    }

    private func makeBox(_ game: LibraryGame, input: Input) -> CoverBoxEntity {
        let box = CoverBoxEntity(
            game: game,
            cover: artwork(game),
            missing: input.missing.contains(game.id),
            metrics: input.stage.metrics,
            dark: input.dark
        )
        root.addChild(box.entity)
        return box
    }
}

/// One game's box: a rounded box mesh with its six faces textured.
@MainActor
final class CoverBoxEntity {
    let entity: ModelEntity
    /// Points: as wide and tall as the cover, as deep as its system's box.
    let size: (width: Double, height: Double, depth: Double)
    private let faces: [UnlitMaterial]

    /// Faces of `MeshResource.generateBox(splitFaces: true)`, in its order.
    enum Face: Int, CaseIterable {
        case front, top, back, bottom, right, left
    }

    init(game: LibraryGame, cover: CoverArt?, missing: Bool, metrics: CoverFlow.Metrics, dark: Bool) {
        let aspect = CoverBoxTextures.aspect(game: game, cover: cover)
        let drawn = metrics.coverSize(aspect: aspect)
        let depth = (metrics.coverWidth * CoverFlow.boxDepth(game.systemID)).rounded()
        size = (drawn.width, drawn.height, depth)
        let package = RetailPackage.of(game.systemID)
        let radius = min(depth * package.edgeRounding, depth / 2, drawn.width / 5)
        let u = CoverFlowScene.unit
        let mesh = CoverBoxTextures.mesh(width: Float(drawn.width) * u, height: Float(drawn.height) * u,
                                         depth: Float(depth) * u, radius: Float(radius) * u)
        let textures = CoverBoxTextures(game: game, cover: cover, missing: missing,
                                        size: CGSize(width: drawn.width, height: drawn.height),
                                        depth: depth, radius: radius)
        faces = Face.allCases.map { textures.material(for: $0) }
        entity = ModelEntity(mesh: mesh, materials: faces)
    }

    /// Darkens a box far from the middle.
    func tint(dimming: Double) {
        let shade = UIColor(white: CGFloat(1 - dimming), alpha: 1)
        entity.model?.materials = faces.map { face in
            var material = face
            material.color.tint = shade
            return material
        }
    }
}

/// Draws a box's faces as pictures (SwiftUI views rendered once), for its materials.
@MainActor
struct CoverBoxTextures {
    let game: LibraryGame
    let cover: CoverArt?
    let missing: Bool
    let size: CGSize
    let depth: Double
    let radius: Double

    private static let meshes = NSCache<NSString, MeshResource>()

    static func mesh(width: Float, height: Float, depth: Float, radius: Float) -> MeshResource {
        let key = "\(width)x\(height)x\(depth)r\(radius)" as NSString
        if let known = meshes.object(forKey: key) { return known }
        let mesh = MeshResource.generateBox(width: width, height: height, depth: depth,
                                            cornerRadius: radius, splitFaces: true)
        meshes.setObject(mesh, forKey: key)
        return mesh
    }

    static func aspect(game: LibraryGame, cover: CoverArt?) -> Double {
        if let cover, cover.isBoxArt, cover.image.size.height > 0 {
            return min(max(Double(cover.image.size.width / cover.image.size.height), 0.5), 1.6)
        }
        return Double(RetroPlayTheme.boxArtAspect(game.systemID))
    }

    func material(for face: CoverBoxEntity.Face) -> UnlitMaterial {
        let package = RetailPackage.of(game.systemID)
        let colors = BoxEdgeColors(system: game.systemID, package: package, cover: cover)
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "RetroPlaySmokeBoxFaces") {
            return textured(FaceLabel(face: face), width: faceSize(face).width, height: faceSize(face).height)
        }
        #endif
        switch face {
        case .front:
            // The art on the flat of the face: the rounded edges round it take the box's
            // edge colour, not a sliver of the art.
            return textured(
                GameArtworkView(game: game, artwork: cover?.image, isBoxArt: cover?.isBoxArt ?? false,
                                cornerRadius: 0, labelTitleSize: 16)
                    .opacity(missing ? 0.45 : 1)
                    .padding(radius)
                    .background(colors.side),
                width: size.width, height: size.height
            )
        case .left:
            return textured(
                PackageSpine(system: game.systemID, title: game.displayName, cover: cover, cornerRadius: 0)
                    .padding(.vertical, radius)
                    .background(colors.side),
                width: depth, height: size.height
            )
        case .top:
            return textured(
                PackageTop(system: game.systemID, cover: cover, cornerRadius: 0)
                    .padding(radius * 0.5)
                    .background(colors.top),
                width: size.width, height: depth
            )
        case .back, .bottom, .right:
            var material = UnlitMaterial(color: UIColor(colors.side))
            material.color.tint = UIColor(white: face == .bottom ? 0.6 : 0.8, alpha: 1)
            return material
        }
    }

    private func faceSize(_ face: CoverBoxEntity.Face) -> CGSize {
        switch face {
        case .front, .back: return size
        case .left, .right: return CGSize(width: depth, height: size.height)
        case .top, .bottom: return CGSize(width: size.width, height: depth)
        }
    }

    private func textured(_ view: some View, width: Double, height: Double) -> UnlitMaterial {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let texture = try? TextureResource(image: image, options: .init(semantic: .color))
        else {
            return UnlitMaterial(color: .darkGray)
        }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        return material
    }
}

/// The colours round a box: a case's plastic, or on a cardboard box the colour of its cover's
/// edges (the art printed round it).
struct BoxEdgeColors {
    let side: Color
    let top: Color

    @MainActor
    init(system: SystemID, package: RetailPackage, cover: CoverArt?) {
        let art = cover.flatMap { $0.isBoxArt ? $0.image : nil }
        if let plastic = package.plastic {
            side = plastic.color
            top = plastic.color
        } else {
            let tint = RetroPlayTheme.systemTint(system)
            side = art.flatMap { CoverEdgeColor.left(of: $0) }.map { Color(uiColor: $0) } ?? tint
            top = art.flatMap { CoverEdgeColor.top(of: $0) }.map { Color(uiColor: $0) } ?? tint
        }
    }
}

#if DEBUG
/// `-RetroPlaySmokeBoxFaces YES`: each face labelled, to see which is which and its way up.
private struct FaceLabel: View {
    let face: CoverBoxEntity.Face

    var body: some View {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange]
        ZStack(alignment: .topLeading) {
            colors[face.rawValue]
            Text("\(face)".uppercased() + " ↑")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(.white)
                .padding(4)
        }
    }
}
#endif
