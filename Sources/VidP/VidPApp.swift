import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct VidPApp: App {
    @StateObject private var controller = PlaybackController()
    @State private var pendingURLs: [URL] = []
    @State private var openCoalesceTask: Task<Void, Never>?

    init() {
        PlaybackController.cleanup()  // stale remux sweep at launch
    }

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .onOpenURL { url in enqueue(url) }  // Finder / dock drops (one call per file)
                .onAppear { controller.installKeyboardMonitor() }
                .onDisappear { controller.teardown(); PlaybackController.cleanup() }
                .frame(minWidth: 640, minHeight: 360)
                .background(WindowConfigurator())
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { chooseFiles() }
                    .keyboardShortcut("o")
            }
        }
    }

    /// Coalesces rapid per-file onOpenURL callbacks so a multi-select
    /// (video + sidecars) arrives as one selection.
    @MainActor
    private func enqueue(_ url: URL) {
        pendingURLs.append(url)
        openCoalesceTask?.cancel()
        openCoalesceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            controller.open(pendingURLs)
            pendingURLs.removeAll()
        }
    }

    @MainActor
    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        controller.open(Array(panel.urls))
    }
}

/// Edge-to-edge video window: hidden title bar, black backdrop (TV-app style).
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .black
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 480, height: 270)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

struct ContentView: View {
    @ObservedObject var controller: PlaybackController

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if controller.player != nil {
                VideoView(controller: controller)
                PlayerOverlayView(controller: controller)
            } else {
                emptyState
            }

            if controller.preparing {
                ProgressView("Preparing…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            controller.open(urls.filter { $0.isFileURL })
            return true
        }
        .alert("Can’t play this file", isPresented: .init(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 56, weight: .light))
            Text("Drop a video here")
                .font(.title3)
            Text("or press ⌘O — select the video together with any .srt files")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
