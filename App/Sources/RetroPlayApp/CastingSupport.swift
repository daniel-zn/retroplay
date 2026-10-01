// SPDX-License-Identifier: GPL-3.0-or-later
import AVKit
import RetroPlayCore
import SwiftUI
import UIKit

/// Shared handoff between the interactive phone scene and noninteractive external-display scenes.
@MainActor
public final class CastingCoordinator: ObservableObject {
    public static let shared = CastingCoordinator()

    /// The running game's frames. The external scene draws them with its own display link.
    @Published public private(set) var video: VideoFrameStore?
    @Published public private(set) var gameTitle: String?
    @Published public private(set) var screenAspect: CGFloat = 4.0 / 3.0
    @Published public private(set) var isExternalDisplayConnected = false

    private var externalSceneIDs: Set<String> = []
    private var screenObservers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        screenObservers.append(center.addObserver(
            forName: UIScreen.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clearExternalDisplayTracking()
            }
        })
    }

    public func externalDisplayConnected(sceneID: String) {
        externalSceneIDs.insert(sceneID)
        isExternalDisplayConnected = !externalSceneIDs.isEmpty
    }

    public func externalDisplayDisconnected(sceneID: String) {
        externalSceneIDs.remove(sceneID)
        isExternalDisplayConnected = !externalSceneIDs.isEmpty
    }

    /// Clears stale AirPlay bookkeeping when accessory disconnect callbacks are missed.
    public func reconcileExternalDisplayConnectivity(
        connectedScreenCount: Int,
        usesLegacyScreenCount: Bool = true
    ) {
        guard ExternalDisplayConnectivity.shouldClearStaleConnection(
            trackedSceneCount: externalSceneIDs.count,
            connectedScreenCount: connectedScreenCount,
            usesLegacyScreenCount: usesLegacyScreenCount
        ) else { return }
        externalSceneIDs.removeAll()
        isExternalDisplayConnected = false
    }

    func beginGame(title: String, aspect: CGFloat) {
        // A missed disconnect callback would leave the phone showing "Playing on AirPlay"
        // with no picture anywhere; recount the external-display scenes that really exist.
        let externalScenes = UIApplication.shared.connectedScenes
            .filter { $0.session.role == .windowExternalDisplayNonInteractive }
            .count
        reconcileExternalDisplayConnectivity(connectedScreenCount: externalScenes + 1)
        gameTitle = title
        screenAspect = aspect
        video = nil
    }

    /// Shows this core's frames on the external display (nil while the game reboots).
    func attach(video: VideoFrameStore?) {
        self.video = video
    }

    /// Keeps display tracking: the external scene stays connected between games.
    func endGame() {
        gameTitle = nil
        video = nil
    }

    private func clearExternalDisplayTracking() {
        externalSceneIDs.removeAll()
        isExternalDisplayConnected = false
    }
}

/// Full-screen, noninteractive scene shown on an AirPlay/external display.
@available(iOS 18.0, *)
public struct ExternalGameDisplayView: View {
    @ObservedObject private var casting = CastingCoordinator.shared
    @AppStorage(PlaySettingsKey.smoothScreen) private var smoothScreen = false

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let video = casting.video {
                GameScreenView(store: video, smoothing: smoothScreen)
                    .aspectRatio(casting.screenAspect, contentMode: .fit)
                    .accessibilityElement()
                    .accessibilityLabel(casting.gameTitle.map { "Game video for \($0)" } ?? "Game video")
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "airplayvideo")
                        .font(.system(size: 42))
                        .accessibilityHidden(true)
                    Text(casting.gameTitle ?? "RetroPlay")
                    Text(casting.gameTitle == nil ? "Choose a game on iPhone" : "Waiting for video…")
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    casting.gameTitle.map { "RetroPlay, \($0), waiting for video" }
                        ?? "RetroPlay, choose a game on iPhone"
                )
            }
        }
        .environment(\.font, RetroPlayFont.body)
    }
}

@available(iOS 18.0, *)
struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.activeTintColor = UIColor(RetroPlayTheme.accent)
        picker.tintColor = .white
        picker.accessibilityLabel = "AirPlay"
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        picker.activeTintColor = UIColor(RetroPlayTheme.accent)
        picker.tintColor = .white
    }
}

@available(iOS 18.0, *)
public extension View {
    /// iOS 27 requires an explicitly registered scene accessory before it will
    /// connect a noninteractive external-display scene. Earlier releases use
    /// the external-display role declared in the app's scene manifest.
    @ViewBuilder
    func retroPlayExternalDisplayAccessory() -> some View {
        if #available(iOS 27.0, *) {
            sceneAccessory {
                ExternalNonInteractiveAccessory {
                    ExternalGameDisplayView()
                        .onAppear {
                            CastingCoordinator.shared.externalDisplayConnected(
                                sceneID: "swiftui-external-accessory"
                            )
                        }
                        .onDisappear {
                            CastingCoordinator.shared.externalDisplayDisconnected(
                                sceneID: "swiftui-external-accessory"
                            )
                        }
                }
            }
        } else {
            self
        }
    }
}
