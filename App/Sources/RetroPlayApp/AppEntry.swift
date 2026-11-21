// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers
import RetroPlayCore
import UIKit

/// Root shell: the library, with import, filter and Settings as glass buttons in its top bar
/// (no tab bar) and iOS's search field under its large title, revealed by pulling the library
/// down. Appearance preference (dark default).
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
    /// No game may start while saves are being found, reviewed or written.
    @State private var saveImports = SaveImportSessions()
    /// The session `saveImport` belongs to, for when its sheet closes.
    @State private var saveImportID: UUID?
    /// The running scan, so "Finding saves" can stop it.
    @State private var saveScanTask: Task<Void, Never>?
    /// Stop sets it: the scan's listings and coordinated reads end at their next check.
    @State private var saveScanCancellation: ImportCancellation?
    @State private var showSettings = false
    /// The import button in the top bar (follows `importsInProgress`, animated).
    @State private var showsImports = false
    /// The imports' popover is open: their button stays until it closes (removing a
    /// popover's anchor while it's up leaves it stranded over a dead bar).
    @State private var showsImportStatus = false
    @State private var importTime: ImportBackgroundTime?
    @State private var playGame: LibraryGame?
    @State private var navigator = ControllerNavigator()
    /// The library's search field (iOS's own, in the navigation bar's drawer): shown by a pull
    /// down, or Command-F; while it's active the library shows what it finds.
    @State private var searchQuery = ""
    @State private var isSearchPresented = false
    @AppStorage("retroplay.recentSearches") private var recentSearchesRaw = ""
    /// Keyboard focus for the search field. isSearchPresented alone can't re-show the
    /// keyboard once it's already true.
    @FocusState private var searchFocused: Bool
    /// Search results' scroll offset, and where the current drag started: a pull down
    /// hides the keyboard.
    @State private var searchScrollOffset: CGFloat = 0
    @State private var searchDragStart: CGFloat?
    @State private var alert: LibraryAlert?
    /// Import results that came in while a game was open; shown once it closes.
    @State private var pendingImportResults: [ImportResultAlert] = []
    /// Settings → Import Games…: open the picker once the Settings sheet is gone.
    @State private var importAfterSettingsDismiss = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var coverCache = CoverArtImageCache()
    @State private var boxArt = BoxArtUpdater()
    @AppStorage(BoxArtUpdater.enabledKey) private var downloadBoxArt = true
    @AppStorage("retroplay.librarySort") private var sortRaw = LibrarySort.recentlyPlayed.rawValue
    @AppStorage(LibraryLayout.storageKey) private var layoutRaw = LibraryLayout.grid.rawValue
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

    /// Searching: the field is up or holds a query; the library shows what it finds.
    private var isSearching: Bool {
        isSearchPresented || !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Under the title: how many games, and which filter is showing.
    private var librarySubtitle: String {
        guard !store.games.isEmpty else { return "" }
        return systemTab == .all
            ? gameCountText(store.games.count)
            : "\(systemTab.title) · \(store.games(matching: systemTab.systemID).count) of \(gameCountText(store.games.count))"
    }

    private var filteredGames: [LibraryGame] {
        sort.sorted(store.games(matching: systemTab.systemID), lastPlayed: lastPlayed)
    }

    /// The filters the filter menu and L1 / R1 offer: All, the systems that have games, and
    /// the one showing (so an emptied filter stays marked).
    private func offeredTabs(_ counts: [SystemTab: Int]) -> [SystemTab] {
        SystemTab.allCases.filter { $0 == .all || $0 == systemTab || (counts[$0] ?? 0) > 0 }
    }

    private var tabCounts: [SystemTab: Int] {
        let bySystem = Dictionary(grouping: store.games, by: \.systemID).mapValues(\.count)
        var counts: [SystemTab: Int] = [.all: store.games.count]
        for tab in SystemTab.allCases {
            if let system = tab.systemID { counts[tab] = bySystem[system] ?? 0 }
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
        .overlay(alignment: .topLeading) {
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeAccessibilityProbe") { AccessibilityProbeOverlay() }
        }
        #endif
        .environment(\.font, RetroPlayFont.body)
        .retroPlayTypography()
        .environment(navigator)
        .task { navigator.start() }
        .onChange(of: !isSearching && !showSettings && !showImporter, initial: true) { _, front in
            navigator.libraryVisible = front
        }
        // Command-F (the app's Search Library command) while the library is in front.
        .focusedSceneValue(\.retroPlaySearchLibrary,
                           isGameOpen || showSettings ? nil : RetroPlaySearchAction { activateSearch() })
        .onChange(of: navigator.event) { _, event in
            // L1 / R1 step through the system filters that have games.
            guard let event, event.context == .library,
                  event.command == .previousPage || event.command == .nextPage else { return }
            let tabs = offeredTabs(tabCounts)
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
            if importTime == nil { importTime = ImportBackgroundTime(store) }
            refreshActivity()
            RetroPlayNavigationBarChrome.apply(colorScheme: colorScheme)
            if let message = store.libraryLoadFailureMessage { alert = .libraryUnavailable(message) }
            #if DEBUG
            // Debug builds only — Mac/sim smoke: -RetroPlaySmokeSystem <SystemID raw value>,
            // optionally -RetroPlaySmokeGame <part of the title> to pick one of that system's games.
            // simctl launch maps "-Key value" into UserDefaults as well as argv.
            // `-RetroPlaySmokeSettings YES`: open Settings, for screenshots.
            // `-RetroPlaySmokeKeptSave YES`: a GBA save waiting for its game (Settings → Saves).
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeKeptSave") {
                let kept = KeptSaves.url(system: .gba, fileName: "Smoke Waiting Game (USA).srm", paths: SavePaths())
                try? FileManager.default.createDirectory(at: kept.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: 8_192).write(to: kept)
            }
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSettings") {
                showSettings = true
            }
            // `-RetroPlaySmokeSaveFolder YES`: import a folder with a save three folders down
            // (SmokeSaves/A/B/C/Zelda.sav), through the same path as a picked folder.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSaveFolder") {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SmokeSaves", isDirectory: true)
                let save = folder.appendingPathComponent("A/B/C/Zelda.sav")
                try? FileManager.default.createDirectory(at: save.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? Data(count: 8_192).write(to: save)
                handleSaveImport(.success([folder]))
            }
            // `-RetroPlayTestImportSeconds N`: import a 16 MB "Import Test.gba" (picked from
            // tmp, as from Files) that takes about N seconds to copy.
            if let seconds = Double(UserDefaults.standard.string(forKey: "RetroPlayTestImportSeconds") ?? ""), seconds > 0 {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("Import Test.gba")
                let chunks = 16
                try? Data(count: chunks << 20).write(to: file)
                LibraryStore.testChunkPause = seconds / Double(chunks)
                for game in store.games where game.relativePath.hasPrefix("Import Test") {
                    _ = try? store.remove(game)
                }
                handleImport(.success([file]))
            }
            // `-RetroPlayTestImportStall YES`: import "Stalled Test.gba", a pipe nothing writes,
            // so its copy waits forever, as from a share that stopped answering.
            if UserDefaults.standard.bool(forKey: "RetroPlayTestImportStall") {
                let file = FileManager.default.temporaryDirectory.appendingPathComponent("Stalled Test.gba")
                try? FileManager.default.removeItem(at: file)
                mkfifo(file.path, 0o644)
                handleImport(.success([file]))
            }
            // `-RetroPlaySmokeSaveScan YES`: a save scan that runs until it's stopped, to see
            // the library while saves are found.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSaveScan"), let id = saveImports.beginScan() {
                saveImportID = id
            }
            // `-RetroPlaySmokeSaveImport YES`: the save import summary with sample rows.
            if UserDefaults.standard.bool(forKey: "RetroPlaySmokeSaveImport") {
                if let id = saveImports.beginScan(), saveImports.scanFinished(id) {
                    saveImportID = id
                    saveImport = SaveImportSession(id: id, batch: .smokeSample)
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
        .onChange(of: store.importsInProgress > 0 || showsImportStatus) { _, shows in
            withAnimation { showsImports = shows }
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
            if let message {
                alert = .libraryUnavailable(message)
            } else if case .libraryUnavailable = alert {
                alert = nil
            }
        }
        // One picker for both: two .fileImporter modifiers on one view don't both present.
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importKind == .games
                ? ImportContentTypes.allowedContentTypes
                : SaveImportContentTypes.folderContentTypes,
            // Saves: one folder (open it, then Open). The folder picker has no Select mode for
            // several folders; every picked URL is scanned all the same.
            allowsMultipleSelection: importKind == .games
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
            if let id = saveImportID { saveImports.cancel(id) }
            saveImportID = nil
        }) { session in
            SaveImportSheet(batch: session.batch, committing: saveImports.phase == .committing) { replace in
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
                games: store.games,
                onImport: {
                    importAfterSettingsDismiss = true
                    showSettings = false
                }
            )
            // No Done button: swipe down closes it, like the other sheets.
            .presentationDragIndicator(.visible)
        }
        .modifier(LibraryAlertPresenter(alert: $alert, buttons: alertButtons))
    }

    private var libraryNavigation: some View {
        #if DEBUG
        LibraryWorkProbe.library += 1
        #endif
        return NavigationStack {
            Group {
                if isSearching {
                    searchContent
                } else if store.games.isEmpty {
                    ScrollView {
                        LibraryOnboardingView { openImporter(.games) }
                            .padding(.top, 12)
                    }
                } else {
                    // Sorted once per pass (the headers below are run again as the covers move).
                    let games = filteredGames
                    if layout == .coverFlow {
                        LibraryCoverFlowView(
                            games: games,
                            filter: systemTab,
                            onSelect: { play($0) },
                            artworkProvider: { game in
                                loadCover(for: game)
                            },
                            onRequestDelete: { requestDelete($0) },
                            lastPlayed: lastPlayed,
                            missingGameIDs: store.missingGameIDs,
                            controllerNavigation: true,
                            artRevision: coverCache.revision
                        ) {
                            if games.isEmpty {
                                EmptyFilterView(
                                    tab: systemTab,
                                    onImport: { openImporter(.games) },
                                    onShowAll: { systemTab = .all }
                                )
                            }
                        }
                    } else {
                        LibraryGridView(
                            games: games,
                            onSelect: { play($0) },
                            artworkProvider: { game in
                                loadCover(for: game)
                            },
                            onRequestDelete: { requestDelete($0) },
                            lastPlayed: lastPlayed,
                            missingGameIDs: store.missingGameIDs,
                            controllerNavigation: true
                        ) {
                            if games.isEmpty {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RetroPlayTheme.canvas(for: colorScheme))
            // iOS's large title (collapsing into the bar as the library scrolls; inline in
            // landscape), with the game count under it.
            .retroPlayLargeTitle("RetroPlay", subtitle: librarySubtitle)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .retroPlayNavigationTitleChrome(for: colorScheme, content: [librarySubtitle, "\(showsImports)"])
            // The search field sits hidden under the title until the library is pulled down
            // (Cover Flow's covers sit in a page that pulls down the same way).
            .searchable(
                text: $searchQuery,
                isPresented: $isSearchPresented,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Games"
            )
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { recordSearch() }
            .toolbar {
                // Import first (adds to the library), then the filter, and Settings at the edge,
                // as across iOS: the system's own items, one glass group. While games copy in,
                // their status joins the group at its start.
                let counts = tabCounts
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsImports {
                        LibraryImportsButton(imports: store.imports, showsStatus: $showsImportStatus)
                    }
                    LibraryImportMenu(
                        onImportGames: { openImporter(.games) },
                        onImportSaves: { openImporter(.saves) }
                    )
                    .disabled(!saveImports.allowsImporting)
                    LibraryFilterMenu(
                        selection: $systemTab,
                        sort: sortBinding,
                        tabs: offeredTabs(counts),
                        counts: counts
                    )
                    .disabled(store.games.isEmpty)
                    LibraryTopBarButton(title: "Settings", symbol: "gearshape") {
                        showSettings = true
                    }
                }
                // Saves being found, as Mail shows its status: the bottom bar's status item, with
                // Stop beside it (a big folder can take a while, and games can't start meanwhile).
                if saveImports.phase == .scanning {
                    ToolbarItem(placement: .status) {
                        LibraryImportStatus(text: "Finding saves")
                            .accessibilityIdentifier("library.findingSaves")
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Stop", systemImage: "xmark", role: .cancel) {
                            cancelSaveScan()
                        }
                        .accessibilityLabel("Stop Finding Saves")
                        .accessibilityIdentifier("library.stopFindingSaves")
                    }
                }
            }
            .navigationDestination(item: $playGame) { game in
                PlayView(game: game, romURL: store.absoluteURL(for: game))
            }
        }
        .retroPlayScrollEdge()
        #if DEBUG
        .libraryWorkProbe()
        #endif
    }

    /// Command-F: the search field up (pulled into view if it was hidden) with the cursor in it.
    private func activateSearch() {
        isSearchPresented = true
        Task { @MainActor in
            // Once the field is on screen: a field that isn't there yet can't take focus.
            try? await Task.sleep(for: .milliseconds(100))
            searchFocused = true
        }
    }

    /// What the library shows while searching: recent searches, then the matching games (always
    /// as the grid).
    private var searchContent: some View {
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
            } else {
                let results = searchResults
                if results.isEmpty {
                    RetroPlayUnavailableView(
                        title: "No Results",
                        systemImage: "magnifyingglass",
                        description: "No games match “\(searchQuery)”."
                    )
                    .keyboardSwipeDownDismiss { searchFocused = false }
                } else {
                    LibraryGridView(
                        games: results,
                        onSelect: { play($0, fromSearch: true) },
                        artworkProvider: { game in
                            loadCover(for: game)
                        },
                        onRequestDelete: { requestDelete($0) },
                        lastPlayed: lastPlayed,
                        missingGameIDs: store.missingGameIDs
                    ) {
                        SectionHeading(
                            title: results.count == 1 ? "1 Result" : "\(results.count) Results"
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
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
                            .font(RetroPlayFont.body)
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
                        .font(RetroPlayFont.footnote)
                        .accessibilityLabel("Clear recent searches")
                }
            }
            .listRowBackground(RetroPlayTheme.card(for: colorScheme))
        }
        .scrollContentBackground(.hidden)
    }

    /// Starts a game unless its ROM was removed in Files; then offers to delete the row.
    private func play(_ game: LibraryGame, fromSearch: Bool = false) {
        // A game's core would write its old save over the one being imported.
        guard saveImports.allowsLaunchingGames else { return }
        if store.refreshMissing(game) {
            alert = .missingGame(game)
        } else {
            if fromSearch { recordSearch() }
            playGame = game
        }
    }

    private func requestDelete(_ game: LibraryGame) {
        alert = .confirmDelete(game)
    }

    private func deleteGame(_ game: LibraryGame) {
        defer {
            // The row is gone even when some files could not be removed.
            if !store.games.contains(where: { $0.id == game.id }) {
                coverCache.remove(gameID: game.id)
                if playGame?.id == game.id { playGame = nil }
            }
        }
        // Deletes start from an alert, which the system dismisses after this runs: a follow-up
        // alert is shown on the next turn so the dismissal doesn't clear it.
        var followUp: LibraryAlert?
        do {
            let cleanup = try store.remove(game)
            if cleanup.retainedPSPSavedata, let reason = cleanup.retainedPSPSavedataReason {
                followUp = .pspSaveRetained(reason)
            }
        } catch {
            followUp = .deleteFailed(error.localizedDescription)
        }
        if let followUp { Task { alert = followUp } }
    }

    @ViewBuilder
    private func alertButtons(_ alert: LibraryAlert) -> some View {
        switch alert {
        case .missingGame(let game), .confirmDelete(let game):
            Button(alert.isMissingGame ? "OK" : "Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { deleteGame(game) }
        default:
            Button("OK", role: .cancel) {}
        }
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
            // Copies run off the main actor; the top bar's import button shows their progress
            // until rows appear.
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
                    } else if summary.added.isEmpty, summary.covers.isEmpty, summary.cancelled.isEmpty, !urls.isEmpty {
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

    private var isGameOpen: Bool { playGame != nil }

    private func openImporter(_ kind: ImportKind) {
        // One import at a time: a second pick can't start while saves are found or written.
        guard saveImports.allowsImporting else { return }
        importKind = kind
        showImporter = true
    }

    /// Scans and matches the picked saves off the main actor, then shows what would be imported.
    private func handleSaveImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            presentImportResult(.error(error.localizedDescription))
        case .success(let urls):
            guard !urls.isEmpty, let id = saveImports.beginScan() else { return }
            // Held until the sheet closes: files inside a picked folder read under its access.
            let access = SecurityScopedAccess(urls)
            // An alias the picker handed over is read where it points (each pick logged).
            let readURLs = access.readURLs
            let games = store.games
            saveImportID = id
            let cancellation = ImportCancellation()
            saveScanCancellation = cancellation
            saveScanTask = Task {
                let batch = await Self.findSaves(in: readURLs, games: games, cancellation: cancellation)
                // A stale or cancelled session (ended meanwhile) changes nothing.
                guard saveImports.scanFinished(id) else {
                    access.stop()
                    return
                }
                saveScanTask = nil
                if !SaveImportPhase.mayWrite(gameOpen: isGameOpen) {
                    saveImports.end(id)
                    saveImportID = nil
                    access.stop()
                    presentImportResult(.error("Close the game, then import the saves again."))
                } else if batch.items.isEmpty, batch.skipped.isEmpty {
                    saveImports.end(id)
                    saveImportID = nil
                    access.stop()
                    let others = batch.otherSystemSaves
                    let place = urls.count == 1 ? "this folder" : "these folders"
                    let message = others > 0
                        ? "No saves for systems RetroPlay plays in \(place). \(others == 1 ? "1 save is" : "\(others) saves are") for other systems."
                        : "No saves in \(place). Pick a folder that holds battery saves (.sav, .srm), memory cards (.mcr, .mcd) or PSP SAVEDATA folders."
                    // What was looked at, so a folder that should have worked says why it didn't.
                    let refused = access.refused.map { "“\($0.lastPathComponent)”: Files didn't give RetroPlay access to it" }
                    let notes = refused + batch.notes
                    let looked = notes.isEmpty ? "" : "\n\n" + notes.joined(separator: "\n")
                    presentImportResult(.error(message + looked))
                } else {
                    saveImportAccess = access
                    saveImport = SaveImportSession(id: id, batch: batch)
                }
            }
        }
    }

    /// Off the main actor, and a child of the scan task, so cancelling that stops the walk.
    private nonisolated static func findSaves(
        in urls: [URL],
        games: [LibraryGame],
        cancellation: ImportCancellation
    ) async -> SaveImportBatch {
        LibrarySaveImporter().plan(SaveFolderScanner.scan(urls, cancellation: cancellation), games: games)
    }

    /// Ends the scan's session at once (games can start again); the walk stops at its next entry.
    private func cancelSaveScan() {
        saveScanCancellation?.cancel()
        saveScanCancellation = nil
        saveScanTask?.cancel()
        saveScanTask = nil
        if let id = saveImportID {
            saveImports.cancel(id)
            saveImportID = nil
        }
    }

    private func commitSaveImport(_ session: SaveImportSession, replaceExisting: Bool) {
        // Checked again right before writing: nothing may have started a game meanwhile.
        guard saveImports.beginCommit(session.id, gameOpen: isGameOpen) else {
            if isGameOpen {
                saveImport = nil
                presentImportResult(.error("Close the game, then import the saves again."))
            }
            return
        }
        let batch = session.batch
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                LibrarySaveImporter().commit(batch, replaceExisting: replaceExisting)
            }.value
            saveImports.end(session.id)
            saveImport = nil
            presentImportResult(Self.saveImportResult(outcome))
        }
    }

    private static func saveImportResult(_ outcome: SaveImportOutcome) -> ImportResultAlert {
        var lines: [String] = []
        let forLibrary = outcome.imported.filter { !$0.forMissingGame }
        let games = Set(forLibrary.map(\.game.id)).count
        if !forLibrary.isEmpty {
            let saves = forLibrary.count == 1 ? "1 save" : "\(forLibrary.count) saves"
            lines.append("Imported \(saves) for \(gameCountText(games)). Each game starts fresh the next time you play it, so it loads the imported save.")
        }
        let kept = outcome.imported.count - forLibrary.count
        if kept > 0 {
            lines.append(kept == 1
                ? "1 save is waiting for its game: add the game and it's there. Settings → Saves lists it."
                : "\(kept) saves are waiting for their games: add the games and they're there. Settings → Saves lists them.")
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
        if playGame != nil {
            pendingImportResults.append(result)
        } else {
            show(result)
        }
    }

    private func showPendingImportResults() {
        guard playGame == nil, !pendingImportResults.isEmpty else { return }
        let results = pendingImportResults
        pendingImportResults = []
        // Several imports may have finished during one game: show them in one alert.
        let message = results.map(\.message).joined(separator: "\n\n")
        show(results.allSatisfy(\.isError) ? .error(message) : .notice(message))
    }

    private func show(_ result: ImportResultAlert) {
        switch result {
        case .notice(let message): alert = .importNotice(message)
        case .error(let message): alert = .importFailed(message)
        }
    }
}

/// The library's alert, in its own modifier so the library's long body type-checks in time.
private struct LibraryAlertPresenter<Buttons: View>: ViewModifier {
    @Binding var alert: LibraryAlert?
    let buttons: (LibraryAlert) -> Buttons

    func body(content: Content) -> some View {
        content.alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } }),
            presenting: alert,
            actions: buttons,
            message: { (alert: LibraryAlert) in Text(alert.message) }
        )
    }
}

/// The library shows one alert at a time.
private enum LibraryAlert {
    case libraryUnavailable(String)
    case importFailed(String)
    case importNotice(String)
    case missingGame(LibraryGame)
    case confirmDelete(LibraryGame)
    case deleteFailed(String)
    case pspSaveRetained(String)

    var isMissingGame: Bool {
        if case .missingGame = self { true } else { false }
    }

    var title: String {
        switch self {
        case .libraryUnavailable: "Library Unavailable"
        case .importFailed: "Import failed"
        case .importNotice: "Import"
        case .missingGame: "Game File Missing"
        case .confirmDelete: "Delete Game?"
        case .deleteFailed: "Couldn't Delete"
        case .pspSaveRetained: "PSP Save Data Retained"
        }
    }

    var message: String {
        switch self {
        case .libraryUnavailable(let message), .importFailed(let message), .importNotice(let message),
             .deleteFailed(let message), .pspSaveRetained(let message):
            message
        case .missingGame(let game):
            "\(game.displayName) is no longer in Files → RetroPlay → Games. Put the file back to keep playing, or delete the game to also remove its saves and states."
        case .confirmDelete(let game):
            "This removes \(game.displayName) from the library and deletes its imported file, saves, and states on this device."
        }
    }
}

private enum ImportKind {
    case games
    case saves
}

/// A scanned saves pick waiting for the player's go-ahead.
private struct SaveImportSession: Identifiable {
    /// The `SaveImportSessions` id.
    let id: UUID
    let batch: SaveImportBatch
}

#if DEBUG
private extension SaveImportBatch {
    /// Sample rows for `-RetroPlaySmokeSaveImport` screenshots.
    static var smokeSample: SaveImportBatch {
        let saves = SavePaths().savesDirectory
        func item(
            _ name: String, _ system: SystemID, _ source: String, replaces: Bool,
            parts: [N64CombinedSave.Region] = [], note: String? = nil, missing: Bool = false
        ) -> SaveImportItem {
            let game = LibraryGame(displayName: name, systemID: system, relativePath: "\(name).rom")
            return SaveImportItem(
                game: game,
                sourceURL: URL(fileURLWithPath: "/\(source)"),
                sourceName: source,
                plan: SaveGameImportPlan(
                    sourceDescription: source,
                    destinationURL: saves.appendingPathComponent("\(name).sav"),
                    replacesExisting: replaces,
                    warning: note
                ),
                n64Parts: parts.map { N64CombinedSave.Part(region: $0, bytes: Data()) },
                forMissingGame: missing
            )
        }
        return SaveImportBatch(
            items: [
                item("Golden Sun", .gba, "saves/mGBA/Golden Sun (USA).srm", replaces: false),
                item("Super Mario 64", .n64, "Project64/Save/SUPER MARIO 64.eep, Project64/Save/SUPER MARIO 64.mpk",
                     replaces: false, parts: [.eeprom, .controllerPak(1)]),
                item("Final Fantasy VII", .ps1, "memcards/Final Fantasy VII (USA)_1.mcd", replaces: true),
                item("Patapon", .psp, "PSP/SAVEDATA/UCUS98711DATA00", replaces: false),
                item("ULUS10041", .psp, "PSP/SAVEDATA/ULUS10041SAVE00", replaces: false, missing: true),
            ],
            skipped: [
                SkippedSave(name: "states/mGBA/Golden Sun (USA).state", reason: "Save states only work in the emulator that made them; import the battery save (.sav/.srm) instead."),
                SkippedSave(name: "saves/Chrono Trigger.srm", reason: "No game in your library has this name, and nothing says which system it's for. Import the game first, or keep the save in a folder named after its system (GBA, SNES…) and import it again."),
            ],
            ignoredFiles: 12
        )
    }
}
#endif

/// An import outcome for the "Import" notice or the "Import failed" alert.
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
