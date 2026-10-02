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

    @Binding var haptics: Bool
    @Binding var padOpacity: Double
    @Binding var smoothScreen: Bool
    @Binding var touchWithController: Bool
    @Binding var landscapeFill: Bool

    let onResume: () -> Void
    let onSave: () -> Void
    /// A save row loads that save; Reset deletes every save state and starts over.
    let onLoadCommand: (PlayLoadCommand) -> Void
    let onImportSave: () -> Void
    let onQuit: () -> Void

    @State private var confirmRestart = false
    @State private var showSaves = false
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
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Quick actions: icon only.
            HStack(spacing: 14) {
                MenuIconButton(
                    symbol: "square.and.arrow.down",
                    label: "Save state",
                    action: onSave
                )
                .disabled(!supportsSaveState || busy)
                AirPlayRoutePicker()
                    .frame(width: MenuIconButton.size, height: MenuIconButton.size)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .accessibilityLabel("AirPlay display")
            }
            .padding(.vertical, 4)

            savesGroup

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
                    ForEach(saveEntries) { entry in
                        Button {
                            onLoadCommand(.loadEntry(entry))
                        } label: {
                            SaveRowLabel(entry: entry)
                        }
                        .buttonStyle(SaveRowButtonStyle())
                        .disabled(!supportsSaveState || busy)
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
                    Button(action: onImportSave) {
                        Label("Import", systemImage: "square.and.arrow.down.on.square")
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(MenuTileButtonStyle())
                    .accessibilityLabel(PlaySavesMenuContent.importTitle)
                }
            }
            .padding(.top, 8)
        } label: {
            Label(PlaySavesMenuContent.title, systemImage: "tray.full")
                .foregroundStyle(.white)
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
            .background(
                Color.white.opacity(configuration.isPressed ? 0.22 : 0.08),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? .black : tint)
                .frame(width: Self.size, height: Self.size)
                .background(active ? activeColor : Color.white.opacity(0.12), in: Circle())
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
