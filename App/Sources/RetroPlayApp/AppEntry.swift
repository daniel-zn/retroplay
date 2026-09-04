import SwiftUI
import UniformTypeIdentifiers
import RetroPlayCore

/// Library shell: Files import → Documents/ROMs + JSON library; stub cores until M1+.
/// Liquid Glass on iOS 26+; plain/material fallback on older OS. Platform remains iOS 18.
@available(iOS 18.0, *)
public struct RetroPlayRootView: View {
    @StateObject private var store = LibraryStore()
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var playGame: LibraryGame?
    @State private var importErrorMessage: String?
    @State private var showImportError = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    ContentUnavailableView(
                        "No Games Yet",
                        systemImage: "gamecontroller",
                        description: Text("Import games you own via Files. RetroPlay does not include ROMs.")
                    )
                } else {
                    List(store.games) { game in
                        Button {
                            playGame = game
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(game.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("\(game.systemID.displayName) · \(game.systemID.defaultCoreName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("RetroPlay")
            .retroPlayToolbarGlass()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .padding(8)
                            .retroPlayGlassChrome()
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .retroPlayGlassChrome()
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: ImportContentTypes.allowedContentTypes,
                allowsMultipleSelection: true
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
            .alert("Import failed", isPresented: $showImportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrorMessage ?? "Could not import the selected files.")
            }
        }
    }


    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        case .success(let urls):
            do {
                let added = try store.importFiles(from: urls)
                if added.isEmpty, !urls.isEmpty {
                    importErrorMessage = "No supported P0 ROMs in the selection (GBA, N64, NDS, PSP extensions)."
                    showImportError = true
                }
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }
}

@available(iOS 18.0, *)
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Legal") {
                    Text(
                        """
                        RetroPlay only runs games you import yourself via Files. We do not ship, sell, or host ROMs, BIOS dumps, or copyrighted game files.

                        App Store Guideline 4.7: emulator apps may offer downloadable games; the developer is responsible for compliance. You must own the rights to any software you import.

                        No ROMs are included with this app.
                        """
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                }

                Section("Systems (P0)") {
                    ForEach(SystemID.allCases) { system in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(system.displayName)
                            Text("Default core: \(system.defaultCoreName) (stub until bundled)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    LabeledContent("Milestone", value: "M0 — library shell")
                    Text("Cores are StubEmulatorCore placeholders. First playable target is M1 (mGBA).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .retroPlayToolbarGlass()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .retroPlayGlassChrome()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
