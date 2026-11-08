// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import RetroPlayCore

/// Settings → Saves Waiting for Games: saves imported for games not in the library
/// (`KeptSaves`). Each goes to its game when the game is added; swipe to delete one.
@available(iOS 18.0, *)
struct KeptSavesView: View {
    let games: [LibraryGame]
    @Binding var saves: [KeptSave]
    @Environment(\.colorScheme) private var colorScheme
    @State private var deleteError: String?

    static let title = "Saves Waiting for Games"

    var body: some View {
        List {
            if saves.isEmpty {
                ContentUnavailableView(
                    "No Waiting Saves",
                    systemImage: "tray",
                    description: Text("Saves you import for games that aren't in your library wait here until you add the game.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(saves) { save in
                        KeptSaveRow(save: save)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Each save goes to its game when you add the game to your library.")
                }
                .listRowBackground(RetroPlayTheme.card(for: colorScheme))
            }
        }
        .scrollContentBackground(.hidden)
        .background(RetroPlayTheme.canvas(for: colorScheme))
        .navigationTitle(retroPlayDisplayString(Self.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if !saves.isEmpty { EditButton() } }
        .retroPlayAlert(
            "Couldn't Delete the Save",
            message: deleteError ?? "",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }),
            actions: [.cancel("OK")]
        )
    }

    private func delete(_ offsets: IndexSet) {
        for save in offsets.map({ saves[$0] }) {
            do {
                try KeptSaves.delete(save)
            } catch {
                deleteError = error.localizedDescription
            }
        }
        saves = KeptSaves.list(games: games, paths: SavePaths())
    }
}

@available(iOS 18.0, *)
private struct KeptSaveRow: View {
    let save: KeptSave

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(save.title)
                .font(RetroPlayFont.body)
                .lineLimit(2)
            Text(detail)
                .font(RetroPlayFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [save.system.displayName]
        if save.title != save.name { parts.append(save.name) }
        parts.append(Int64(save.bytes).formatted(.byteCount(style: .file)))
        if let date = save.modified { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        return parts.joined(separator: " · ")
    }
}
