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
    @State private var frameImage: CGImage?
    @State private var frameSink = FrameSinkStore()

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

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.black.opacity(0.85))
                if let frameImage {
                    Image(decorative: frameImage, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .padding(8)
                } else {
                    Text(statusLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .aspectRatio(3 / 2, contentMode: .fit)

            if game.systemID == .gba {
                gbaPad
            }

            HStack {
                Button("Pause") { core?.pause(); statusLine = "Paused" }
                Button("Resume") { core?.resume(); statusLine = "Running" }
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
        .onDisappear {
            core?.stop()
            core = nil
        }
        .alert("Could not play", isPresented: $showError) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var gbaPad: some View {
        VStack(spacing: 8) {
            HStack { padButton("↑", .up) }
            HStack(spacing: 24) {
                padButton("←", .left)
                padButton("→", .right)
            }
            HStack { padButton("↓", .down) }
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
        if let mgba = instance as? MGBACore {
            frameSink.onFrame = { image in
                frameImage = image
                statusLine = "Running"
            }
            mgba.attachFrameSink(frameSink)
        }
        core = instance
        do {
            try await instance.loadROM(at: romURL)
            instance.start()
            statusLine = "Running"
        } catch {
            errorMessage = error.localizedDescription
            statusLine = "Failed"
            showError = true
        }
    }
}
