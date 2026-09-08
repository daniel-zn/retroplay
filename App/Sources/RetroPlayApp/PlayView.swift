import SwiftUI
import RetroPlayCore

/// Play shell for a library game. GBA and PSP use native cores; other systems stay stubs.
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
    @State private var gbaHeld: GBAInput = []
    @State private var pspHeld: PSPInput = []
    @State private var frameImage: CGImage?
    @State private var frameSink = FrameSinkStore()
    @State private var sawFirstFrame = false

    public init(game: LibraryGame, romURL: URL) {
        self.game = game
        self.romURL = romURL
    }

    private var isLandscapeCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    /// GBA ~3:2; PSP native 480×272 ≈ 16:9.
    private var screenAspect: CGFloat {
        game.systemID == .psp ? (480.0 / 272.0) : (3.0 / 2.0)
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

    // MARK: - Portrait

    private var portraitBody: some View {
        VStack(spacing: 12) {
            Text("\(game.systemID.displayName) · \(game.systemID.defaultCoreName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            gameScreen
                .aspectRatio(screenAspect, contentMode: .fit)
                .frame(maxHeight: game.systemID == .psp ? 280 : 320)

            if game.systemID == .gba || game.systemID == .psp {
                ConsolePadHost(
                    systemID: game.systemID,
                    orientation: .portrait,
                    gbaHeld: gbaHeld,
                    setGBAHeld: setGBAHeld,
                    pspHeld: pspHeld,
                    setPSPHeld: setPSPHeld
                )
            }

            transportBar
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Landscape

    private var landscapeBody: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                if game.systemID == .gba {
                    GBAPadLeftColumn(held: gbaHeld, setHeld: setGBAHeld)
                } else if game.systemID == .psp {
                    PSPPadLeftColumn(held: pspHeld, setHeld: setPSPHeld)
                }

                gameScreen
                    .aspectRatio(screenAspect, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if game.systemID == .gba {
                    GBAPadRightColumn(held: gbaHeld, setHeld: setGBAHeld)
                } else if game.systemID == .psp {
                    PSPPadRightColumn(held: pspHeld, setHeld: setPSPHeld)
                }
            }
            .padding(.horizontal, 8)

            if game.systemID == .gba {
                GBAPadStartSelectRow(held: gbaHeld, setHeld: setGBAHeld)
            } else if game.systemID == .psp {
                PSPPadStartSelectRow(held: pspHeld, setHeld: setPSPHeld)
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
            Button("Resume") {
                core?.resume()
                if sawFirstFrame { statusLine = "Running" }
            }
            Button("Stop") {
                core?.stop()
                dismiss()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @MainActor
    private func setGBAHeld(_ bit: GBAInput, _ down: Bool) {
        if down { gbaHeld.insert(bit) } else { gbaHeld.remove(bit) }
        core?.setGBAInput(gbaHeld)
    }

    @MainActor
    private func setPSPHeld(_ bit: PSPInput, _ down: Bool) {
        if down { pspHeld.insert(bit) } else { pspHeld.remove(bit) }
        core?.setPSPInput(pspHeld)
    }

    private func boot() async {
        let instance = CoreFactory.makeCore(for: game.systemID)
        sawFirstFrame = false
        frameSink.onFrame = { image in
            frameImage = image
            sawFirstFrame = true
            statusLine = "Running"
        }
        instance.attachFrameSink(frameSink)
        core = instance
        do {
            try await instance.loadROM(at: romURL)
            instance.start()
            statusLine = "Waiting for first frame…"
            let system = game.systemID
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !sawFirstFrame, frameImage == nil else { return }
                let message: String
                if system == .psp {
                    message = """
                    PPSSPP produced no video frames after 10 seconds. \
                    The ISO may have loaded, but the display buffer never became readable \
                    (common on Simulator if MemMap/graphics init is incomplete). \
                    Try a physical device, or check the console for MemMap / GetOutputFramebuffer errors.
                    """
                } else {
                    message = "No video frames after 10 seconds. The core may be stuck or not emitting frames."
                }
                statusLine = "No frames"
                errorMessage = message
                showError = true
            }
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Failed"
            showError = true
        }
    }
}
