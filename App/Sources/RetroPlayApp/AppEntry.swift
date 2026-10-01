// SPDX-License-Identifier: GPL-3.0-or-later
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
    @State private var isSearchPresented = false
    /// Keyboard focus for the search field. isSearchPresented alone can't re-show the
    /// keyboard once it's already true (after Search or switching tabs).
    @FocusState private var searchFocused: Bool
    @State private var libraryTitleCollapsed = false
    @State private var importErrorMessage: String?
    @State private var showImportError = false
    @State private var gamePendingDelete: LibraryGame?
    @State private var showDeleteConfirm = false
    @State private var deleteErrorMessage: String?
    @State private var showDeleteError = false
    @State private var deleteRetentionNotice: String?
    @State private var showDeleteRetentionNotice = false
    @State private var showLibraryLoadError = false
    @State private var importNotice: String?
    @State private var showImportNotice = false
    /// Import results that came in while a game was open; shown once it closes.
    @State private var pendingImportResults: [ImportResultAlert] = []
    /// Settings → Import Games…: open the picker once the Settings sheet is gone.
    @State private var importAfterSettingsDismiss = false
    @State private var missingGame: LibraryGame?
    @State private var showMissingGame = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coverCache = CoverArtImageCache()
    @AppStorage("retroplay.librarySort") private var sortRaw = LibrarySort.recentlyPlayed.rawValue
    /// Newest save state per game (Play auto-saves on exit), refreshed after each session.
    @State private var lastPlayed: [UUID: Date] = [:]

    public init() {
        RetroPlayFont.registerBundledFont()
        RetroPlayFont.applyUIKitAppearance()
    }

    private var appearance: AppearancePreference {
        AppearancePreference(rawValue: appearanceRaw) ?? .dark
    }

    private var sort: LibrarySort {
        LibrarySort(rawValue: sortRaw) ?? .recentlyPlayed
    }

    private var sortBinding: Binding<LibrarySort> {
        Binding(get: { sort }, set: { sortRaw = $0.rawValue })
    }

    private var filteredGames: [LibraryGame] {
        sort.sorted(store.games(matching: systemTab.systemID), lastPlayed: lastPlayed)
    }

    private var tabCounts: [SystemTab: Int] {
        var counts: [SystemTab: Int] = [.all: store.games.count]
        for tab in SystemTab.allCases {
            if let system = tab.systemID {
                counts[tab] = store.games.filter { $0.systemID == system }.count
            }
        }
        return counts
    }

    /// Up to eight most recently played games in the current filter.
    private var recentGames: [LibraryGame] {
        let played = store.games(matching: systemTab.systemID).filter { lastPlayed[$0.id] != nil }
        return Array(LibrarySort.recentlyPlayed.sorted(played, lastPlayed: lastPlayed).prefix(8))
    }

    private func refreshActivity() {
        let games = store.games
        Task {
            let result = await LibraryActivity.lastPlayed(for: games)
            lastPlayed = result
        }
    }

    private var searchResults: [LibraryGame] {
        let matches = store.games.filter {
            LibrarySearch.matches($0, query: searchQuery) { system in
                [system.displayName, RetroPlayTheme.shortName(system), system.defaultCoreName]
            }
        }
        return LibrarySort.name.sorted(matches, lastPlayed: lastPlayed)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            libraryNavigation
                .tabItem {
                    Label("Library", systemImage: "square.grid.2x2.fill")
                        .font(RetroPlayFont.caption2)
                }
                .tag(RootTab.library)

            searchNavigation
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(RetroPlayFont.caption2)
                }
                .tag(RootTab.search)
        }
        .environment(\.font, RetroPlayFont.body)
        .tint(RetroPlayTheme.accent)
        .toolbarBackground(RetroPlayTheme.canvas(for: colorScheme), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background {
            TabBarReselectHandler { index in
                if index == RootTab.search.rawValue {
                    isSearchPresented = true
                    searchFocused = true
                }
            }
        }
        // Set on the window, not via preferredColorScheme, so an open Settings sheet
        // follows the Appearance picker live (and "System" really clears the override).
        .onAppear { appearance.applyToWindows() }
        .onChange(of: appearanceRaw) { appearance.applyToWindows() }
        .onAppear {
            refreshActivity()
            RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
            showLibraryLoadError = store.libraryLoadFailureMessage != nil
            #if DEBUG
            // Debug builds only — Mac/sim smoke: -RetroPlaySmokeSystem nds|n64|gba|psp
            // simctl launch maps "-Key value" into UserDefaults as well as argv.
            if playGame == nil {
                let args = ProcessInfo.processInfo.arguments
                var raw: String?
                if let idx = args.firstIndex(of: "-RetroPlaySmokeSystem"),
                   args.index(after: idx) < args.endIndex {
                    raw = args[args.index(after: idx)]
                }
                if raw == nil {
                    raw = UserDefaults.standard.string(forKey: "RetroPlaySmokeSystem")
                }
                if let raw,
                   let sys = SystemID(rawValue: raw),
                   let game = store.games.first(where: { $0.systemID == sys }) {
                    playGame = game
                    NSLog("RP_SMOKE autoplay system=%@ game=%@", raw, game.displayName)
                } else if let raw {
                    NSLog("RP_SMOKE no library game for system=%@ games=%lu", raw, store.games.count)
                }
            }
            #endif
        }
        .onChange(of: colorScheme) { _, scheme in
            RetroPlayNavigationBarChrome.apply(colorScheme: scheme)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIContentSizeCategory.didChangeNotification
        )) { _ in
            RetroPlayFont.applyUIKitAppearance()
            RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme, force: true)
        }
        // Back from a game (it auto-saved) or the library changed: refresh "last played".
        .onChange(of: playGame) { _, game in
            if game == nil {
                refreshActivity()
                showPendingImportResults()
            }
        }
        .onChange(of: searchPlayGame) { _, game in
            if game == nil {
                refreshActivity()
                showPendingImportResults()
            }
        }
        .onChange(of: store.games) { _, _ in
            refreshActivity()
            coverCache.forgetMissing()
        }
        // Pick up ROMs added or removed in Files → RetroPlay → Games.
        .task { await store.reconcileWithGamesFolder() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.reconcileWithGamesFolder() }
            }
        }
        .onChange(of: store.libraryLoadFailureMessage) { _, message in
            showLibraryLoadError = message != nil
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .search {
                // First land on Search: show the field; re-tap forces focus via TabBarReselectHandler.
                isSearchPresented = true
                searchFocused = true
            }
            if tab == .library {
                libraryTitleCollapsed = false
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: ImportContentTypes.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            // Presenting the picker in the same update that dismisses the sheet can drop it.
            if importAfterSettingsDismiss {
                importAfterSettingsDismiss = false
                showImporter = true
            }
        }) {
            SettingsView(
                appearanceRaw: $appearanceRaw,
                gameCounts: tabCounts,
                storageDirectories: store.storageDirectoryURLs,
                onImport: {
                    importAfterSettingsDismiss = true
                    showSettings = false
                }
            )
        }
        .retroPlayAlert(
            "Library Unavailable",
            message: store.libraryLoadFailureMessage
                ?? "Your library file could not be read. A copy was kept; games in Files → RetroPlay → Games are added back automatically.",
            isPresented: $showLibraryLoadError,
            actions: [.cancel("OK")]
        )
        .retroPlayAlert(
            "Import failed",
            message: importErrorMessage ?? "Could not import the selected files.",
            isPresented: $showImportError,
            actions: [.cancel("OK")]
        )
        .retroPlayAlert(
            "Import",
            message: importNotice ?? "",
            isPresented: $showImportNotice,
            actions: [.cancel("OK")]
        )
        .retroPlayAlert(
            "Game File Missing",
            message: missingGame.map {
                "\($0.displayName) is no longer in Files → RetroPlay → Games. Put the file back to keep playing, or delete the game to also remove its saves and states."
            } ?? "This game's file is no longer in the Games folder.",
            isPresented: $showMissingGame,
            actions: [
                .cancel("OK") { missingGame = nil },
                .destructive("Delete") {
                    if let missingGame {
                        deleteGame(missingGame)
                    }
                    missingGame = nil
                }
            ]
        )
        .retroPlayAlert(
            "Delete Game?",
            message: gamePendingDelete.map {
                "This removes \($0.displayName) from the library and deletes its imported file, saves, and states on this device."
            } ?? "This removes the selected game and its data from this device.",
            isPresented: $showDeleteConfirm,
            actions: [
                .cancel("Cancel") { gamePendingDelete = nil },
                .destructive("Delete") {
                    if let gamePendingDelete {
                        deleteGame(gamePendingDelete)
                    }
                }
            ]
        )
        .retroPlayAlert(
            "Couldn't Delete",
            message: deleteErrorMessage ?? "The game file or save data could not be removed.",
            isPresented: $showDeleteError,
            actions: [.cancel("OK")]
        )
        .retroPlayAlert(
            "PSP Save Data Retained",
            message: deleteRetentionNotice ?? "Battery save data was left on the virtual memory stick.",
            isPresented: $showDeleteRetentionNotice,
            actions: [.cancel("OK")]
        )
    }

    private var libraryNavigation: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            libraryTitle
                            LibraryOnboardingView { showImporter = true }
                                .padding(.top, 12)
                        }
                    }
                } else {
                    // Custom large title in the scroll header (system large titles stay blank on black).
                    LibraryGridView(
                        games: filteredGames,
                        onSelect: { play($0) },
                        artworkProvider: { game in
                            loadCover(for: game)
                        },
                        onRequestDelete: { requestDelete($0) },
                        titleCollapsed: $libraryTitleCollapsed,
                        lastPlayed: lastPlayed,
                        missingGameIDs: store.missingGameIDs
                    ) {
                        libraryTitle
                        if !recentGames.isEmpty {
                            ContinuePlayingRow(
                                games: recentGames,
                                lastPlayed: lastPlayed,
                                artworkProvider: { loadCover(for: $0) },
                                onPlay: { play($0) }
                            )
                            .padding(.top, 6)
                            .padding(.bottom, 18)
                        }
                        LibraryFilterBar(selection: $systemTab, sort: sortBinding, counts: tabCounts)
                            .padding(.bottom, 12)
                        if filteredGames.isEmpty {
                            EmptyFilterView(
                                tab: systemTab,
                                onImport: { showImporter = true },
                                onShowAll: { systemTab = .all }
                            )
                        } else {
                            SectionHeading(
                                title: systemTab == .all ? "All Games" : systemTab.title,
                                trailing: sort.title
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle(libraryTitleCollapsed ? "RetroPlay" : "")
            .navigationBarTitleDisplayMode(.inline)
            .retroPlayLibraryInlineNav()
            .toolbarBackground(RetroPlayTheme.canvas(for: colorScheme), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if store.importsInProgress > 0 {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Importing \(store.importsInProgress)")
                                .font(RetroPlayFont.caption2)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .retroPlayGlassChrome()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Importing \(gameCountText(store.importsInProgress))")
                    }
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
                }
            }
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
        }
    }

    private var libraryTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RetroPlay")
                .font(RetroPlayFont.largeTitle)
                // One line: at accessibility sizes the pixel face would split the word.
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .accessibilityAddTraits(.isHeader)
            if !store.games.isEmpty {
                Text(gameCountText(store.games.count))
                    .font(RetroPlayFont.caption2)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private var searchNavigation: some View {
        NavigationStack {
            Group {
                if store.games.isEmpty {
                    RetroPlayUnavailableView(
                        title: "No Games Yet",
                        systemImage: "magnifyingglass",
                        description: "Import games from the Library tab, then search them here."
                    )
                } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    RetroPlayUnavailableView(
                        title: "Search Library",
                        systemImage: "magnifyingglass",
                        description: "Find games you already imported into RetroPlay."
                    )
                } else if searchResults.isEmpty {
                    RetroPlayUnavailableView(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        description: "No games match “\(searchQuery)”."
                    )
                } else {
                    LibraryGridView(
                        games: searchResults,
                        onSelect: { play($0, fromSearch: true) },
                        artworkProvider: { game in
                            loadCover(for: game)
                        },
                        onRequestDelete: { requestDelete($0) },
                        lastPlayed: lastPlayed,
                        missingGameIDs: store.missingGameIDs
                    ) {
                        SectionHeading(
                            title: searchResults.count == 1 ? "1 Result" : "\(searchResults.count) Results"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            // Opaque SwiftUI toolbarBackground covers the large title; UIKit scroll-edge is clear.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .retroPlayNavigationTitleChrome(for: colorScheme)
            .searchable(
                text: $searchQuery,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Games"
            )
            .searchFocused($searchFocused)
            .navigationDestination(item: $searchPlayGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
        }
    }

    /// Starts a game unless its ROM was removed in Files; then offers to delete the row.
    private func play(_ game: LibraryGame, fromSearch: Bool = false) {
        store.refreshMissingGames()
        if store.missingGameIDs.contains(game.id) {
            missingGame = game
            showMissingGame = true
        } else if fromSearch {
            searchPlayGame = game
        } else {
            playGame = game
        }
    }

    private func requestDelete(_ game: LibraryGame) {
        gamePendingDelete = game
        showDeleteConfirm = true
    }

    private func deleteGame(_ game: LibraryGame) {
        defer {
            // The row is gone even when some files could not be removed.
            if !store.games.contains(where: { $0.id == game.id }) {
                coverCache.remove(gameID: game.id)
                if playGame?.id == game.id { playGame = nil }
                if searchPlayGame?.id == game.id { searchPlayGame = nil }
            }
        }
        do {
            let cleanup = try store.remove(game)
            if cleanup.retainedPSPSavedata, let reason = cleanup.retainedPSPSavedataReason {
                deleteRetentionNotice = reason
                showDeleteRetentionNotice = true
            }
        } catch {
            deleteErrorMessage = error.localizedDescription
            showDeleteError = true
        }
        gamePendingDelete = nil
    }

    private func loadCover(for game: LibraryGame) -> UIImage? {
        coverCache.image(for: game)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportResult(.error(error.localizedDescription))
        case .success(let urls):
            // Copies run off the main actor; the toolbar shows progress until rows appear.
            Task {
                do {
                    let summary = try await store.importInBackground(from: urls)
                    // Jump to a system only when the whole import is that system.
                    let systems = Set(summary.added.map(\.systemID))
                    if systems.count == 1, let only = systems.first,
                       let tab = SystemTab.allCases.first(where: { $0.systemID == only }) {
                        systemTab = tab
                    } else if systems.count > 1 {
                        systemTab = .all
                    }
                    let notices = Self.importNotices(for: summary)
                    if !notices.isEmpty {
                        presentImportResult(.notice(notices.joined(separator: "\n\n")))
                    } else if summary.added.isEmpty, !urls.isEmpty {
                        presentImportResult(.error(
                            "No supported games in the selection. RetroPlay imports .gba, .z64/.n64/.v64, .nds and .iso/.cso/.chd/.pbp files — unzip archives first."
                        ))
                    }
                } catch {
                    presentImportResult(.error(error.localizedDescription))
                }
            }
        }
    }

    /// What to tell the player about files that were not added. Empty when everything went in.
    private static func importNotices(for summary: LibraryImportSummary) -> [String] {
        var notices: [String] = []
        if let failure = summary.failed.first, summary.failed.count == 1 {
            notices.append("\(failure.fileName) could not be imported. \(failure.reason)")
        } else if !summary.failed.isEmpty {
            let names = nameList(summary.failed.map(\.fileName))
            notices.append("These could not be imported: \(names). Make sure they are downloaded and readable, then try again.")
        }
        if !summary.duplicates.isEmpty {
            let names = nameList(summary.duplicates)
            notices.append(summary.duplicates.count == 1
                ? "\(names) is already in your library, so it was not copied again."
                : "These are already in your library, so they were not copied again: \(names).")
        }
        if !summary.unsupported.isEmpty,
           !summary.added.isEmpty || !summary.duplicates.isEmpty || !summary.failed.isEmpty {
            let names = nameList(summary.unsupported)
            notices.append(summary.unsupported.count == 1
                ? "\(names) was skipped: RetroPlay plays Game Boy Advance, Nintendo 64, Nintendo DS and PSP games."
                : "These were skipped because RetroPlay plays Game Boy Advance, Nintendo 64, Nintendo DS and PSP games: \(names).")
        }
        return notices
    }

    /// "A, B, C" — or the first few and "and N more", so a big pick cannot make the alert huge.
    private static func nameList(_ names: [String], limit: Int = 5) -> String {
        guard names.count > limit else { return names.joined(separator: ", ") }
        return names.prefix(limit).joined(separator: ", ") + ", and \(names.count - limit) more"
    }

    /// The alert would cover a running game and block its controls, so a result that comes in
    /// mid-game waits until the player is back in the library.
    private func presentImportResult(_ result: ImportResultAlert) {
        if playGame != nil || searchPlayGame != nil {
            pendingImportResults.append(result)
        } else {
            show(result)
        }
    }

    private func showPendingImportResults() {
        guard playGame == nil, searchPlayGame == nil, !pendingImportResults.isEmpty else { return }
        let results = pendingImportResults
        pendingImportResults = []
        // Several imports may have finished during one game: show them in one alert.
        let message = results.map(\.message).joined(separator: "\n\n")
        show(results.allSatisfy(\.isError) ? .error(message) : .notice(message))
    }

    private func show(_ result: ImportResultAlert) {
        switch result {
        case .notice(let message):
            importNotice = message
            showImportNotice = true
        case .error(let message):
            importErrorMessage = message
            showImportError = true
        }
    }
}

/// An import outcome for the "Import" notice or the "Import failed" alert.
@available(iOS 18.0, *)
private enum ImportResultAlert {
    case notice(String)
    case error(String)

    var message: String {
        switch self {
        case .notice(let message), .error(let message):
            return message
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

@available(iOS 18.0, *)
private enum RootTab: Int, Hashable {
    case library = 0
    case search = 1
}
