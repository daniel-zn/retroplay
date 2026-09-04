import SwiftUI
import RetroPlayCore

/// Library shell stub. Open in Xcode as a package or paste into an iOS app target.
/// Liquid Glass APIs require iOS 26 — gate with #available when building against older SDKs.
@available(iOS 18.0, *)
public struct RetroPlayRootView: View {
    @State private var games: [LibraryGame] = []

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    ContentUnavailableView(
                        "No Games Yet",
                        systemImage: "gamecontroller",
                        description: Text("Import games you own via Files. RetroPlay does not include ROMs.")
                    )
                } else {
                    List(games) { game in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.displayName).font(.headline)
                            Text("\(game.systemID.displayName) · \(game.systemID.defaultCoreName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("RetroPlay")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Wire `.fileImporter` here — do not hardcode ROM paths.
                    Text("Import")
                        .accessibilityLabel("Import via Files (wire fileImporter)")
                }
            }
        }
    }
}
