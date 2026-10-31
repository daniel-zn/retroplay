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
                if !batch.skipped.isEmpty {
                    skippedSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("Import Saves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !batch.items.isEmpty { actions }
            }
        }
        .environment(\.font, RetroPlayFont.caption)
        .tint(RetroPlayTheme.accent)
        .interactiveDismissDisabled(committing)
    }

    private var summaryText: String {
        let found = batch.items.count
        var text = found == 0
            ? "No saves to import."
            : "Found \(found == 1 ? "1 save" : "\(found) saves") for \(gameCountText(batch.gameCount))."
        if !batch.skipped.isEmpty {
            text += " \(batch.skipped.count) skipped."
        }
        return text
    }

    private var summarySection: some View {
        Section {
            Text(summaryText)
                .font(RetroPlayFont.subheadline)
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
            }
            .font(RetroPlayFont.caption2)
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private func itemSection(_ title: String, items: [SaveImportItem], footer: String? = nil) -> some View {
        Section {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.game.displayName)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                        Spacer(minLength: 4)
                        SystemBadge(system: item.game.systemID)
                    }
                    Text(item.sourceName)
                        .font(RetroPlayFont.caption2)
                        .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            sectionHeader("\(title) (\(items.count))")
        } footer: {
            if let footer {
                Text(footer).font(RetroPlayFont.caption2)
            }
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private var skippedSection: some View {
        Section {
            ForEach(batch.skipped) { skipped in
                VStack(alignment: .leading, spacing: 6) {
                    Text(skipped.name)
                        .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    Text(skipped.reason)
                        .font(RetroPlayFont.caption2)
                        .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } header: {
            sectionHeader("Skipped (\(batch.skipped.count))")
        }
        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(RetroPlayFont.caption2)
            .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
    }

    /// One button when nothing would be replaced; otherwise replace-all first and, when there
    /// are new saves too, a way to add only those.
    private var actions: some View {
        let replacing = batch.replacements.count
        let adding = batch.newSaves.count
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
                        .font(RetroPlayFont.caption)
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
        .background(RetroPlayTheme.canvas(for: colorScheme).opacity(0.94))
    }
}
