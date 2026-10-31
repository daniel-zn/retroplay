// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers
import RetroPlayCore
import UIKit

/// Root shell: the library, with filter, search, import and Settings as glass buttons in its
/// top bar (no tab bar). Appearance preference (dark default).
@available(iOS 18.0, *)
public struct RetroPlayRootView: View {
    @StateObject private var store = LibraryStore()
    @AppStorage("retroplay.appearance") private var appearanceRaw = AppearancePreference.dark.rawValue
    @State private var systemTab: SystemTab = .all
    @State private var showImporter = false
    /// What the Files picker is open for: games, or saves (files and folders).
    @State private var importKind = ImportKind.games
    /// A saves pick, scanned and matched, waiting for the player to confirm.
    @State private var saveImport: SaveImportSession?
    @State private var saveImportAccess: SecurityScopedAccess?
    @State private var savesScanning = false
    @State private var savesCommitting = false
    @State private var showSettings = false
    @State private var playGame: LibraryGame?
    @State private var navigator = ControllerNavigator()
    /// Search is a page pushed over the library from its top bar.
    @State private var showSearch = false
    @State private var searchPlayGame: LibraryGame?
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @AppStorage("retroplay.recentSearches") private var recentSearchesRaw = ""
    /// Keyboard focus for the search field. isSearchPresented alone can't re-show the
    /// keyboard once it's already true (after Search).
    @FocusState private var searchFocused: Bool
    /// Search results' scroll offset, and where the current drag started: a pull down
    /// hides the keyboard.
    @State private var searchScrollOffset: CGFloat = 0
    @State private var searchDragStart: CGFloat?
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
    @State private var boxArt = BoxArtUpdater()
    @AppStorage(BoxArtUpdater.enabledKey) private var downloadBoxArt = true
    @AppStorage("retroplay.librarySort") private var sortRaw = LibrarySort.recentlyPlayed.rawValue
    @AppStorage(LibraryLayout.storageKey) private var layoutRaw = LibraryLayout.grid.rawValue
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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

    private var layout: LibraryLayout {
        LibraryLayout(rawValue: layoutRaw) ?? .grid
    }

    /// Cover Flow in landscape needs the height for the covers: the big title gives way
    /// to the inline one.
    private var hidesLibraryTitle: Bool {
        layout == .coverFlow && verticalSizeClass == .compact && !store.games.isEmpty
    }

    private var showsInlineTitle: Bool { libraryTitleCollapsed || hidesLibraryTitle }

    private var filteredGames: [LibraryGame] {
        sort.sorted(store.games(matching: systemTab.systemID), lastPlayed: lastPlayed)
    }

    /// The filters the filter menu and L1 / R1 offer: All, the systems that have games, and
    /// the one showing (so an emptied filter stays marked).
    private var offeredTabs: [SystemTab] {
        let counts = tabCounts
        return SystemTab.allCases.filter { $0 == .all || $0 == systemTab || (counts[$0] ?? 0) > 0 }
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
        libraryNavigation
        #if DEBUG
        .overlay { if UserDefaults.standard.bool(forKey: "RetroPlaySmokePackages") { RetailPackageGallery() } }
        #endif
        .environment(\.font, RetroPlayFont.body)
        .environment(navigator)
        .task { navigator.start() }
        .onChange(of: !showSearch && !showSettings && !showImporter, initial: true) { _, front in
            navigator.libraryVisible = front
        }
        .onChange(of: navigator.event) { _, event in
            // L1 / R1 step through the system filters that have games.
            guard let event, event.context == .library,
                  event.command == .previousPage || event.command == .nextPage else { return }
            let tabs = offeredTabs
            guard let current = tabs.firstIndex(of: systemTab) ?? tabs.firstIndex(of: .all) else { return }
            let step = event.command == .nextPage ? 1 : -1
            withAnimation(.easeOut(duration: 0.15)) {
                systemTab = tabs[(current + step + tabs.count) % tabs.count]
            }
        }
        .tint(RetroPlayTheme.accent)
        // Set on the window, not via preferredColorScheme, so an open Settings sheet
        // follows the Appearance picker live (and "System" really clears the override).
        .onAppear { appearance.applyToWindows() }
        .onChange(of: appearanceRaw) { appearance.applyToWindows() }
        .onAppear {
            refreshActivity()
            RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
            showLibraryLoadError = store.libraryLoadFailureMessage != nil
            #if DEBUG
            // Debug builds only — Mac/sim smoke: -RetroPlaySmokeSystem <SystemID raw value>,
            // optionally -RetroPlaySmokeGame <part of the title> to pick one of that system's games.
            // simctl launch maps "-Key value" into UserDefaults as well as argv.
            // `-RetroPlaySmokeSettings YES`: open Settings, for screenshots.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSettings") {
                showSettings = true
            }
            // `-RetroPlaySmokeSaveImport YES`: the save import summary with sample rows.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSaveImport") {
                saveImport = SaveImportSession(batch: .smokeSample)
            }
            // `-RetroPlaySmokeLandscape YES`: the library in landscape too.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeLandscape") {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                }
            }
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
                let title = UserDefaults.standard.string(forKey: "RetroPlaySmokeGame")
                if let raw,
                   let sys = SystemID(rawValue: raw),
                   let game = store.games.first(where: {
                       $0.systemID == sys && (title.map($0.displayName.localizedCaseInsensitiveContains) ?? true)
                   }) {
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
            updateBoxArt()
        }
        .onChange(of: store.coversRevision) { _, _ in
            coverCache.coversReplaced()
        }
        .onChange(of: downloadBoxArt) { _, on in
            if on {
                boxArt.forgetLookups()
                updateBoxArt()
            }
        }
        // Pick up ROMs added or removed in Files → RetroPlay → Games.
        .task {
            await store.reconcileWithGamesFolder()
            updateBoxArt()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.reconcileWithGamesFolder() }
            }
        }
        .onChange(of: store.libraryLoadFailureMessage) { _, message in
            showLibraryLoadError = message != nil
        }
        // One picker for both: two .fileImporter modifiers on one view don't both present.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importKind == .games
                ? ImportContentTypes.allowedContentTypes
                : SaveImportContentTypes.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch importKind {
            case .games: handleImport(result)
            case .saves: handleSaveImport(result)
            }
        }
        // Swiped away or imported: either way the picked files are done with.
        .sheet(item: $saveImport, onDismiss: {
            saveImportAccess?.stop()
            saveImportAccess = nil
        }) { session in
            SaveImportSheet(batch: session.batch, committing: savesCommitting) { replace in
                commitSaveImport(session, replaceExisting: replace)
            }
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            // Presenting the picker in the same update that dismisses the sheet can drop it.
            if importAfterSettingsDismiss {
                importAfterSettingsDismiss = false
                openImporter(.games)
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
                            LibraryOnboardingView { openImporter(.games) }
                                .padding(.top, 12)
                        }
                    }
                } else if layout == .coverFlow {
                    LibraryCoverFlowView(
                        games: filteredGames,
                        filter: systemTab,
                        onSelect: { play($0) },
                        artworkProvider: { game in
                            loadCover(for: game)
                        },
                        onRequestDelete: { requestDelete($0) },
                        lastPlayed: lastPlayed,
                        missingGameIDs: store.missingGameIDs,
                        titleCollapsed: $libraryTitleCollapsed,
                        controllerNavigation: true
                    ) {
                        if !hidesLibraryTitle {
                            libraryTitle
                        }
                        if filteredGames.isEmpty {
                            EmptyFilterView(
                                tab: systemTab,
                                onImport: { openImporter(.games) },
                                onShowAll: { systemTab = .all }
                            )
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
                        missingGameIDs: store.missingGameIDs,
                        controllerNavigation: true
                    ) {
                        libraryTitle
                        if filteredGames.isEmpty {
                            EmptyFilterView(
                                tab: systemTab,
                                onImport: { openImporter(.games) },
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
            .navigationTitle(showsInlineTitle ? "RetroPlay" : "")
            .onChange(of: layoutRaw) { libraryTitleCollapsed = false }
            .navigationBarTitleDisplayMode(.inline)
            .retroPlayLibraryInlineNav()
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar {
                // The collapsed title, drawn here so it keeps the pixel font: the bar's own
                // title text falls back to the system font under SwiftUI's toolbar styling.
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text("RetroPlay")
                            .font(RetroPlayFont.sized(17, relativeTo: .headline))
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        // The filter, when the big title (which names it) is out of sight.
                        if systemTab != .all {
                            Text(systemTab.title)
                                .font(RetroPlayFont.caption2)
                                .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                        }
                    }
                    .opacity(showsInlineTitle ? 1 : 0)
                    .animation(.easeOut(duration: 0.15), value: showsInlineTitle)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if savesScanning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Finding saves")
                                .font(RetroPlayFont.caption2)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .retroPlayGlassChrome()
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Finding saves")
                    } else if store.importsInProgress > 0 {
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
                }
                // Import first (adds to the library), then the two ways to find a game (filter,
                // search) side by side, and Settings at the edge, as across iOS. One item, so
                // the four share one glass capsule, close together.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        LibraryImportMenu(
                            onImportGames: { openImporter(.games) },
                            onImportSaves: { openImporter(.saves) }
                        )
                        LibraryFilterMenu(
                            selection: $systemTab,
                            sort: sortBinding,
                            tabs: offeredTabs,
                            counts: tabCounts
                        )
                        .disabled(store.games.isEmpty)
                        LibraryTopBarButton(title: "Search", symbol: "magnifyingglass") {
                            openSearch()
                        }
                        LibraryTopBarButton(title: "Settings", symbol: "gearshape") {
                            showSettings = true
                        }
                    }
                }
            }
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
            .navigationDestination(isPresented: $showSearch) {
                searchPage
            }
        }
    }

    private var libraryTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RetroPlay")
                .font(RetroPlayFont.largeTitle)
                // One line: at accessibility sizes the title would otherwise split the word.
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                .accessibilityAddTraits(.isHeader)
            if !store.games.isEmpty {
                // With the filter chips gone, the title says which games are showing.
                Text(systemTab == .all
                    ? gameCountText(store.games.count)
                    : "\(systemTab.title) · \(filteredGames.count) of \(gameCountText(store.games.count))")
                    .font(RetroPlayFont.caption2)
                    .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    /// Opens Search with an empty field and the keyboard up.
    private func openSearch() {
        searchQuery = ""
        showSearch = true
        Task { @MainActor in
            // Once the page has been pushed: a field that isn't on screen yet can't take focus.
            try? await Task.sleep(for: .milliseconds(450))
            guard showSearch else { return }
            isSearchPresented = true
            searchFocused = true
        }
    }

    private var searchPage: some View {
        Group {
            if store.games.isEmpty {
                RetroPlayUnavailableView(
                    title: "No Games Yet",
                    systemImage: "magnifyingglass",
                    description: "Import games with + in the library, then search them here."
                )
            } else if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if recentSearches.isEmpty {
                    RetroPlayUnavailableView(
                        title: "Search Library",
                        systemImage: "magnifyingglass",
                        description: "Find games you already imported into RetroPlay."
                    )
                    .keyboardSwipeDownDismiss { searchFocused = false }
                } else {
                    recentSearchesList
                }
            } else if searchResults.isEmpty {
                RetroPlayUnavailableView(
                    title: "No Results",
                    systemImage: "magnifyingglass",
                    description: "No games match “\(searchQuery)”."
                )
                .keyboardSwipeDownDismiss { searchFocused = false }
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
        // Dragging the results down pulls the keyboard away with the finger, and a pull
        // down of a short list (nothing to scroll) hides it too.
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            searchScrollOffset = offset
            if let start = searchDragStart, offset < start - 24 {
                searchFocused = false
                searchDragStart = nil
            }
        }
        .onScrollPhaseChange { _, phase in
            searchDragStart = phase == .interacting ? searchScrollOffset : nil
        }
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
        .onSubmit(of: .search) { recordSearch() }
        .navigationDestination(item: $searchPlayGame) { game in
            PlayView(game: game, romURL: store.absoluteURL(for: game))
        }
    }

    private var recentSearches: [String] {
        RecentSearches.decode(recentSearchesRaw)
    }

    private func recordSearch() {
        recentSearchesRaw = RecentSearches.encode(RecentSearches.adding(searchQuery, to: recentSearches))
    }

    private var recentSearchesList: some View {
        List {
            Section {
                ForEach(recentSearches, id: \.self) { query in
                    Button {
                        searchQuery = query
                        recordSearch()
                    } label: {
                        Label(query, systemImage: "clock.arrow.circlepath")
                            .font(RetroPlayFont.caption)
                            .foregroundStyle(RetroPlayTheme.primaryText(for: colorScheme))
                    }
                    .accessibilityHint("Searches for \(query)")
                }
                .onDelete { offsets in
                    var list = recentSearches
                    list.remove(atOffsets: offsets)
                    recentSearchesRaw = RecentSearches.encode(list)
                }
            } header: {
                HStack {
                    Text("RECENT SEARCHES")
                        .font(RetroPlayFont.caption2)
                        .foregroundStyle(RetroPlayTheme.secondaryText(for: colorScheme))
                    Spacer()
                    Button("Clear") { recentSearchesRaw = "" }
                        .font(RetroPlayFont.caption2)
                        .accessibilityLabel("Clear recent searches")
                }
            }
            .listRowBackground(RetroPlayTheme.card(for: colorScheme))
        }
        .scrollContentBackground(.hidden)
    }

    /// Starts a game unless its ROM was removed in Files; then offers to delete the row.
    private func play(_ game: LibraryGame, fromSearch: Bool = false) {
        store.refreshMissingGames()
        if store.missingGameIDs.contains(game.id) {
            missingGame = game
            showMissingGame = true
        } else if fromSearch {
            recordSearch()
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

    /// Box art for games that don't have it yet (Settings → Download Box Art).
    private func updateBoxArt() {
        let games = store.games
        Task {
            await boxArt.update(games) { coverCache.coverChanged(gameID: $0) }
        }
    }

    private func loadCover(for game: LibraryGame) -> CoverArt? {
        coverCache.cover(for: game)
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
                    } else if summary.added.isEmpty, summary.covers.isEmpty, !urls.isEmpty {
                        presentImportResult(.error(
                            "No supported games in the selection. Unzip archives first; a picture becomes a cover when it's named like a game's file."
                        ))
                    }
                } catch {
                    presentImportResult(.error(error.localizedDescription))
                }
            }
        }
    }

    private func openImporter(_ kind: ImportKind) {
        importKind = kind
        showImporter = true
    }

    /// Scans and matches the picked saves off the main actor, then shows what would be imported.
    private func handleSaveImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportResult(.error(error.localizedDescription))
        case .success(let urls):
            guard !urls.isEmpty else { return }
            // Held until the sheet closes: files inside a picked folder read under its access.
            let access = SecurityScopedAccess(urls)
            let games = store.games
            savesScanning = true
            Task {
                let batch = await Task.detached(priority: .userInitiated) {
                    LibrarySaveImporter().plan(SaveFolderScanner.scan(urls), games: games)
                }.value
                savesScanning = false
                if batch.items.isEmpty, batch.skipped.isEmpty {
                    access.stop()
                    presentImportResult(.error(
                        "No saves in the selection. Pick battery saves (.sav, .srm), memory cards (.mcr, .mcd), PSP SAVEDATA folders, or a folder that holds them."
                    ))
                } else {
                    saveImportAccess = access
                    saveImport = SaveImportSession(batch: batch)
                }
            }
        }
    }

    private func commitSaveImport(_ session: SaveImportSession, replaceExisting: Bool) {
        guard !savesCommitting else { return }
        savesCommitting = true
        let batch = session.batch
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                LibrarySaveImporter().commit(batch, replaceExisting: replaceExisting)
            }.value
            savesCommitting = false
            saveImport = nil
            presentImportResult(Self.saveImportResult(outcome))
        }
    }

    private static func saveImportResult(_ outcome: SaveImportOutcome) -> ImportResultAlert {
        var lines: [String] = []
        let games = Set(outcome.imported.map(\.game.id)).count
        if !outcome.imported.isEmpty {
            let saves = outcome.imported.count == 1 ? "1 save" : "\(outcome.imported.count) saves"
            lines.append("Imported \(saves) for \(gameCountText(games)). Each game starts fresh the next time you play it, so it loads the imported save.")
        }
        if !outcome.kept.isEmpty {
            lines.append(outcome.kept.count == 1
                ? "Kept the save already here for \(outcome.kept[0].game.displayName)."
                : "Kept the saves already here for \(outcome.kept.count) games.")
        }
        for failure in outcome.failed.prefix(3) {
            lines.append("\(failure.name): \(failure.reason)")
        }
        if outcome.failed.count > 3 {
            lines.append("\(outcome.failed.count - 3) more couldn't be imported.")
        }
        let message = lines.joined(separator: "\n\n")
        return outcome.imported.isEmpty && !outcome.failed.isEmpty ? .error(message) : .notice(message)
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
           !summary.added.isEmpty || !summary.duplicates.isEmpty || !summary.failed.isEmpty || !summary.covers.isEmpty {
            let names = nameList(summary.unsupported)
            notices.append(summary.unsupported.count == 1
                ? "\(names) was skipped: it isn't a game RetroPlay plays, or a picture named like one."
                : "These were skipped because they aren't games RetroPlay plays, or pictures named like one: \(names).")
        }
        if !summary.covers.isEmpty, summary.added.isEmpty {
            notices.append(summary.covers.count == 1
                ? "Cover added from \(nameList(summary.covers))."
                : "\(summary.covers.count) covers added.")
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

@available(iOS 18.0, *)
private enum ImportKind {
    case games
    case saves
}

/// A scanned saves pick waiting for the player's go-ahead.
@available(iOS 18.0, *)
private struct SaveImportSession: Identifiable {
    let id = UUID()
    let batch: SaveImportBatch
}

#if DEBUG
@available(iOS 18.0, *)
private extension SaveImportBatch {
    /// Sample rows for `-RetroPlaySmokeSaveImport` screenshots.
    static var smokeSample: SaveImportBatch {
        let saves = SavePaths().savesDirectory
        func item(_ name: String, _ system: SystemID, _ source: String, replaces: Bool) -> SaveImportItem {
            let game = LibraryGame(displayName: name, systemID: system, relativePath: "\(name).rom")
            return SaveImportItem(
                game: game,
                sourceURL: URL(fileURLWithPath: "/\(source)"),
                sourceName: source,
                plan: SaveGameImportPlan(
                    sourceDescription: source,
                    destinationURL: saves.appendingPathComponent("\(name).sav"),
                    replacesExisting: replaces
                )
            )
        }
        return SaveImportBatch(
            items: [
                item("Golden Sun", .gba, "saves/mGBA/Golden Sun (USA).srm", replaces: false),
                item("Super Mario 64", .n64, "saves/Mupen64Plus-Next/Super Mario 64 (USA).srm", replaces: false),
                item("Final Fantasy VII", .ps1, "memcards/Final Fantasy VII (USA)_1.mcd", replaces: true),
                item("Patapon", .psp, "PSP/SAVEDATA/UCUS98711DATA00", replaces: false),
            ],
            skipped: [
                SkippedSave(name: "states/mGBA/Golden Sun (USA).state", reason: "Save states only work in the emulator that made them; import the battery save (.sav/.srm) instead."),
                SkippedSave(name: "saves/Snes9x/Chrono Trigger.srm", reason: "No game in your library has this name. Import the game first, or rename the save to match its file."),
            ],
            ignoredFiles: 12
        )
    }
}
#endif

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
