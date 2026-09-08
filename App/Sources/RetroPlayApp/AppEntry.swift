import SwiftUI
import UniformTypeIdentifiers
import RetroPlayCore
import UIKit

/// Root shell: dark library tiles, system tabs, Settings tab. Liquid Glass chrome where useful.
@available(iOS 18.0, *)
public struct RetroPlayRootView: View {
    @StateObject private var store = LibraryStore()
    @State private var selectedTab: RootTab = .library
    @State private var systemTab: SystemTab = .all
    @State private var showImporter = false
    @State private var playGame: LibraryGame?
    @State private var importErrorMessage: String?
    @State private var showImportError = false
    private let covers = CoverArtStore()

    public init() {}

    private var filteredGames: [LibraryGame] {
        store.games(matching: systemTab.systemID)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            libraryNavigation
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(RootTab.library)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(RootTab.settings)
        }
        .tint(RetroPlayTheme.accent)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ImportContentTypes.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Import failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage ?? "Could not import the selected files.")
        }
    }

    private var libraryNavigation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                systemPicker
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RetroPlayTheme.section)

                Group {
                    if filteredGames.isEmpty {
                        ContentUnavailableView(
                            store.games.isEmpty ? "No Games Yet" : "No \(systemTab.title) Games",
                            systemImage: "gamecontroller",
                            description: Text(
                                store.games.isEmpty
                                    ? "Import games you own via Files. RetroPlay does not include ROMs."
                                    : "Import a \(systemTab.title) game, or switch tabs."
                            )
                        )
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RetroPlayTheme.canvas)
                    } else {
                        LibraryGridView(
                            games: filteredGames,
                            onSelect: { playGame = $0 },
                            artworkProvider: { game in
                                loadCover(for: game)
                            }
                        )
                    }
                }
            }
            .background(RetroPlayTheme.canvas)
            .navigationTitle("RetroPlay")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(RetroPlayTheme.section, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
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
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
        }
    }

    private var systemPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SystemTab.allCases) { tab in
                    let selected = systemTab == tab
                    Button {
                        systemTab = tab
                    } label: {
                        Text(tab.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .fill(selected ? RetroPlayTheme.accent.opacity(0.35) : RetroPlayTheme.card)
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selected ? RetroPlayTheme.accent : RetroPlayTheme.cardStroke,
                                        lineWidth: 1
                                    )
                            }
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func loadCover(for game: LibraryGame) -> UIImage? {
        let url = covers.coverURL(forGameID: game.id)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)
        else {
            return nil
        }
        return image
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
                } else if let first = added.first {
                    // Jump to the system tab for the first imported game.
                    if let tab = SystemTab.allCases.first(where: { $0.systemID == first.systemID }) {
                        systemTab = tab
                    }
                }
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }
}

@available(iOS 18.0, *)
private enum RootTab: Hashable {
    case library
    case settings
}

@available(iOS 18.0, *)
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(
                        """
                        RetroPlay only runs games you import yourself via Files. We do not ship, sell, or host ROMs, BIOS dumps, or copyrighted game files.

                        App Store Guideline 4.7: emulator apps may offer downloadable games; the developer is responsible for compliance. You must own the rights to any software you import.

                        No ROMs are included with this app.
                        """
                    )
                    .font(.body)
                    .foregroundStyle(.primary)
                    .listRowBackground(RetroPlayTheme.card)
                } header: {
                    Text("Legal")
                }

                Section {
                    ForEach(SystemID.allCases) { system in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(system.displayName)
                            Text("Default core: \(system.defaultCoreName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .listRowBackground(RetroPlayTheme.card)
                    }
                } header: {
                    Text("Systems (P0)")
                }

                Section {
                    LabeledContent("GBA", value: "mGBA (playable)")
                    LabeledContent("PSP", value: "PPSSPP IR (scaffold)")
                    Text(PPSSPPDefaults.performanceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PPSSPPDefaults.appStoreIniSnippet)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Cores")
                }
                .listRowBackground(RetroPlayTheme.card)
            }
            .scrollContentBackground(.hidden)
            .background(RetroPlayTheme.canvas)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(RetroPlayTheme.section, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
