// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// What a "+" → Saves pick would import, before anything is written: the saves found and the
/// games they belong to, the ones that would replace a save already here (one choice for all
/// of them), and what was skipped and why. Swipe down to cancel.
@available(iOS 18.0, *)
struct SaveImportSheet: View {
    let batch: SaveImportBatch
    let committing: Bool
    /// Called with whether existing saves are replaced.
    let onImport: (_ replaceExisting: Bool) -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The system grouped-list colours, so rows sit on visible cards in light and dark alike.
    private static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    private static let rowBackground = Color(uiColor: .secondarySystemGroupedBackground)

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if !batch.newSaves.isEmpty {
                    itemSection("New Saves", items: batch.newSaves)
                }
                if !batch.replacements.isEmpty {
                    itemSection(
                        "Replaces a Save Here",
                        items: batch.replacements,
                        footer: "These games already have a save on this iPhone. Replacing it can't be undone."
                    )
                }
                if !batch.forMissingGames.isEmpty {
                    itemSection(
                        "For Games Not in Your Library Yet",
                        items: batch.forMissingGames,
                        footer: "Kept under their own names, so each game finds its save once you add it. Settings lists them."
                    )
                }
                if !batch.skipped.isEmpty {
                    skippedSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(Self.groupedBackground)
            .navigationTitle(retroPlayDisplayString("Import Saves"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            // The title in the app's face, as in Settings.
            .retroPlayNavigationTitleChrome(for: colorScheme)
            .safeAreaInset(edge: .bottom) {
                if !batch.items.isEmpty { actions }
            }
        }
        .environment(\.font, RetroPlayFont.callout)
        .retroPlayTypography()
        .tint(RetroPlayTheme.accent)
        .interactiveDismissDisabled(committing)
    }

    private var summaryText: String {
        let missing = batch.forMissingGames.count
        let found = batch.items.count - missing
        var text: String
        if found > 0 {
            text = "Found \(found == 1 ? "1 save" : "\(found) saves") for \(gameCountText(batch.gameCount))."
            if missing > 0 { text += " \(missing) for games not in your library yet." }
        } else if missing > 0 {
            text = "Found \(missing == 1 ? "1 save" : "\(missing) saves") for games not in your library yet."
        } else {
            text = "No saves to import."
        }
        if !batch.skipped.isEmpty {
            text += " \(batch.skipped.count) skipped."
        }
        return text
    }

    private var summarySection: some View {
        Section {
            Text(summaryText)
                .font(RetroPlayFont.headline)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .accessibilityIdentifier("saveImport.summary")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if batch.truncated {
                    Text("The folder was too big to look through completely. Pick a smaller folder to find the rest.")
                }
                if batch.ignoredFiles > 0 {
                    Text(batch.ignoredFiles == 1 ? "1 other file isn't a save." : "\(batch.ignoredFiles) other files aren't saves.")
                }
                if batch.otherSystemSaves > 0 {
                    Text(batch.otherSystemSaves == 1
                        ? "1 save is for a system RetroPlay doesn't play."
                        : "\(batch.otherSystemSaves) saves are for systems RetroPlay doesn't play.")
                }
            }
            .font(RetroPlayFont.footnote)
            .lineSpacing(2)
        }
        .listRowBackground(Self.rowBackground)
    }

    private func itemSection(_ title: String, items: [SaveImportItem], footer: String? = nil) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // A PSP game not in the library yet is named by its product ID.
                        Text(item.forMissingGame && item.game.systemID == .psp ? "Product ID \(item.game.displayName)" : item.game.displayName)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        Spacer(minLength: 4)
                        SystemBadge(system: item.game.systemID)
                    }
                    if !item.addedParts.isEmpty {
                        Text("Adds \(item.addedParts.joined(separator: ", "))")
                            .font(RetroPlayFont.footnote)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    }
                    if item.forMissingGame, item.replacesExisting {
                        Text("Replaces a save here")
                            .font(RetroPlayFont.footnote)
                            .foregroundStyle(.orange)
                    }
                    Text(item.sourceName)
                        .font(RetroPlayFont.footnote)
                        .lineSpacing(2)
                        .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                    if let note = item.plan.warning {
                        Text(note)
                            .font(RetroPlayFont.footnote)
                            .lineSpacing(2)
                            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                    }
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            sectionHeader("\(title) (\(items.count))")
        } footer: {
            if let footer {
                Text(footer).font(RetroPlayFont.footnote).lineSpacing(2)
            }
        }
        .listRowBackground(Self.rowBackground)
    }

    private var skippedSection: some View {
        Section {
            ForEach(batch.skipped) { skipped in
                VStack(alignment: .leading, spacing: 6) {
                    Text(skipped.name)
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    Text(skipped.reason)
                        .font(RetroPlayFont.footnote)
                        .lineSpacing(2)
                        .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            sectionHeader("Skipped (\(batch.skipped.count))")
        }
        .listRowBackground(Self.rowBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        // Footnote rather than caption2: in capitals, 11 pt section names read as specks.
        Text(title.uppercased())
            .font(RetroPlayFont.footnote)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    /// One button when nothing would be replaced; otherwise replace-all first and, when there
    /// are new saves too, a way to add only those.
    private var actions: some View {
        // Every save counts, those for games not in the library too: none replaces one here
        // without the player's choice.
        let replacing = batch.items.filter(\.replacesExisting).count
        let adding = batch.items.count - replacing
        return VStack(spacing: 10) {
            Button {
                onImport(true)
            } label: {
                Group {
                    if committing {
                        ProgressView().tint(.white)
                    } else if replacing == 0 {
                        Text(adding == 1 ? "Import 1 Save" : "Import \(adding) Saves")
                    } else if adding == 0 {
                        Text(replacing == 1 ? "Replace 1 Save" : "Replace \(replacing) Saves")
                    } else {
                        Text("Import All and Replace \(replacing)")
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(RetroPlayPrimaryButtonStyle())
            .accessibilityIdentifier("saveImport.import")
            if replacing > 0, adding > 0 {
                Button {
                    onImport(false)
                } label: {
                    Text(adding == 1 ? "Only Add 1 New Save" : "Only Add \(adding) New Saves")
                        .font(RetroPlayFont.callout)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .accessibilityIdentifier("saveImport.keepExisting")
            }
        }
        .disabled(committing)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        // Opaque down to the screen's edge, so rows scrolling under the buttons don't show
        // through below them.
        .background(Self.groupedBackground.ignoresSafeArea(edges: .bottom))
    }
}
