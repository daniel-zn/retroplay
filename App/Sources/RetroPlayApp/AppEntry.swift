import SwiftUI
import UniformTypeIdentifiers
import RetroPlayCore
import UIKit

/// Root shell: tile library, search, Settings via glass toolbar. Appearance preference (dark default).
@available(iOS 18.0, *)
public struct RetroPlayRootView: View {
    @StateObject private var store = LibraryStore()
    @AppStorage("retroplay.appearance") private var appearanceRaw = AppearancePreference.dark.rawValue
    @State private var selectedTab: RootTab = .library
    @State private var systemTab: SystemTab = .all
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var playGame: LibraryGame?
    @State private var searchPlayGame: LibraryGame?
    @State private var searchQuery = ""
    @State private var importErrorMessage: String?
    @State private var showImportError = false
    @Environment(\.colorScheme) private var colorScheme
    private let covers = CoverArtStore()

    public init() {}

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .dark
    }

    private var filteredGames: [LibraryGame] {
        store.games(matching: systemTab.systemID)
    }

    private var searchResults: [LibraryGame] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return store.games.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.systemID.displayName.localizedCaseInsensitiveContains(q)
                || $0.systemID.defaultCoreName.localizedCaseInsensitiveContains(q)
        }
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            libraryNavigation
                .tabItem { Label("Library", systemImage: "square.grid.2x2.fill") }
                .tag(RootTab.library)

            searchNavigation
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(RootTab.search)
        }
        .tint(RetroPlayTheme.accent)
        .preferredColorScheme(appearance.colorScheme)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ImportContentTypes.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(appearanceRaw: $appearanceRaw)
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
                    .background(RetroPlayTheme.section(for: colorScheme))

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
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RetroPlayTheme.canvas(for: colorScheme))
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
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("RetroPlay")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(RetroPlayTheme.section(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                            .labelStyle(.iconOnly)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .retroPlayGlassChrome()
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        showImporter = true
                    } label: {
                        Label("Import", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .retroPlayGlassChrome()
                    }
                    .accessibilityLabel("Import")
                }
            }
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
        }
    }

    private var searchNavigation: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    ContentUnavailableView(
                        "No Games Yet",
                        systemImage: "magnifyingglass",
                        description: Text("Import games from the Library tab, then search them here.")
                    )
                } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Search Library",
                        systemImage: "magnifyingglass",
                        description: Text("Find games you already imported into RetroPlay.")
                    )
                } else if searchResults.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    LibraryGridView(
                        games: searchResults,
                        onSelect: { searchPlayGame = $0 },
                        artworkProvider: { game in
                            loadCover(for: game)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(RetroPlayTheme.section(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .searchable(text: $searchQuery, prompt: "Search imported games")
            .navigationDestination(item: $searchPlayGame) { game in
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
                                    .fill(selected ? RetroPlayTheme.accent.opacity(0.35) : RetroPlayTheme.card(for: colorScheme))
                            }
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        selected ? RetroPlayTheme.accent : RetroPlayTheme.cardStroke(for: colorScheme),
                                        lineWidth: 1
                                    )
                            }
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
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
    case search
}

@available(iOS 18.0, *)
struct SettingsView: View {
    @Binding var appearanceRaw: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var appearanceBinding: Binding<AppearancePreference> {
        Binding(
            get: { AppearancePreference(rawValue: appearanceRaw) ?? .dark },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: appearanceBinding) {
                        ForEach(AppearancePreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Dark is the default while we build. Light is fully supported.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Appearance")
                }
                .listRowBackground(RetroPlayTheme.card(for: colorScheme))

                Section {
                    Text(
                        """
                        RetroPlay only runs games you import yourself via Files. We do not ship, sell, or host ROMs, BIOS dumps, or copyrighted game files.

                        App Store Guideline 4.7: emulator apps may offer downloadable games; the developer is responsible for compliance. You must own the rights to any software you import.

                        No ROMs are included with this app.
                        """
                    )
                    .font(.body)
                    .listRowBackground(RetroPlayTheme.card(for: colorScheme))
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
                        .listRowBackground(RetroPlayTheme.card(for: colorScheme))
                    }
                } header: {
                    Text("Systems (P0)")
                }

                Section {
                    LabeledContent("GBA", value: "mGBA (playable)")
                    LabeledContent("PSP", value: "PPSSPP IR (linking)")
                    Text(PPSSPPDefaults.performanceNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(PPSSPPDefaults.appStoreIniSnippet)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Cores")
                }
                .listRowBackground(RetroPlayTheme.card(for: colorScheme))
            }
            .scrollContentBackground(.hidden)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RetroPlayTheme.section(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
