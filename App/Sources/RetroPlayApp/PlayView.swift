// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UIKit
import RetroPlayCore

/// `@AppStorage` keys shared by Play and Settings.
enum PlaySettingsKey {
    static let sound = "retroplay.sound"
    static let respectSilentSwitch = "retroplay.respectSilentSwitch"
    static let haptics = "retroplay.haptics"
    static let padOpacity = "retroplay.padOpacity"
    static let smoothScreen = "retroplay.smoothScreen"
    static let touchWithController = "retroplay.touchWithController"
    /// Per system: landscape screen fills the height under the pad instead of fitting
    /// between the control columns.
    static func landscapeFill(_ system: SystemID) -> String {
        "retroplay.landscapeFill.\(system.rawValue)"
    }
}

/// Full-screen play: game screen + multi-touch pad (portrait: pad below; landscape:
/// pad in the thumb zones over the screen edges), physical controllers, and a pause menu.
@available(iOS 18.0, *)
public struct PlayView: View {
    let game: LibraryGame
    let romURL: URL

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(PlaySettingsKey.sound) private var soundOn = true
    @AppStorage(PlaySettingsKey.respectSilentSwitch) private var respectSilentSwitch = false
    @AppStorage(PlaySettingsKey.haptics) private var haptics = true
    @AppStorage(PlaySettingsKey.padOpacity) private var padOpacity = 0.75
    @AppStorage(PlaySettingsKey.smoothScreen) private var smoothScreen = false
    @AppStorage(PlaySettingsKey.touchWithController) private var touchWithController = false
    @AppStorage private var landscapeFill: Bool
    /// The display's corner radius (0 until read, or before iOS 26).
    @State private var displayCorner: CGFloat = 0

    @State private var core: (any EmulatorCore)?
    @State private var input: PadInputModel
    @State private var controllers = GameControllerInput()
    @State private var phase: Phase = .loading
    @State private var menuOpen = false
    @State private var fastForward = false
    @State private var busy = false
    @State private var toast: Toast?
    @State private var sawFirstFrame = false
    @State private var slowStartHint = false
    @State private var saveEntries: [SaveStateStore.Entry] = []
    @State private var loadCoordinator = PlayLoadActionCoordinator()
    /// Bumped on quit / restart so in-flight boot or load work abandons.
    @State private var sessionToken = PlaySessionToken(rawValue: 0)
    @State private var didLeave = false
    /// Quit is running its exit save: the menu is locked and shows "Saving…".
    @State private var leaving = false
    /// N64 resumes only after its first frame. Until that load returns, the running
    /// core is still showing the intro, so no auto-save may overwrite slot 0 with it.
    @State private var autoResumePending = false
    @State private var alertMessage: String?
    @State private var showSaveImporter = false
    @State private var pendingImport: PendingSaveImport?
    @State private var saveImportError: String?
    @ObservedObject private var casting = CastingCoordinator.shared
    private let saveImporter = SaveGameImporter()

    private enum Phase: Equatable {
        case loading
        case running
        case failed(String)
    }

    private struct Toast: Equatable {
        let id = UUID()
        let text: String
    }

    /// A battery save waiting for "Replace?" confirmation (security scope still open).
    private struct PendingSaveImport {
        let url: URL
        let plan: SaveGameImportPlan
        let securityScoped: Bool
    }

    public init(game: LibraryGame, romURL: URL) {
        self.game = game
        self.romURL = romURL
        _input = State(initialValue: PadInputModel(system: game.systemID))
        // PSP's 16:9 screen would shrink too far between the columns, so it fills by default.
        _landscapeFill = AppStorage(
            // PSP and GBA: the picture at full size, the controls over it.
            wrappedValue: [.psp, .gba].contains(game.systemID),
            PlaySettingsKey.landscapeFill(game.systemID)
        )
    }

    private var system: SystemID { game.systemID }

    private var showTouchControls: Bool {
        !controllers.hasController || touchWithController
    }

    /// Live foreground check for the async boot path. `scenePhase` read there comes from
    /// the view value captured when the task started, so after a long load it can be stale
    /// (e.g. still `.inactive` from app launch) and leave a running game paused for good.
    private var isAppActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    public var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Color.black
                if landscape {
                    landscapeLayout(size: geo.size, safeArea: geo.safeAreaInsets)
                } else {
                    portraitLayout(size: geo.size, bottomInset: geo.safeAreaInsets.bottom)
                }
                statusOverlay
            }
            // A finger held through a rotation keeps its old-layout origin (stick, D-pad);
            // drop it so nothing stays pinned until the finger lifts.
            .onChange(of: landscape) { input.releaseAll() }
            .coordinateSpace(.named(PadSurface.space))
            .overlayPreferenceValue(PadRegionKey.self) { regions in
                // Not over the loading / failed card, where the pad is not live yet.
                if !menuOpen && phase == .running {
                    PadTouchSurface(
                        regions: regions,
                        hapticsEnabled: haptics,
                        releaseCount: input.releaseCount
                    ) { output in
                        input.applyTouch(output)
                    }
                }
            }
            .overlay {
                if menuOpen {
                    menuOverlay
                }
            }
            // Above the menu: most toasts ("State saved", load results) come from it.
            .overlay {
                if let toast {
                    toastView(toast.text)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(toast.id)
                }
            }
        }
        .environment(input)
        .background {
            DisplayCornerReader { displayCorner = $0 }
                .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // An auto-hidden home indicator comes back on every touch, which during play is
        // constant. Deferring only the bottom edge keeps it hidden (a first swipe up shows
        // it, a second goes home) while Control Center and notifications stay one swipe.
        .defersSystemGestures(on: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // Also disables the edge swipe-back that used to fire from the D-pad.
        .navigationBarBackButtonHidden(true)
        .task {
            casting.beginGame(title: game.displayName, aspect: CGFloat(system.screenAspect))
            GameModeSession.begin()
            startControllers()
            refreshSaveEntries()
            await boot()
        }
        .onDisappear {
            loadCoordinator.cancel()
            casting.endGame()
            GameModeSession.end()
            Task { await leave(autoSave: true) }
        }
        .fileImporter(
            isPresented: $showSaveImporter,
            allowedContentTypes: SaveImportContentTypes.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handleSaveImportSelection(result)
        }
        // Only the buttons dismiss these; each action owns its cleanup, so the
        // setters stay no-ops (a cancel here would end file access before Replace).
        .retroPlayAlert(
            "Replace Save?",
            message: pendingImport.map {
                "Replace the existing save \($0.plan.destinationURL.lastPathComponent) with \($0.plan.sourceDescription)?"
            } ?? "",
            isPresented: Binding(get: { pendingImport != nil }, set: { _ in }),
            actions: [
                .cancel("Cancel") { cancelPendingImport() },
                .destructive("Replace") {
                    guard let pending = pendingImport else { return }
                    pendingImport = nil
                    commitSaveImport(pending, overwrite: true)
                }
            ]
        )
        .retroPlayAlert(
            "Import Save",
            message: saveImportError ?? "",
            isPresented: Binding(get: { saveImportError != nil }, set: { _ in }),
            actions: [.cancel("OK") { saveImportError = nil }]
        )
        .retroPlayAlert(
            "Play",
            message: alertMessage ?? "",
            isPresented: Binding(get: { alertMessage != nil }, set: { _ in }),
            actions: [.cancel("OK") { alertMessage = nil }]
        )
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
        .onChange(of: menuOpen) { _, open in
            if open {
                input.releaseAll()
                core?.pause()
            } else if scenePhase == .active {
                core?.resume()
            }
        }
        .onChange(of: soundOn) { _, _ in applyAudioSettings() }
        .onChange(of: respectSilentSwitch) { _, _ in applyAudioSettings() }
        .animation(.easeOut(duration: 0.2), value: menuOpen)
        .animation(.easeOut(duration: 0.2), value: toast)
    }

    // MARK: - Layouts

    private static let portraitBarHeight: CGFloat = 52
    /// The backing's inset from the screen's sides, and from its bottom edge.
    private static let backingSideInset: CGFloat = 6
    private static let backingBottomInset: CGFloat = 12

    /// Portrait game screen height: full width, but DS screens are tall, so they're capped
    /// to leave the pad room for full-size controls.
    private static func portraitScreenHeight(_ system: SystemID, in size: CGSize) -> CGFloat {
        let maxScreenHeight = size.height * (system == .nds ? 0.54 : 0.5)
        return min(size.width / CGFloat(system.screenAspect), maxScreenHeight)
    }

    /// The controls' portrait scale on this phone, worked out from the landscape geometry
    /// (Face ID iPhones: about 59 pt top safe area in portrait; the pad runs through the
    /// home-indicator strip to the bottom edge).
    private static func portraitScale(_ system: SystemID, landscape size: CGSize, safeArea: EdgeInsets) -> CGFloat {
        let portrait = CGSize(
            width: size.height + safeArea.top + safeArea.bottom,
            height: size.width + safeArea.leading + safeArea.trailing - 59
        )
        // Less the gaps above and below the backing (`portraitLayout`).
        let padHeight = portrait.height - portraitScreenHeight(system, in: portrait) - portraitBarHeight
            - 6 - backingBottomInset
        return ConsolePadPortrait.scale(for: system, in: CGSize(width: portrait.width, height: padHeight))
    }

    private func portraitLayout(size: CGSize, bottomInset: CGFloat) -> some View {
        let aspect = CGFloat(system.screenAspect)
        let screenHeight = Self.portraitScreenHeight(system, in: size)
        let screenWidth = screenHeight * aspect
        let barHeight = Self.portraitBarHeight
        // The backing runs to the bottom edge (through the home-indicator strip, hidden while
        // playing); fast-forward / pause / sound sit at its foot, below every game control.
        let backingHeight = max(0, size.height + bottomInset - screenHeight - 6 - Self.backingBottomInset)
        let padHeight = max(0, backingHeight - barHeight)
        // Concentric with the screen's corners; 0 when the display's radius isn't known.
        let backingRadius = displayCorner > 0 ? displayCorner - Self.backingSideInset : 0

        return VStack(spacing: 6) {
            screen
                .frame(width: screenWidth, height: screenHeight)
                .frame(maxWidth: .infinity)
            VStack(spacing: 0) {
                if showTouchControls {
                    ConsolePadPortrait(system: system, size: CGSize(width: size.width, height: padHeight))
                        // Button letters mirror the hardware; past xxxLarge they overflow the pad.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(height: padHeight)
                        // Shoulders sit `ConsolePadPortrait.edgeInset` in from the backing's top
                        // and side, so their outer corner is that much tighter than the backing's.
                        .environment(\.padOuterCornerRadius,
                                     backingRadius > 0 ? backingRadius - ConsolePadPortrait.edgeInset : nil)
                } else {
                    controllerConnectedNote
                        .frame(maxHeight: .infinity)
                }
                // Own row, so the buttons never sit inside a pad control's touch area; well
                // clear of the backing's rounded bottom.
                quickButtons()
                    .frame(height: barHeight, alignment: .top)
            }
            // Full width, the backing inset 6 pt inside it: centred on every iPhone width.
            .frame(width: size.width, height: backingHeight)
            .background {
                PadBacking(fill: system.padChassis, stroke: system.padChassisStroke, radius: backingRadius)
                    .padding(.horizontal, Self.backingSideInset)
            }
            .padding(.bottom, Self.backingBottomInset)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea(edges: .bottom)
    }

    private func landscapeLayout(size: CGSize, safeArea: EdgeInsets) -> some View {
        let aspect = CGFloat(system.screenAspect)
        // The controls also use the home-indicator strip (it's hidden while playing).
        let sizing = ConsolePad.landscapeLayout(
            for: system,
            in: CGSize(width: size.width, height: size.height + safeArea.bottom),
            portraitScale: Self.portraitScale(system, landscape: size, safeArea: safeArea)
        )
        let scale = sizing.scale
        let pad = ConsolePad(system: system, scale: scale, large: sizing.large, landscape: true)
        let edgeInset: CGFloat = 8
        // Fit: the screen sits between the two control columns so no control covers the
        // game. Fill: it runs the full height (through the home-indicator strip) under the pad.
        let fit = showTouchControls && !landscapeFill
        let availableWidth = fit
            ? size.width - 2 * (pad.landscapeColumnWidth + edgeInset + 4)
            : size.width
        let fullHeight = size.height + safeArea.top + safeArea.bottom
        let screenHeight = min(fit ? size.height : fullHeight, max(0, availableWidth) / aspect)
        let screenWidth = screenHeight * aspect
        let chromeOpacity = max(padOpacity, 0.6)

        return ZStack {
            screen
                .frame(width: screenWidth, height: screenHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(edges: fit ? [] : .vertical)
            if showTouchControls {
                // The thumb controls live in the side columns; fast-forward / pause / sound
                // are the lowest control on the right; SELECT / START sit side by side at the
                // bottom centre.
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Centred over the D-pad / stick below.
                        pad.leftShoulders
                            .opacity(padOpacity)
                            .frame(width: pad.landscapeColumnWidth)
                        Spacer(minLength: 6)
                        pad.leftMain
                            .opacity(padOpacity)
                        Spacer(minLength: 0)
                            .frame(maxHeight: 8)
                    }
                    .frame(width: pad.landscapeColumnWidth, alignment: .leading)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        // Centred over the face buttons below.
                        pad.rightShoulders
                            .opacity(padOpacity)
                            .frame(width: pad.landscapeColumnWidth)
                        Spacer(minLength: 6)
                        pad.rightMain
                            .opacity(padOpacity)
                        // Beyond the face buttons' 14 pt touch slop, so taps reach the buttons.
                        quickButtons(maxWidth: pad.landscapeColumnWidth)
                            .frame(width: pad.landscapeColumnWidth)
                            .opacity(chromeOpacity)
                            .padding(.top, 18)
                    }
                    .frame(width: pad.landscapeColumnWidth, alignment: .trailing)
                }
                .padding(.horizontal, edgeInset)
                .padding(.vertical, 6)
                .ignoresSafeArea(edges: .bottom)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                // Over the game every control is see-through, light ones included.
                .environment(\.padGlass, true)
                pad.center
                    .opacity(padOpacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .environment(\.padGlass, true)
            } else {
                VStack(spacing: 8) {
                    controllerConnectedNote
                    quickButtons()
                        .opacity(chromeOpacity)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 4)
            }
        }
    }

    private var screen: some View {
        ZStack {
            if let core {
                if PhonePlaybackPresentation.resolve(
                    hasActiveGame: true,
                    hasExternalDisplay: casting.isExternalDisplayConnected
                ) == .castingRemote {
                    castingRemoteNote
                } else {
                    GameScreenView(store: core.video, smoothing: smoothScreen)
                }
            } else {
                Color.black
            }
            if system == .nds {
                // Bottom half of the stacked frame is the DS Touch Screen: touch it directly.
                VStack(spacing: 0) {
                    Color.clear
                    Color.clear
                        .padRegion("nds.touchscreen", .touchscreen)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(game.displayName) screen")
    }

    /// Fast-forward, pause and sound: one size, centred, reachable without covering the game.
    /// `maxWidth` is the room they get (a landscape control column); they shrink to fit it.
    private func quickButtons(maxWidth: CGFloat = .infinity) -> some View {
        let spacing: CGFloat = 10
        let width = min(48, (maxWidth - 2 * spacing) / 3)
        return HStack(spacing: spacing) {
            // On: inverted (white fill, dark glyph).
            chromeButton("forward.fill", tint: fastForward ? .black : .white, width: width,
                         fill: fastForward ? .white : nil) {
                setFastForward(!fastForward)
            }
            .accessibilityLabel(fastForward ? "Fast forward on" : "Fast forward off")
            chromeButton("pause.fill", tint: .white, width: width) {
                menuOpen = true
            }
            .accessibilityLabel("Pause menu")
            chromeButton(soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill", tint: .white, width: width) {
                soundOn.toggle()
            }
            .accessibilityLabel(soundOn ? "Sound on" : "Sound off")
        }
        .frame(maxWidth: .infinity)
        .disabled(core == nil || phase != .running)
    }

    private func chromeButton(
        _ symbol: String,
        tint: Color,
        width: CGFloat,
        fill: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ChromeButtonLabel(symbol: symbol, tint: tint, width: width, fill: fill)
        }
        .buttonStyle(.plain)
    }

    private var castingRemoteNote: some View {
        VStack(spacing: 8) {
            Image(systemName: "airplayvideo")
                .font(.system(size: 30))
                .foregroundStyle(RetroPlayTheme.accent)
            Text("Playing on AirPlay")
                .font(RetroPlayFont.body)
                .foregroundStyle(.white)
            Text("This iPhone is the controller.")
                .font(RetroPlayFont.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.opacity(0.06))
    }

    private var controllerConnectedNote: some View {
        Label(controllers.controllerName ?? "Controller connected", systemImage: "gamecontroller.fill")
            .font(RetroPlayFont.caption)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch phase {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text("Starting \(game.displayName)…")
                    .font(RetroPlayFont.caption)
                    .foregroundStyle(.white.opacity(0.8))
                // A slow or stuck load must not trap the player here.
                Button {
                    Task { await leave(autoSave: false) }
                } label: {
                    Text("Cancel")
                        .font(RetroPlayFont.subheadline)
                        .padding(.horizontal, 6)
                }
                .glassButton()
                .tint(.white)
                .disabled(didLeave)
                .padding(.top, 4)
            }
        case .running:
            if !sawFirstFrame && slowStartHint {
                Text("Still waiting for the first frame…")
                    .font(RetroPlayFont.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
        case .failed(let message):
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text("Couldn't start \(game.displayName)")
                    .font(RetroPlayFont.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                Text(message)
                    .font(RetroPlayFont.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                Button("Back to Library") { dismiss() }
                    .prominentGlassButton()
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding()
        }
    }

    private func toastView(_ text: String) -> some View {
        Text(text)
            .font(RetroPlayFont.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .allowsHitTesting(false)
    }

    // MARK: - Menu

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { if !leaving { menuOpen = false } }
            PlayMenuView(
                title: game.displayName,
                systemName: system.displayName,
                supportsSaveState: core?.supportsSaveState ?? false,
                saveEntries: saveEntries,
                busy: busy || leaving,
                leaving: leaving,
                hasController: controllers.hasController,
                haptics: $haptics,
                padOpacity: $padOpacity,
                smoothScreen: $smoothScreen,
                touchWithController: $touchWithController,
                landscapeFill: $landscapeFill,
                onResume: { menuOpen = false },
                onSave: { Task { await quickSave() } },
                onLoadCommand: { submitLoadCommand($0) },
                onImportSave: { showSaveImporter = true },
                onQuit: { Task { await leave(autoSave: true) } }
            )
            .padding(20)
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func setFastForward(_ enabled: Bool) {
        fastForward = enabled
        core?.setFastForward(enabled)
    }

    private func applyAudioSettings() {
        core?.setAudio(enabled: soundOn, respectSilentSwitch: respectSilentSwitch)
    }

    private func showToast(_ text: String) {
        let next = Toast(text: text)
        toast = next
        AccessibilityNotification.Announcement(text).post()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if toast == next { toast = nil }
        }
    }

    private func refreshSaveEntries() {
        saveEntries = SaveStateStore.resolvedEntries(system: system, gameID: game.id)
    }

    /// Writes to a staging file, then rotates it in as the newest of five saves.
    private func writeQuickSave(_ core: any EmulatorCore) async throws {
        let staged = try SaveStateStore.stagingSaveURL(system: system, gameID: game.id)
        do {
            try await core.saveState(to: staged)
            try SaveStateStore.commitStagedQuickSave(staged, system: system, gameID: game.id)
        } catch {
            SaveStateStore.discardPendingQuickSave(system: system, gameID: game.id)
            throw error
        }
        refreshSaveEntries()
    }

    private func quickSave() async {
        guard let core, core.supportsSaveState, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try await writeQuickSave(core)
            menuOpen = false
            showToast("State saved")
        } catch {
            showToast("Save failed: \(error.localizedDescription)")
        }
    }

    private func submitLoadCommand(_ command: PlayLoadCommand) {
        loadCoordinator.submit(command) { command, stillCurrent in
            await PlayLoadDriver.run(
                command,
                context: PlayLoadDriver.Context(
                    core: core,
                    saveBusy: busy,
                    entries: saveEntries,
                    // The menu is open, so the game is paused; loading closes the menu and resumes.
                    wasPaused: true,
                    pausedForBackground: false,
                    system: system,
                    gameID: game.id
                ),
                apply: { applyLoadEffect($0, command: command) },
                bootFresh: { await restartFromScratch() },
                shouldAbandon: { !stillCurrent() || didLeave }
            )
        }
    }

    private func applyLoadEffect(_ effect: PlayLoadDriver.Effect, command: PlayLoadCommand) {
        switch effect {
        case .status(let line):
            if line.hasPrefix("Quick load OK") || line.hasPrefix("Loaded previous") {
                menuOpen = false
            }
            showToast(line)
        case .alert(let message):
            alertMessage = message
        case .refreshEntries:
            refreshSaveEntries()
        case .setBusy(let value):
            busy = value
        }
    }

    /// Reset (Saves menu): states are already deleted; boot again without auto-resume.
    private func restartFromScratch() async {
        menuOpen = false
        await reboot(autoResume: false)
    }

    private func reboot(autoResume: Bool) async {
        sessionToken = PlaySessionLifecycle.bump(sessionToken)
        casting.attach(video: nil)
        core?.stop()
        core = nil
        autoResumePending = false
        input.releaseAll()
        fastForward = false
        sawFirstFrame = false
        slowStartHint = false
        refreshSaveEntries()
        await boot(autoResume: autoResume)
    }

    // MARK: - Battery save import

    private func handleSaveImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            saveImportError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            do {
                let plan = try saveImporter.planImport(from: url, for: game)
                let pending = PendingSaveImport(url: url, plan: plan, securityScoped: scoped)
                if plan.replacesExisting {
                    pendingImport = pending
                } else {
                    commitSaveImport(pending, overwrite: false)
                }
            } catch {
                if scoped { url.stopAccessingSecurityScopedResource() }
                saveImportError = error.localizedDescription
            }
        }
    }

    private func cancelPendingImport() {
        if let pending = pendingImport, pending.securityScoped {
            pending.url.stopAccessingSecurityScopedResource()
        }
        pendingImport = nil
    }

    private func commitSaveImport(_ pending: PendingSaveImport, overwrite: Bool) {
        Task { await performSaveImport(pending, overwrite: overwrite) }
    }

    private func performSaveImport(_ pending: PendingSaveImport, overwrite: Bool) async {
        defer {
            if pending.securityScoped { pending.url.stopAccessingSecurityScopedResource() }
        }
        guard await BatterySaveReload.waitForSaveIdle(isSaveBusy: { busy }) else {
            saveImportError = BatterySaveReload.saveIdleTimeoutNotice
            return
        }
        // Stop the game first: its teardown flush would otherwise overwrite the imported file.
        let reload = BatterySaveReload.shouldReloadAfterImport(for: system)
        if reload, let running = core {
            // Keep the session: if the save cannot be written, change nothing.
            if running.supportsSaveState, !autoResumePending, await !running.hadRuntimeError() {
                busy = true
                running.pause()
                do {
                    try await writeQuickSave(running)
                    busy = false
                } catch {
                    busy = false
                    saveImportError = "Couldn't save your progress before importing, so nothing was changed. \(error.localizedDescription)"
                    return
                }
            }
            guard !didLeave, core === running else { return }
            sessionToken = PlaySessionLifecycle.bump(sessionToken)
            casting.attach(video: nil)
            core = nil
            await running.stopAndWait()
        }
        var imported = false
        do {
            try saveImporter.commitImport(plan: pending.plan, from: pending.url, overwrite: overwrite)
            imported = true
            showToast(pending.plan.warning ?? "Imported \(pending.plan.sourceDescription)")
        } catch {
            saveImportError = error.localizedDescription
        }
        if reload {
            menuOpen = false
            // Imported: boot fresh so the new battery save is what the game reads (a save
            // state would carry the old one). Failed: pick up from the save just written.
            await reboot(autoResume: !imported)
        }
    }

    // MARK: - Leaving

    /// Auto-saves (when asked and possible), then stops the core and dismisses. Runs once.
    private func leave(autoSave: Bool) async {
        guard !didLeave else { return }
        didLeave = true
        leaving = true
        loadCoordinator.cancel()
        let idle = await BatterySaveReload.waitForSaveIdle(isSaveBusy: { busy })
        if autoSave, LeavePlayPolicy.shouldAutoSaveAfterWaiting(saveStillBusy: !idle),
           // Before the N64 resume lands the core shows the intro; saving would replace slot 0.
           !autoResumePending,
           let core, core.supportsSaveState,
           // A core stopped on a runtime error would save (and later resume) the broken state.
           await !core.hadRuntimeError() {
            busy = true
            defer { busy = false }
            core.pause()
            do {
                try await writeQuickSave(core)
            } catch {
                NSLog("RP auto-save failed system=%@ error=%@", system.rawValue, String(describing: error))
            }
        }
        sessionToken = PlaySessionLifecycle.bump(sessionToken)
        shutdown()
        dismiss()
    }

    private func shutdown() {
        controllers.stop()
        input.releaseAll()
        input.onChange = nil
        casting.attach(video: nil)
        core?.stop()
        core = nil
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        guard let core else { return }
        switch newPhase {
        case .active:
            if !menuOpen { core.resume() }
        case .inactive:
            // Control Center, a call banner: pause only; the player is usually coming back.
            input.releaseAll()
            core.pause()
            core.flushSaveData()
        case .background:
            input.releaseAll()
            core.pause()
            core.flushSaveData()
            saveForBackground(core)
        @unknown default:
            break
        }
    }

    /// iOS may end a backgrounded app without warning; keep a save state of where the
    /// player was. Runs inside a background task so the write can finish.
    private func saveForBackground(_ core: any EmulatorCore) {
        guard core.supportsSaveState, phase == .running, !busy, !leaving, !didLeave,
              !autoResumePending
        else { return }
        busy = true
        let task = BackgroundTask(name: "RetroPlay.BackgroundSave")
        Task { @MainActor in
            defer {
                busy = false
                task.end()
            }
            // A core stopped on a runtime error would save (and later resume) the broken state.
            guard await !core.hadRuntimeError(), self.core === core else { return }
            do {
                try await writeQuickSave(core)
            } catch {
                NSLog("RP background save failed system=%@ error=%@", system.rawValue, String(describing: error))
            }
        }
    }

    // MARK: - Boot

    private func startControllers() {
        controllers.onState = { [input] pad in
            input.applyPhysical(pad)
        }
        controllers.onMenu = {
            // Nothing to pause while loading, failed, or quitting.
            guard phase == .running, !leaving else { return }
            menuOpen.toggle()
        }
        controllers.onDisconnect = {
            // The player just lost their controls: stop the game until they choose.
            guard phase == .running, !leaving else { return }
            menuOpen = true
        }
        controllers.start()
    }

    private func boot(autoResume: Bool = true) async {
        guard core == nil, !didLeave else { return }
        let token = sessionToken
        phase = .loading
        let instance = CoreFactory.makeCore(for: system)
        input.onChange = { [weak instance] state in
            instance?.setInput(state)
        }

        do {
            try PSPROMOwnership.validate(romURL: romURL, game: game)
            try await instance.loadROM(at: romURL, saves: SavePaths())
        } catch {
            guard token.isCurrent(live: sessionToken) else { return }
            phase = .failed(error.localizedDescription)
            return
        }
        // The view may have been closed (or restarted) while the ROM was loading.
        guard !Task.isCancelled, token.isCurrent(live: sessionToken), !didLeave else {
            instance.stop()
            return
        }

        // Re-entering a game continues from the save written when it was last left.
        // mupen64plus-next rejects retro_unserialize until its first retro_run, so N64
        // resumes after the first frame instead of before start().
        let resumeBeforeStart = system != .n64
        var resumeStatus = AutoResumeLoader.Status.firstRun
        if autoResume, resumeBeforeStart {
            resumeStatus = await AutoResumeLoader.apply(
                core: instance,
                system: system,
                gameID: game.id,
                resumeAfterLoad: false,
                shouldContinue: { token.isCurrent(live: sessionToken) && !didLeave }
            )
            refreshSaveEntries()
        }
        guard token.isCurrent(live: sessionToken), !didLeave else {
            instance.stop()
            return
        }

        autoResumePending = autoResume && !resumeBeforeStart
        core = instance
        casting.attach(video: instance.video)
        instance.setInput(input.state)
        instance.setAudio(enabled: soundOn, respectSilentSwitch: respectSilentSwitch)
        instance.start()
        if autoResume, !resumeBeforeStart {
            await waitForFirstFrame(instance, timeout: .seconds(15))
            guard token.isCurrent(live: sessionToken), !didLeave else { return }
            resumeStatus = await AutoResumeLoader.apply(
                core: instance,
                system: system,
                gameID: game.id,
                resumeAfterLoad: false,
                shouldContinue: { token.isCurrent(live: sessionToken) && !didLeave }
            )
            // A newer boot owns the flag once the token moved on.
            guard token.isCurrent(live: sessionToken) else { return }
            autoResumePending = false
            refreshSaveEntries()
            guard !didLeave else { return }
            if isAppActive && !menuOpen {
                instance.resume()
            }
        }
        if !isAppActive || menuOpen {
            instance.pause()
        }
        phase = .running
        switch resumeStatus {
        case .loaded, .failed:
            showToast(AutoResumeLoader.statusLine(for: resumeStatus))
        case .firstRun, .cancelled:
            break
        }
        if system == .psp {
            watchForRuntimeError(instance)
        }
        // Not awaited: Restart and Import call boot and must not wait on the first frame.
        Task { await watchFirstFrame(instance) }
    }

    private func waitForFirstFrame(_ instance: any EmulatorCore, timeout: Duration) async {
        let started = ContinuousClock.now
        while instance.video.frameCount == 0, ContinuousClock.now - started < timeout, !didLeave {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// PPSSPP can stop on an unrecoverable error (e.g. inside a SAVEDATA dialog) without
    /// crashing. Say so instead of leaving a silently frozen screen.
    private func watchForRuntimeError(_ instance: any EmulatorCore) {
        Task { @MainActor in
            while core === instance, !didLeave {
                try? await Task.sleep(for: .milliseconds(500))
                guard core === instance else { return }
                if await instance.hadRuntimeError() {
                    alertMessage = "PPSSPP hit an unrecoverable error. Load a save state, or quit and reopen the game."
                    NSLog("RP_PPSSPP runtime error game=%@", game.id.uuidString)
                    return
                }
            }
        }
    }

    private func watchFirstFrame(_ instance: any EmulatorCore) async {
        let started = ContinuousClock.now
        while !Task.isCancelled, core === instance {
            if instance.video.frameCount > 0 {
                sawFirstFrame = true
                slowStartHint = false
                #if DEBUG
                runSmokeIfRequested()
                #endif
                return
            }
            if ContinuousClock.now - started > .seconds(8) {
                slowStartHint = true
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    #if DEBUG
    /// Mac/Simulator smoke runs (`-RetroPlaySmokeSystem <system>`): press Start then A.
    private func runSmokeIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-RetroPlaySmokeSystem")
            || UserDefaults.standard.object(forKey: "RetroPlaySmokeSystem") != nil
        else { return }
        NSLog("RP_SMOKE play first frame system=%@ rom=%@", system.rawValue, romURL.lastPathComponent)
        // `-RetroPlaySmokeLandscape YES`: turn to landscape, for layout screenshots.
        if UserDefaults.standard.bool(forKey: "RetroPlaySmokeLandscape") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            }
        } else if UserDefaults.standard.bool(forKey: "RetroPlaySmokePortrait") {
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
            }
        }
        let presses: [UInt32]
        switch system {
        case .gba: presses = [GBAInput.start.bits, GBAInput.a.bits]
        case .nds: presses = [NDSInput.start.rawValue, NDSInput.a.rawValue]
        case .n64: presses = [N64Input.start.rawValue, N64Input.a.rawValue]
        case .psp: presses = [PSPInput.start.rawValue, PSPInput.cross.rawValue]
        case .nes, .snes, .atari7800: presses = [RetroPadInput.start.rawValue, RetroPadInput.a.rawValue]
        case .genesis: presses = [RetroPadInput.start.rawValue, RetroPadInput.Genesis.a.rawValue]
        case .ps1: presses = [RetroPadInput.start.rawValue, RetroPadInput.PS1.cross.rawValue]
        }
        Task { @MainActor in
            for bits in presses {
                try? await Task.sleep(for: .milliseconds(1500))
                input.pulse(bits, duration: .milliseconds(300))
            }
            NSLog("RP_SMOKE %@ pulsed Start+A", system.rawValue)
        }
        // `-RetroPlaySmokeMenu YES`: open the pause menu after the presses, for screenshots.
        if UserDefaults.standard.bool(forKey: "RetroPlaySmokeMenu") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(5))
                menuOpen = true
            }
        }
        // `-RetroPlaySmokeRestartAfter <seconds>`: run Restart from Scratch's reboot once,
        // so the fresh-boot path can be checked without driving the menu.
        if let index = args.firstIndex(of: "-RetroPlaySmokeRestartAfter"),
           args.index(after: index) < args.endIndex,
           let seconds = Double(args[args.index(after: index)]),
           !Self.didSmokeRestart {
            Self.didSmokeRestart = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                NSLog("RP_SMOKE restart from scratch")
                await reboot(autoResume: false)
            }
        }
    }

    @MainActor private static var didSmokeRestart = false
    #endif
}

/// `UIApplication.beginBackgroundTask`, ended once (by the owner or on expiry).
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

/// The portrait pad's backing: its bottom corners follow the screen's rounded corners, and
/// the top corners match them.
private struct PadBacking: View {
    let fill: Color
    let stroke: Color
    /// Concentric with the display's corners when known (all four corners alike).
    let radius: CGFloat

    var body: some View {
        if radius > 0 {
            backing(RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else if #available(iOS 26.0, *) {
            backing(ConcentricRectangle(corners: .concentric(minimum: 28), isUniform: true))
        } else {
            backing(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func backing(_ shape: some Shape) -> some View {
        shape
            .fill(fill.opacity(0.55))
            .overlay { shape.stroke(stroke.opacity(0.35), lineWidth: 1).padding(0.5) }
    }
}

/// Reads the display's corner radius: a full-window view whose corners are concentric with
/// the screen's (UIKit, iOS 26) reports its effective radius. Nothing on earlier systems.
private struct DisplayCornerReader: UIViewRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        view.onChange = onChange
    }

    final class Probe: UIView {
        var onChange: ((CGFloat) -> Void)?
        private var reported: CGFloat = -1

        override init(frame: CGRect) {
            super.init(frame: frame)
            if #available(iOS 26.0, *) {
                cornerConfiguration = .uniformCorners(radius: .containerConcentric())
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard #available(iOS 26.0, *), window != nil else { return }
            let radius = effectiveRadius(corner: .bottomLeft)
            guard radius != reported else { return }
            reported = radius
            let onChange = onChange
            DispatchQueue.main.async { onChange?(radius) }
        }
    }
}

/// One in-game chrome button: glass, or filled when the button is on. Its corners match the
/// pad's flat-sided buttons.
@available(iOS 18.0, *)
private struct ChromeButtonLabel: View {
    let symbol: String
    let tint: Color
    let width: CGFloat
    let fill: Color?
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.padGlass) private var overGame

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 32 * padCornerFraction, style: .continuous)
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.4))
            .frame(width: width, height: 32)
            .padSurface(shape, tint: fill ?? .clear, clear: overGame && fill == nil) {
                if let fill {
                    shape.fill(fill)
                } else {
                    shape.fill(.ultraThinMaterial)
                }
                shape.strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            }
            .contentShape(shape)
    }
}
