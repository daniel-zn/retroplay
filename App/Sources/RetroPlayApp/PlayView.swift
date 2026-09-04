import SwiftUI
import RetroPlayCore

/// Play shell for a library game. GBA uses MGBACore; other systems stay stubs until later milestones.
@available(iOS 18.0, *)
public struct PlayView: View {
    let game: LibraryGame
    let romURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var core: (any EmulatorCore)?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var statusLine = "Starting…"
    @State private var held: GBAInput = []

    public init(game: LibraryGame, romURL: URL) {
        self.game = game
        self.romURL = romURL
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text(game.displayName)
                .font(.headline)
            Text("\(game.systemID.displayName) · \(game.systemID.defaultCoreName)")
                .font(.caption)
                .foregroundStyle(.secondary)

            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.85))
                .aspectRatio(3 / 2, contentMode: .fit)
                .overlay {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding()
                }

            if game.systemID == .gba {
                gbaPad
            }

            HStack {
                Button("Pause") { core?.pause(); statusLine = "Paused" }
                Button("Resume") { core?.resume(); statusLine = "Running (native pending)" }
                Button("Stop") {
                    core?.stop()
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .navigationTitle("Play")
        .navigationBarTitleDisplayMode(.inline)
        .task { await boot() }
        .alert("Cannot play yet", isPresented: $showError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var gbaPad: some View {
        VStack(spacing: 8) {
            HStack {
                padButton("↑", .up)
            }
            HStack(spacing: 24) {
                padButton("←", .left)
                padButton("→", .right)
            }
            HStack {
                padButton("↓", .down)
            }
            HStack(spacing: 16) {
                padButton("A", .a)
                padButton("B", .b)
                padButton("L", .l)
                padButton("R", .r)
                padButton("Start", .start)
                padButton("Select", .select)
            }
            .font(.caption)
        }
    }

    private func padButton(_ title: String, _ bit: GBAInput) -> some View {
        Button(title) {}
            .buttonStyle(.bordered)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setHeld(bit, true) }
                    .onEnded { _ in setHeld(bit, false) }
            )
    }

    private func setHeld(_ bit: GBAInput, _ down: Bool) {
        if down { held.insert(bit) } else { held.remove(bit) }
        core?.setGBAInput(held)
    }

    private func boot() async {
        let instance = CoreFactory.makeCore(for: game.systemID)
        core = instance
        do {
            try await instance.loadROM(at: romURL)
            instance.start()
            statusLine = "Core loaded"
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Waiting for mGBA XCFramework"
            showError = true
        }
    }
}
