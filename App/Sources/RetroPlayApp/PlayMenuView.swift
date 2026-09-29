// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// Pause menu shown over the game (emulation is paused while it is open).
@available(iOS 18.0, *)
struct PlayMenuView: View {
    let title: String
    let systemName: String
    let supportsSaveState: Bool
    let supportsReset: Bool
    /// Newest first; slot 0 is the latest save.
    let saveEntries: [SaveStateStore.Entry]
    let busy: Bool
    /// Quit was chosen and the exit save is running: the menu is locked and says so.
    let leaving: Bool
    let fastForward: Bool
    let hasController: Bool

    @Binding var soundOn: Bool
    @Binding var haptics: Bool
    @Binding var padOpacity: Double
    @Binding var smoothScreen: Bool
    @Binding var touchWithController: Bool
    @Binding var landscapeFill: Bool

    let onResume: () -> Void
    let onSave: () -> Void
    /// Tap = latest save; long-press = older saves, Restart from Scratch.
    let onLoadCommand: (PlayLoadCommand) -> Void
    let onImportSave: () -> Void
    let onFastForward: () -> Void
    let onReset: () -> Void
    let onQuit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmReset = false
    @State private var confirmRestart = false
    @State private var showOptions = false

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
        .retroPlayAlert(
            "Reset Game?",
            message: "Unsaved progress is lost.",
            isPresented: $confirmReset,
            actions: [.cancel("Cancel"), .destructive("Reset") { onReset() }]
        )
        .retroPlayAlert(
            "Restart from Scratch?",
            message: "Every save state for this game is deleted and it starts over. In-game saves are kept.",
            isPresented: $confirmRestart,
            actions: [
                .cancel("Cancel"),
                .destructive("Restart") { onLoadCommand(.restartFromScratch) }
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // The pixel face is ~1 em per letter, so at accessibility sizes Save and Load
            // stack instead of squeezing side by side. AnyLayout keeps the UIKit Load control.
            saveLoadLayout {
                Button(action: onSave) {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(MenuTileButtonStyle())
                .disabled(!supportsSaveState || busy)
                // UIKit button: SwiftUI Menu(primaryAction:) drops its row actions on iOS 26.
                PlayLoadMenuControlView(
                    entries: saveEntries,
                    busy: busy,
                    onCommand: { command in
                        // Deletes every save state: confirm first, like Reset.
                        if command == .restartFromScratch {
                            confirmRestart = true
                        } else {
                            onLoadCommand(command)
                        }
                    },
                    onImport: onImportSave
                )
                .frame(maxWidth: .infinity)
            }
            .frame(minHeight: MenuTileButtonStyle.height)

            if let latest = saveEntries.first?.modifiedAt {
                Text("Saved \(latest, format: .relative(presentation: .named)) · hold Load for older saves")
                    .font(RetroPlayFont.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            // Quick actions: icon only, state shown by the fill.
            HStack(spacing: 14) {
                MenuIconButton(
                    symbol: "forward.fill",
                    label: fastForward ? "Normal speed" : "Fast forward",
                    active: fastForward,
                    activeColor: .orange,
                    action: onFastForward
                )
                MenuIconButton(
                    symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                    label: soundOn ? "Sound on" : "Sound off",
                    active: soundOn,
                    activeColor: RetroPlayTheme.accent
                ) { soundOn.toggle() }
                AirPlayRoutePicker()
                    .frame(width: MenuIconButton.size, height: MenuIconButton.size)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .accessibilityLabel("AirPlay display")
                if supportsReset {
                    MenuIconButton(
                        symbol: "arrow.counterclockwise",
                        label: "Reset game",
                        tint: .red
                    ) { confirmReset = true }
                }
            }
            .padding(.vertical, 4)

            DisclosureGroup(isExpanded: $showOptions) {
                VStack(spacing: 10) {
                    Toggle("Haptics", isOn: $haptics)
                    Toggle("Smooth Screen", isOn: $smoothScreen)
                    if hasController {
                        Toggle("Touch Controls with Controller", isOn: $touchWithController)
                    }
                    Toggle("Fill Screen in Landscape", isOn: $landscapeFill)
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
            }
        }
        .disabled(leaving)
        .padding(20)
        .frame(maxWidth: 360)
        // Past AX1 the pixel face no longer fits a phone-width card even stacked.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
    }
}

extension PlayMenuView {
    private var saveLoadLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
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
            .background(
                Color.white.opacity(configuration.isPressed ? 0.22 : 0.12),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? .black : tint)
                .frame(width: Self.size, height: Self.size)
                .background(active ? activeColor : Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
