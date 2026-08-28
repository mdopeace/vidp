import AppKit
import MediaPlayer
import UniformTypeIdentifiers
import CMPV

final class AppDelegate: NSObject, NSApplicationDelegate, PlayerDelegate, NSMenuItemValidation {
    var window: NSWindow!
    private var playerView: PlayerView!
    private var hudOverlay: HUDOverlayView!
    private var isPaused = true
    private var currentFilePath: String?
    private var positionTimer: Timer?
    private var pendingFilePath: String?
    private var sleepActivity: NSObjectProtocol?
    private let vidExts: Set<String> = ["mp4", "mkv", "webm", "mov", "m4v", "avi"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        playerView = PlayerView(frame: .zero)

        // Translucent blur background
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.wantsLayer = true
        visualEffectView.autoresizingMask = [.width, .height]

        // Window: native shadow + rounded corners, no title bar strip
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "vidp"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = visualEffectView

        // Player view on top of the blur
        playerView.frame = visualEffectView.bounds
        playerView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(playerView)

        if let error = playerView.setup() {
            NSLog("vidp setup failed: \(error)")
        }
        playerView.delegate = self

        hudOverlay = HUDOverlayView(frame: .zero)
        hudOverlay.translatesAutoresizingMaskIntoConstraints = false
        hudOverlay.playerView = playerView
        visualEffectView.addSubview(hudOverlay)
        NSLayoutConstraint.activate([
            hudOverlay.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            hudOverlay.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            hudOverlay.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            hudOverlay.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor),
        ])

        setupRemoteCommands()

        window.center()
        window.makeKeyAndOrderFront(nil)

            // CLI fallback: vidp.app/Contents/MacOS/vidp <file>
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let first = args.first {
            open(path: first)
        }

        // Deferred open from "Open With" (fires before finishLaunching)
        if let pending = pendingFilePath {
            pendingFilePath = nil
            open(path: pending)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About vidp", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit vidp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open\u{2026}", action: #selector(openDocument), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Make Default Player\u{2026}", action: #selector(makeDefaultPlayer), keyEquivalent: "")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullscreenItem = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullscreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullscreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.playerView.cyclePause()
            return .success
        }

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if self.isPaused {
                self.playerView.cyclePause()
            }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if !self.isPaused {
                self.playerView.cyclePause()
            }
            return .success
        }

        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.playerView.nextTrack()
            return .success
        }

        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.playerView.prevTrack()
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.playerView.seek(seconds: 10)
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.playerView.seek(seconds: -10)
            return .success
        }
    }

    // Finder "Open With" sends files here (odoc Apple Event).
    func application(_ application: NSApplication, openFiles files: [String]) {
        if hudOverlay != nil {
            open(path: files[0])
        } else {
            pendingFilePath = files[0]
        }
    }

    @objc func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            .movie, .mpeg4Movie, .quickTimeMovie,
            UTType(filenameExtension: "mkv")!,
            UTType(filenameExtension: "webm")!,
            UTType(filenameExtension: "avi")!,
        ]
        panel.begin { [weak self] response in
            if response == .OK, let url = panel.url {
                self?.open(path: url.path)
            }
        }
    }

    @objc private func showSettings() {
        guard hudOverlay.isFileLoaded else { return }
        hudOverlay.showSettingsPopover()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showSettings) {
            return hudOverlay.isFileLoaded
        }
        return true
    }

    @objc private func makeDefaultPlayer() {
        let bundleID = Bundle.main.bundleIdentifier! as CFString
        let types = [
            "org.matroska.mkv",
            "io.iina.mkv",
            "public.movie",
            "public.mpeg-4",
            "com.apple.quicktime-movie",
            "org.webmproject.webm",
        ]
        for uti in types {
            LSSetDefaultRoleHandlerForContentType(uti as CFString, .all, bundleID)
        }
        let alert = NSAlert()
        alert.messageText = "Default Player Set"
        alert.informativeText = "vidp is now the default player for all supported video types."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func playerView(_ playerView: PlayerView, didReceiveFile path: String) {
        open(path: path)
    }

    private func open(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            NSLog("vidp: no such file: \(path)")
            return
        }
        savePosition()
        hudOverlay?.setFileLoaded(false)
        let title = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        hudOverlay?.setTitle(title)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window.makeKeyAndOrderFront(nil)
            self?.playerView.load(path: path)
            self?.currentFilePath = path
            self?.startPositionTimer()
        }
    }

    private func savePosition() {
        guard let path = currentFilePath, let playerView else { return }
        guard let pos = playerView.doubleProperty("time-pos"),
              let dur = playerView.doubleProperty("duration"), dur > 0 else { return }
        // Don't save if near the end (within 2s) — reopen will start fresh
        guard dur - pos > 2 else {
            UserDefaults.standard.removeObject(forKey: "pos:\(path)")
            return
        }
        UserDefaults.standard.set(pos, forKey: "pos:\(path)")
    }

    private func restorePosition(for path: String) {
        guard let playerView else { return }
        let key = "pos:\(path)"
        guard let saved = UserDefaults.standard.object(forKey: key) as? Double else { return }
        // Seek after a brief delay so mpv has time to settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            playerView.seekAbsolute(saved)
        }
    }

    private func startPositionTimer() {
        positionTimer?.invalidate()
        positionTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.savePosition()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        positionTimer?.invalidate()
        savePosition()
    }

    // MARK: PlayerDelegate

    func playerDidUpdateVideoSize(width: Int64, height: Int64) {
        guard width > 0, height > 0, let screen = window.screen ?? NSScreen.main else { return }
        playerView.hideOverlay()
        // In fullscreen the window must keep covering the screen; mpv letterboxes
        // the new aspect ratio itself. setContentSize/center() would shrink the
        // fullscreen window to windowed size, leaving blank space around it.
        guard !window.styleMask.contains(.fullScreen) else { return }
        let maxW = screen.visibleFrame.width * 0.9
        let maxH = screen.visibleFrame.height * 0.9
        let aspect = CGFloat(width) / CGFloat(height)
        var size = CGSize(width: maxW, height: maxW / aspect)
        if size.height > maxH {
            size = CGSize(width: maxH * aspect, height: maxH)
        }
        window.setContentSize(size)
        window.center()
    }

    func playerDidUpdatePlaybackState(isPaused: Bool) {
        self.isPaused = isPaused
        hudOverlay.setPaused(isPaused)
        updateSleepActivity(paused: isPaused)
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: window.title,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        center.playbackState = isPaused ? .paused : .playing
    }

    /// Hold a NoDisplaySleepAssertion while playing so macOS doesn't lock/sleep/screensaver.
    private func updateSleepActivity(paused: Bool) {
        if !paused {
            if sleepActivity == nil {
                sleepActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled],
                    reason: "vidp playback")
            }
        } else if let token = sleepActivity {
            ProcessInfo.processInfo.endActivity(token)
            sleepActivity = nil
        }
    }

    func playerDidEncounterError(_ message: String) {
        NSLog("vidp playback error: \(message)")
        playerView.showOverlay()
    }

    func playerDidEndFile() {
        guard currentFilePath != nil else {
            playerView.showOverlay()
            return
        }
        guard playAdjacent(offset: 1) else {
            playerView.showOverlay()
            return
        }
    }

    func playerDidRequestNext() {
        playAdjacent(offset: 1)
    }

    func playerDidRequestPrev() {
        playAdjacent(offset: -1)
    }

    /// Plays the video `offset` slots away in the folder's natural-sorted list.
    /// Returns false if there is no adjacent file (folder edges, no file open).
    @discardableResult
    private func playAdjacent(offset: Int) -> Bool {
        guard let cur = currentFilePath else { return false }
        let ns = cur as NSString
        let dir = ns.deletingLastPathComponent
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { vidExts.contains(($0 as NSString).pathExtension.lowercased()) }
            // localizedStandardCompare = Finder-style natural sort (ep2 < ep10)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let idx = files.firstIndex(of: ns.lastPathComponent),
              files.indices.contains(idx + offset) else {
            return false
        }
        playerView.unpause()
        open(path: dir + "/" + files[idx + offset])
        return true
    }

    func playerDidFileLoad() {
        guard let path = currentFilePath else { return }
        hudOverlay.setFileLoaded(true)
        restorePosition(for: path)
    }
}
