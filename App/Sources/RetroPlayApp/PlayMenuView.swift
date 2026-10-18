// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// Pause menu shown over the game (emulation is paused while it is open).
@available(iOS 18.0, *)
struct PlayMenuView: View {
    let title: String
    let systemName: String
    let supportsSaveState: Bool
    /// Newest first; slot 0 is the latest save.
    let saveEntries: [SaveStateStore.Entry]
    let busy: Bool
    /// Quit was chosen and the exit save is running: the menu is locked and says so.
    let leaving: Bool
    let hasController: Bool
    /// The connected controller, named under Options (not over the game).
    var controllerName: String? = nil

    @Binding var haptics: Bool
    @Binding var padOpacity: Double
    @Binding var smoothScreen: Bool
    @Binding var touchWithController: Bool
    @Binding var landscapeFill: Bool
    /// PSP only: internal resolution (`PSPRenderResolution` raw value).
    var pspResolution: Binding<Int>? = nil

    let onResume: () -> Void
    let onSave: () -> Void
    /// A save row loads that save; Reset deletes every save state and starts over.
    let onLoadCommand: (PlayLoadCommand) -> Void
    let onImportSave: () -> Void
    let onQuit: () -> Void

    @State private var confirmRestart = false
    @State private var showSaves = false
    @State private var showOptions = false
    /// The controller cursor.
    @State private var focus: MenuItem?
    @Environment(ControllerNavigator.self) private var navigator

    /// Everything the controller cursor can land on, top to bottom.
    private enum MenuItem: Hashable {
        case resume, save, saves, saveEntry(Int), reset, importSave
        case options, haptics, smooth, resolution, touchWithController, fill, quit
    }

    private var menuItems: [MenuItem] {
        var items: [MenuItem] = [.resume]
        if supportsSaveState { items.append(.save) }
        items.append(.saves)
        if showSaves {
            items += saveEntries.indices.map(MenuItem.saveEntry)
            items += [.reset, .importSave]
        }
        items.append(.options)
        if showOptions {
            items += [.haptics, .smooth]
            if pspResolution != nil { items.append(.resolution) }
            if hasController { items.append(.touchWithController) }
            items.append(.fill)
        }
        if !leaving { items.append(.quit) }
        return items
    }

    var body: some View {
        // Landscape phones are short: scroll only when the card does not fit.
        ViewThatFits(in: .vertical) {
            card
            ScrollView {
                card
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: 380)
        }
        .environment(\.colorScheme, .dark)
        .onAppear { if navigator.isConnected { focus = .resume } }
        .onChange(of: navigator.event) { _, event in
            guard let event, event.context == .pauseMenu, !confirmRestart else { return }
            handle(event.command)
        }
        .retroPlayAlert(
            "Reset Game?",
            message: "Every save state for this game is deleted and it starts over. In-game saves are kept.",
            isPresented: $confirmRestart,
            actions: [
                .cancel("Cancel"),
                .destructive("Reset") { onLoadCommand(.restartFromScratch) }
            ]
        )
    }

    private var card: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(title)
                    .font(RetroPlayFont.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(systemName)
                    .font(RetroPlayFont.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            Button(action: onResume) {
                Label("Resume", systemImage: "play.fill")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
            }
            .prominentGlassButton()
            .controlSize(.large)
            .controllerFocusRing(focus == .resume, cornerRadius: 22)

            // Quick actions: icon only.
            HStack(spacing: 14) {
                MenuIconButton(
                    symbol: "square.and.arrow.down",
                    label: "Save state",
                    action: onSave
                )
                .disabled(!supportsSaveState || busy)
                .controllerFocusRing(focus == .save, cornerRadius: MenuIconButton.size / 2)
                AirPlayRoutePicker()
                    .frame(width: MenuIconButton.size, height: MenuIconButton.size)
                    .menuGlass(Circle(), fallback: Color.white.opacity(0.12))
                    .accessibilityLabel("AirPlay display")
            }
            .padding(.vertical, 4)

            savesGroup

            DisclosureGroup(isExpanded: $showOptions) {
                VStack(spacing: 10) {
                    if hasController {
                        Label(controllerName ?? "Controller connected", systemImage: "gamecontroller.fill")
                            .font(RetroPlayFont.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Toggle("Haptics", isOn: $haptics)
                        .controllerFocusRing(focus == .haptics, cornerRadius: 6)
                    Toggle("Smooth Screen", isOn: $smoothScreen)
                        .controllerFocusRing(focus == .smooth, cornerRadius: 6)
                    if let pspResolution {
                        resolutionPicker(pspResolution)
                            .controllerFocusRing(focus == .resolution, cornerRadius: 6)
                    }
                    if hasController {
                        Toggle("Touch Controls with Controller", isOn: $touchWithController)
                            .controllerFocusRing(focus == .touchWithController, cornerRadius: 6)
                    }
                    Toggle("Fill Screen in Landscape", isOn: $landscapeFill)
                        .controllerFocusRing(focus == .fill, cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Landscape Controls Opacity")
                            .font(RetroPlayFont.caption)
                            .foregroundStyle(.white.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                        Slider(value: $padOpacity, in: 0.25...1)
                    }
                }
                .padding(.top, 8)
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
                    .foregroundStyle(.white)
                    .controllerFocusRing(focus == .options, cornerRadius: 6)
            }
            .font(RetroPlayFont.subheadline)
            .padding(.horizontal, 4)

            if leaving {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Saving…")
                        .font(RetroPlayFont.subheadline)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: MenuTileButtonStyle.height)
                .accessibilityElement(children: .combine)
            } else {
                Button(action: onQuit) {
                    Label("Quit Game", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuTileButtonStyle(foreground: .red))
                .frame(minHeight: MenuTileButtonStyle.height)
                .controllerFocusRing(focus == .quit)
            }
        }
        .disabled(leaving)
        .padding(20)
        .frame(maxWidth: 360)
        // Past AX1 the menu no longer fits a phone-width card even stacked.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .menuCardGlass()
    }
}

extension View {
    /// The pause menu card: Liquid Glass (iOS 26), else the material card.
    @ViewBuilder
    func menuCardGlass() -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            GlassEffectContainer {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1) }
                .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        }
    }

    /// A pause-menu button's surface: interactive Liquid Glass (iOS 26), optionally tinted,
    /// else `fallback` filling `shape`.
    @ViewBuilder
    func menuGlass<S: Shape>(_ shape: S, tint: Color? = nil, fallback: Color) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(), in: shape)
        } else {
            background(fallback, in: shape)
        }
    }

    /// A secondary button: glass (iOS 26), else bordered.
    @ViewBuilder
    func glassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Resume: prominent glass (iOS 26), else bordered prominent.
    @ViewBuilder
    func prominentGlassButton() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

extension PlayMenuView {
    /// Up / down move the cursor, A does what a tap would, B resumes the game.
    private func handle(_ command: ControllerNavCommand) {
        let items = menuItems
        guard let current = focus, let index = items.firstIndex(of: current) else {
            if command == .back { onResume() } else { focus = items.first }
            return
        }
        switch command {
        case .up: focus = items[max(0, index - 1)]
        case .down: focus = items[min(items.count - 1, index + 1)]
        case .confirm: activate(current)
        case .back: onResume()
        case .left, .right, .previousPage, .nextPage: break
        }
    }

    private func activate(_ item: MenuItem) {
        guard !leaving else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            switch item {
            case .resume: onResume()
            case .save: if supportsSaveState && !busy { onSave() }
            case .saves: showSaves.toggle()
            case .saveEntry(let index):
                if supportsSaveState, !busy, saveEntries.indices.contains(index) {
                    onLoadCommand(.loadEntry(saveEntries[index]))
                }
            case .reset: if !busy { confirmRestart = true }
            case .importSave: onImportSave()
            case .options: showOptions.toggle()
            case .haptics: haptics.toggle()
            case .smooth: smoothScreen.toggle()
            case .resolution:
                if let pspResolution {
                    let all = PSPRenderResolution.allCases
                    let index = all.firstIndex { $0.rawValue == pspResolution.wrappedValue } ?? 0
                    pspResolution.wrappedValue = all[(index + 1) % all.count].rawValue
                }
            case .touchWithController: touchWithController.toggle()
            case .fill: landscapeFill.toggle()
            case .quit: onQuit()
            }
        }
    }

    /// PSP internal resolution: Auto matches the screen; the others are fixed multiples.
    private func resolutionPicker(_ selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Resolution")
                .font(RetroPlayFont.caption)
                .foregroundStyle(.white.opacity(0.6))
            Picker("Resolution", selection: selection) {
                ForEach(PSPRenderResolution.allCases) { option in
                    Text(option.title)
                        .accessibilityLabel(option.accessibilityTitle)
                        .tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Saves dropdown: every save state (newest first), Reset, battery-save import.
    private var savesGroup: some View {
        DisclosureGroup(isExpanded: $showSaves) {
            VStack(spacing: 8) {
                if saveEntries.isEmpty {
                    Text(PlaySavesMenuContent.emptyTitle)
                        .font(RetroPlayFont.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity, minHeight: 36)
                } else {
                    ForEach(Array(saveEntries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            onLoadCommand(.loadEntry(entry))
                        } label: {
                            SaveRowLabel(entry: entry)
                        }
                        .buttonStyle(SaveRowButtonStyle())
                        .disabled(!supportsSaveState || busy)
                        .controllerFocusRing(focus == .saveEntry(index), cornerRadius: 12)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        confirmRestart = true
                    } label: {
                        Label(PlaySavesMenuContent.resetTitle, systemImage: "arrow.counterclockwise")
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MenuTileButtonStyle(foreground: .red))
                    .disabled(busy)
                    .controllerFocusRing(focus == .reset)
                    Button(action: onImportSave) {
                        Label("Import", systemImage: "square.and.arrow.down.on.square")
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MenuTileButtonStyle())
                    .accessibilityLabel(PlaySavesMenuContent.importTitle)
                    .controllerFocusRing(focus == .importSave)
                }
            }
            .padding(.top, 8)
        } label: {
            Label(PlaySavesMenuContent.title, systemImage: "tray.full")
                .foregroundStyle(.white)
                .controllerFocusRing(focus == .saves, cornerRadius: 6)
        }
        .font(RetroPlayFont.subheadline)
        .padding(.horizontal, 4)
    }
}

/// One save state: its name and when it was made.
@available(iOS 18.0, *)
private struct SaveRowLabel: View {
    let entry: SaveStateStore.Entry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.slot == 0 ? "clock.fill" : "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(PlaySavesMenuContent.name(for: entry))
                    .font(RetroPlayFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let date = entry.modifiedAt {
                    Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(RetroPlayFont.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Loads this save")
    }
}

/// Save row: same glass fill as the tiles, left-aligned, a little shorter.
@available(iOS 18.0, *)
private struct SaveRowButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .menuGlass(
                RoundedRectangle(cornerRadius: 12, style: .continuous),
                fallback: Color.white.opacity(configuration.isPressed ? 0.22 : 0.08)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Neutral pause-menu tile: light glass fill, white label (the green tint read as disabled).
@available(iOS 18.0, *)
struct MenuTileButtonStyle: ButtonStyle {
    static let height: CGFloat = 46
    var foreground: Color = .white
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroPlayFont.subheadline)
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.35))
            .multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .menuGlass(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
                fallback: Color.white.opacity(configuration.isPressed ? 0.22 : 0.12)
            )
    }
}

/// Round icon-only quick action. `active` fills it with `activeColor`.
@available(iOS 18.0, *)
struct MenuIconButton: View {
    static let size: CGFloat = 52
    let symbol: String
    let label: String
    var active = false
    var activeColor: Color = RetroPlayTheme.accent
    var tint: Color = .white
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? .black : tint)
                .frame(width: Self.size, height: Self.size)
                .menuGlass(Circle(), tint: active ? activeColor : nil,
                           fallback: active ? activeColor : Color.white.opacity(0.12))
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
