import SwiftUI
import RetroPlayCore

/// Play shell for a library game. GBA uses MGBACore; other systems stay stubs until later milestones.
@available(iOS 18.0, *)
public struct PlayView: View {
    let game: LibraryGame
    let romURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("retroplay.appearance") private var appearanceRaw = AppearancePreference.dark.rawValue
    @State private var core: (any EmulatorCore)?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var statusLine = "Starting…"
    @State private var held: GBAInput = []
    @State private var frameImage: CGImage?
    @State private var frameSink = FrameSinkStore()

    public init(game: LibraryGame, romURL: URL) {
        self.game = game
        self.romURL = romURL
    }

    private var isLandscapeCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    public var body: some View {
        Group {
            if isLandscapeCompactHeight {
                landscapeBody
            } else {
                portraitBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RetroPlayTheme.canvas(for: colorScheme).ignoresSafeArea())
        .preferredColorScheme((AppearancePreference(rawValue: appearanceRaw) ?? .dark).colorScheme)
                .navigationTitle(game.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RetroPlayTheme.section(for: colorScheme), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(colorScheme, for: .navigationBar)
        .task { await boot() }
        .onDisappear {
            core?.stop()
            core = nil
        }
        .alert("Could not play", isPresented: $showError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Portrait (Game Boy–style: screen above, pad below)

    private var portraitBody: some View {
        VStack(spacing: 12) {
            Text("\(game.systemID.displayName) · \(game.systemID.defaultCoreName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            gameScreen
                .aspectRatio(3 / 2, contentMode: .fit)
                .frame(maxHeight: 320)

            if game.systemID == .gba {
                ConsolePadHost(
                    systemID: .gba,
                    orientation: .portrait,
                    held: held,
                    setHeld: setHeld
                )
            }

            transportBar
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Landscape (GBA slab–style: D-pad left, face right)

    private var landscapeBody: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if game.systemID == .gba {
                    GBAPadLeftColumn(held: held, setHeld: setHeld)
                }

                gameScreen
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if game.systemID == .gba {
                    GBAPadRightColumn(held: held, setHeld: setHeld)
                }
            }
            .padding(.horizontal, 8)

            if game.systemID == .gba {
                GBAPadStartSelectRow(held: held, setHeld: setHeld)
            }

            transportBar
        }
        .padding(.bottom, 4)
    }

    private var gameScreen: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
            if let frameImage {
                Image(decorative: frameImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            } else {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private var transportBar: some View {
        HStack(spacing: 12) {
            Button("Pause") { core?.pause(); statusLine = "Paused" }
            Button("Resume") { core?.resume(); statusLine = "Running" }
            Button("Stop") {
                core?.stop()
                dismiss()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @MainActor
    private func setHeld(_ bit: GBAInput, _ down: Bool) {
        if down { held.insert(bit) } else { held.remove(bit) }
        // Must hit MGBACore via protocol requirement (not extension-only) for dynamic dispatch.
        core?.setGBAInput(held)
    }

    private func boot() async {
        let instance = CoreFactory.makeCore(for: game.systemID)
        frameSink.onFrame = { image in
            frameImage = image
            statusLine = "Running"
        }
        if let mgba = instance as? MGBACore {
            mgba.attachFrameSink(frameSink)
        } else if let psp = instance as? PPSSPPCore {
            psp.attachFrameSink(frameSink)
        }
        core = instance
        do {
            try await instance.loadROM(at: romURL)
            instance.start()
            statusLine = "Running"
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Failed"
            showError = true
        }
    }
}
