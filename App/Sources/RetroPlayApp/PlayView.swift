import SwiftUI
import RetroPlayCore

/// Play shell for a library game. GBA/PSP playable; N64/NDS hosts + pads scaffolded (native pending).
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
    @State private var n64Held: N64Input = []
    @State private var n64Stick: N64AnalogStick = .zero
    @State private var ndsHeld: NDSInput = []
    @State private var ndsTouch: NDSTouch = .idle
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

    /// GBA ~3:2; PSP 480×272; N64 4:3; NDS stacked screens stub 256×384.
    private var screenAspect: CGFloat {
        switch game.systemID {
        case .psp: return 480.0 / 272.0
        case .n64: return 4.0 / 3.0
        case .nds: return 256.0 / 384.0
        case .gba: return 3.0 / 2.0
        }
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
                ConsolePadHost(
                    systemID: game.systemID,
                    orientation: .portrait,
                    gbaHeld: gbaHeld,
                    setGBAHeld: setGBAHeld,
                    pspHeld: pspHeld,
                    setPSPHeld: setPSPHeld,
                    n64Held: n64Held,
                    setN64Held: setN64Held,
                    n64Stick: n64Stick,
                    setN64Stick: setN64Stick,
                    ndsHeld: ndsHeld,
                    setNDSHeld: setNDSHeld,
                    onNDSTouch: setNDSTouch
                )
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
                } else if game.systemID == .n64 {
                    N64PadLeftColumn(held: n64Held, stick: n64Stick, setHeld: setN64Held, setStick: setN64Stick)
                } else if game.systemID == .nds {
                    NDSPadLeftColumn(held: ndsHeld, setHeld: setNDSHeld)
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
                } else if game.systemID == .n64 {
                    N64HoldPadCapsule(title: "Start", bit: .start, isHeld: n64Held.contains(.start), setHeld: setN64Held)
                } else if game.systemID == .nds {
                    NDSPadStartSelectRow(held: ndsHeld, setHeld: setNDSHeld)
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
                } else if game.systemID == .n64 {
                    N64PadRightColumn(held: n64Held, setHeld: setN64Held)
                } else if game.systemID == .nds {
                    NDSPadRightColumn(held: ndsHeld, setHeld: setNDSHeld)
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
                Button("Save") {
                    Task { await quickSave() }
                }
                .disabled(saveBusy || !(core?.supportsSaveState ?? false))

                Button("Load") {
                    Task { await quickLoad() }
                }
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

    @MainActor
    private func setN64Held(_ bit: N64Input, _ down: Bool) {
        if down { n64Held.insert(bit) } else { n64Held.remove(bit) }
        core?.setN64Input(n64Held, stick: n64Stick)
    }

    @MainActor
    private func setN64Stick(_ stick: N64AnalogStick) {
        n64Stick = stick
        core?.setN64Input(n64Held, stick: n64Stick)
    }

    @MainActor
    private func setNDSHeld(_ bit: NDSInput, _ down: Bool) {
        if down { ndsHeld.insert(bit) } else { ndsHeld.remove(bit) }
        core?.setNDSInput(ndsHeld, touch: ndsTouch)
    }

    @MainActor
    private func setNDSTouch(_ touch: NDSTouch) {
        ndsTouch = touch
        core?.setNDSInput(ndsHeld, touch: ndsTouch)
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
            if ProcessInfo.processInfo.arguments.contains("-RetroPlaySmokeSystem") || UserDefaults.standard.object(forKey: "RetroPlaySmokeSystem") != nil {
                NSLog("RP_SMOKE play boot ok system=%@ rom=%@", game.systemID.rawValue, romURL.lastPathComponent)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    switch game.systemID {
                    case .nds:
                        // Firmware menu often needs Start; then A.
                        for bit in [NDSInput.start, NDSInput.a] {
                            var held: NDSInput = bit
                            ndsHeld = held
                            core?.setNDSInput(held, touch: .idle)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            held = []
                            ndsHeld = held
                            core?.setNDSInput(held, touch: .idle)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                        }
                        NSLog("RP_SMOKE nds pulsed Start+A sawFirstFrame=%d", sawFirstFrame ? 1 : 0)
                    case .n64:
                        // Angrylion on Simulator can take several seconds for first VI.
                        for _ in 0..<40 {
                            if sawFirstFrame { break }
                            try? await Task.sleep(nanoseconds: 250_000_000)
                        }
                        NSLog("RP_SMOKE n64 pre-pulse sawFirstFrame=%d", sawFirstFrame ? 1 : 0)
                        for bit in [N64Input.start, N64Input.a] {
                            var held: N64Input = bit
                            n64Held = held
                            core?.setN64Input(held, stick: .zero)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                            held = []
                            n64Held = held
                            core?.setN64Input(held, stick: .zero)
                            try? await Task.sleep(nanoseconds: 400_000_000)
                        }
                        NSLog("RP_SMOKE n64 pulsed Start+A sawFirstFrame=%d", sawFirstFrame ? 1 : 0)
                    default:
                        break
                    }
                }
            }
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
