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
    @State private var fastForward = false
    @State private var saveBusy = false

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
        .toolbar(.hidden, for: .tabBar)
        .task { await boot() }
        .onDisappear {
            core?.stop()
            core = nil
        }
        .alert("Play", isPresented: $showError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Portrait (screen full width; all controls below)

    private var portraitBody: some View {
        VStack(spacing: 0) {
            // Edge-to-edge game bezel; nav title already names the game.
            GeometryReader { geo in
                gameScreen
                    .frame(width: geo.size.width, height: geo.size.width / screenAspect)
            }
            .aspectRatio(screenAspect, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .layoutPriority(1)

            VStack(spacing: 8) {
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
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Landscape (PSP-style: controls left | screen | controls right)

    private var landscapeBody: some View {
        HStack(alignment: .center, spacing: 0) {
            // Left thumb zone
            Group {
                if game.systemID == .gba {
                    GBAPadLeftColumn(held: gbaHeld, setHeld: setGBAHeld)
                } else if game.systemID == .psp {
                    PSPPadLeftColumn(held: pspHeld, setHeld: setPSPHeld)
                } else {
                    Color.clear.frame(width: 8)
                }
            }
            .padding(.leading, 6)

            // Screen takes remaining width; chrome under it stays in the center column.
            VStack(spacing: 4) {
                GeometryReader { geo in
                    // Prefer the largest aspect-fit rect that fits the center column.
                    // Ternaries only — ViewBuilder rejects if/else used to bind lets.
                    let maxW = geo.size.width
                    let maxH = geo.size.height
                    let hFromWidth = maxW / screenAspect
                    let wFromHeight = maxH * screenAspect
                    let fitsByWidth = hFromWidth <= maxH
                    let drawnW = fitsByWidth ? maxW : wFromHeight
                    let drawnH = fitsByWidth ? hFromWidth : maxH
                    gameScreen
                        .frame(width: drawnW, height: drawnH)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

                if game.systemID == .gba {
                    GBAPadStartSelectRow(held: gbaHeld, setHeld: setGBAHeld)
                } else if game.systemID == .psp {
                    PSPPadStartSelectRow(held: pspHeld, setHeld: setPSPHeld)
                }

                transportBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 4)

            // Right thumb zone
            Group {
                if game.systemID == .gba {
                    GBAPadRightColumn(held: gbaHeld, setHeld: setGBAHeld)
                } else if game.systemID == .psp {
                    PSPPadRightColumn(held: pspHeld, setHeld: setPSPHeld)
                } else {
                    Color.clear.frame(width: 8)
                }
            }
            .padding(.trailing, 6)
        }
        .padding(.vertical, 4)
    }

    private var gameScreen: some View {
        ZStack {
            Rectangle()
                .fill(.black)
            if let frameImage {
                Image(decorative: frameImage, scale: 1, orientation: .up)
                    .resizable()
                    .interpolation(.none)
                    // Fill the bezel; SoftGPU frames are already the display aspect.
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    private var transportBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    core?.pause()
                    statusLine = "Paused"
                } label: {
                    Image(systemName: "pause.fill")
                }
                .accessibilityLabel("Pause")

                Button {
                    core?.resume()
                    if sawFirstFrame { statusLine = "Running" }
                } label: {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("Resume")

                Button {
                    core?.stop()
                    dismiss()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .accessibilityLabel("Stop")
            }

            HStack(spacing: 10) {
                Button {
                    Task { await quickSave() }
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .accessibilityLabel("Quick Save")
                .disabled(saveBusy || !(core?.supportsSaveState ?? false))

                Button {
                    Task { await quickLoad() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Quick Load")
                .disabled(
                    saveBusy
                        || !(core?.supportsSaveState ?? false)
                        || !SaveStateStore.quickSaveExists(system: game.systemID, gameID: game.id)
                )

                if core?.supportsFastForward == true {
                    Button {
                        fastForward.toggle()
                        core?.setFastForward(fastForward)
                        if sawFirstFrame { statusLine = "Running" }
                    } label: {
                        Image(systemName: fastForward ? "forward.fill" : "forward")
                    }
                    .accessibilityLabel(fastForward ? "Fast-forward on" : "Fast-forward off")
                    .tint(fastForward ? .orange : nil)
                }
            }

            if core?.supportsSaveState != true {
                Text("Save states not available for this core yet.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    @MainActor
    private func quickSave() async {
        guard let core, core.supportsSaveState else {
            statusLine = "Save states not available"
            return
        }
        saveBusy = true
        defer { saveBusy = false }
        core.pause()
        do {
            let url = try SaveStateStore.quickSaveURL(system: game.systemID, gameID: game.id)
            try await core.saveState(to: url)
            core.resume()
            statusLine = "Quick save OK"
        } catch {
            statusLine = "Quick save failed"
            errorMessage = error.localizedDescription
            showError = true
            core.resume()
        }
    }

    @MainActor
    private func quickLoad() async {
        guard let core, core.supportsSaveState else {
            statusLine = "Save states not available"
            return
        }
        saveBusy = true
        defer { saveBusy = false }
        core.pause()
        do {
            let url = try SaveStateStore.quickSaveURL(system: game.systemID, gameID: game.id)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw EmulatorCoreError.romLoadFailed("No quick save yet")
            }
            try await core.loadState(from: url)
            core.resume()
            statusLine = "Quick load OK"
        } catch {
            statusLine = "Quick load failed"
            errorMessage = error.localizedDescription
            showError = true
            core.resume()
        }
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
