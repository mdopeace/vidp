import AppKit
import CryptoKit
import MediaPlayer
import UniformTypeIdentifiers
import CMPV

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, PlayerDelegate, PIPViewControllerDelegate, NSMenuItemValidation {
    private static let homepageContentSize = NSSize(width: 1000, height: 650)
    private static let settingsSidebarWidth: CGFloat = 300

    var window: NSWindow!
    private var playerView: PlayerView!
    private var playerContainer: NSVisualEffectView!
    private var homepageView: HomepageView!
    private var hudOverlay: HUDOverlayView!
    private var settingsSplitItem: NSSplitViewItem!
    private var isSettingsOpen = false
    private var settingsMonitor: Any?
    private var isPaused = true
    private var currentFilePath: String?
    private var positionTimer: Timer?
    private var pendingFilePath: String?
    private var sleepActivity: NSObjectProtocol?
    private let vidExts: Set<String> = ["mp4", "mkv", "webm", "mov", "m4v", "avi"]
    private var isPiPActive = false
    private var pipController: PIPViewController?
    private var pipVideo: NSViewController?
    private var savedWindowSize: NSSize?
    private var hasShownWindow = false
    private var currentVideoAspectRatio: CGFloat?
    private let applicationPath = URL(fileURLWithPath: "/Applications/vidp.app")
    private static let supportURL = URL(string: "https://buymeacoffee.com/mdopeace")!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        playerView = PlayerView(frame: .zero)

        playerContainer = NSVisualEffectView()
        playerContainer.material = .windowBackground
        playerContainer.state = .active
        playerContainer.blendingMode = .behindWindow
        playerContainer.wantsLayer = true

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.homepageContentSize),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.title = "Vidp"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.delegate = self

        homepageView = HomepageView(playerContainer: playerContainer)
        let playerController = NSViewController()
        playerController.view = homepageView
        let settingsSidebar = SettingsSidebarView(
            frame: NSRect(x: 0, y: 0, width: Self.settingsSidebarWidth, height: 650))
        let settingsController = NSViewController()
        settingsController.view = settingsSidebar
        settingsSidebar.onDone = { [weak self] in self?.closeSettingsSidebar() }

        let splitViewController = NSSplitViewController()
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin
        splitViewController.addSplitViewItem(NSSplitViewItem(viewController: playerController))
        settingsSplitItem = NSSplitViewItem(viewController: settingsController)
        settingsSplitItem.minimumThickness = Self.settingsSidebarWidth
        settingsSplitItem.maximumThickness = Self.settingsSidebarWidth
        settingsSplitItem.canCollapse = true
        splitViewController.addSplitViewItem(settingsSplitItem)
        settingsSplitItem.isCollapsed = true
        splitViewController.view.wantsLayer = true
        splitViewController.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentViewController = splitViewController

        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])

        if let error = playerView.setup() {
            NSLog("vidp setup failed: \(error)")
        }
        let mpvReady = playerView.mpv != nil
        playerView.delegate = self
        playerView.onPiPToggle = { [weak self] in self?.togglePiP() }

        hudOverlay = HUDOverlayView(frame: .zero)
        hudOverlay.translatesAutoresizingMaskIntoConstraints = false
        hudOverlay.playerView = playerView
        hudOverlay.onSettingsToggle = { [weak self] in self?.toggleSettingsSidebar() }
        hudOverlay.onPiPToggle = { [weak self] in self?.togglePiP() }
        hudOverlay.onFullscreenToggle = { [weak self] in
            self?.window.toggleFullScreen(nil)
        }
        hudOverlay.onBack = { [weak self] in self?.closeCurrentVideo() }
        hudOverlay.onSupport = { [weak self] in self?.openSupportLink() }
        playerContainer.addSubview(hudOverlay)
        NSLayoutConstraint.activate([
            hudOverlay.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            hudOverlay.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            hudOverlay.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            hudOverlay.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])

        // Parented to the player column, not the HUD, so it shows while the HUD is hidden.
        let volumeIconView = NSImageView()
        volumeIconView.imageScaling = .scaleProportionallyUpOrDown
        volumeIconView.contentTintColor = NSColor(white: 1, alpha: 0.5)
        let volumeIconConfig = NSImage.SymbolConfiguration(pointSize: HUDOverlayView.titlePointSize * HUDOverlayView.osdScale, weight: .semibold)
        volumeIconView.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)?
            .withSymbolConfiguration(volumeIconConfig)
        volumeIconView.translatesAutoresizingMaskIntoConstraints = false
        hudOverlay.volumeIconWidth = volumeIconView.widthAnchor.constraint(equalToConstant: 40 * HUDOverlayView.osdScale)
        hudOverlay.volumeIconHeight = volumeIconView.heightAnchor.constraint(equalToConstant: 40 * HUDOverlayView.osdScale)
        NSLayoutConstraint.activate([
            hudOverlay.volumeIconWidth,
            hudOverlay.volumeIconHeight,
        ])
        let volumeLabel = NSTextField(labelWithString: "")
        volumeLabel.font = AppSettings.hudFont(named: AppSettings.hudFontName,
                                               size: HUDOverlayView.titlePointSize * HUDOverlayView.osdScale,
                                               bold: AppSettings.hudBold, italic: AppSettings.hudItalic)
        volumeLabel.textColor = NSColor(white: 1, alpha: 0.5)
        volumeLabel.translatesAutoresizingMaskIntoConstraints = false
        let volumeStack = ClickThroughStackView(views: [volumeIconView, volumeLabel])
        volumeStack.orientation = .horizontal
        volumeStack.spacing = 10 * HUDOverlayView.osdScale
        volumeStack.alignment = .centerY
        volumeStack.translatesAutoresizingMaskIntoConstraints = false
        volumeStack.alphaValue = 0
        playerContainer.addSubview(volumeStack)

        let volumeCenterY = volumeStack.centerYAnchor.constraint(equalTo: playerContainer.centerYAnchor)
        let volumeAboveTransport = volumeStack.bottomAnchor.constraint(equalTo: hudOverlay.transportStack.topAnchor, constant: -12)
        NSLayoutConstraint.activate([
            volumeStack.centerXAnchor.constraint(equalTo: playerContainer.centerXAnchor),
            volumeCenterY,
        ])

        hudOverlay.volumeLabel = volumeLabel
        hudOverlay.volumeIconView = volumeIconView
        hudOverlay.volumeStack = volumeStack
        hudOverlay.volumeCenterY = volumeCenterY
        hudOverlay.volumeAboveTransport = volumeAboveTransport

        setupRemoteCommands()
        restoreVolume()

        // Cold-start open: stay hidden until the first video-size event, so the
        // window appears once, directly at video size.
        let cliFile = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") })
        // pendingFilePath (Open With) wins over the CLI arg; without mpv there is
        // no size/file/error event to ever show the window, so load() no-ops.
        let launchFile = pendingFilePath ?? cliFile
        if let launchFile, mpvReady {
            pendingFilePath = nil
            playerView.hideOverlay()
            open(path: launchFile)
        } else {
            revealHomepage()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.performVersionCheck(showUpToDate: false)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows, !hasShownWindow {
            revealHomepage()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        // Tahoe auto-icons standard items (About, Quit) only; custom items
        // need explicit images to match.
        func menuIcon(_ name: String) -> NSImage? {
            let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            img?.isTemplate = true
            return img
        }
        let aboutItem = appMenu.addItem(withTitle: "About Vidp", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = menuIcon("info.circle")
        let updatesItem = appMenu.addItem(withTitle: "Check for Updates\u{2026}", action: #selector(checkForUpdates), keyEquivalent: "")
        updatesItem.target = self
        updatesItem.image = menuIcon("arrow.triangle.2.circlepath")
        let supportItem = appMenu.addItem(withTitle: "Buy Me a Coffee\u{2026}", action: #selector(openSupportLink), keyEquivalent: "")
        supportItem.target = self
        supportItem.image = menuIcon("heart")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = menuIcon("gear")
        let removeItem = appMenu.addItem(withTitle: "Remove Vidp\u{2026}", action: #selector(uninstallApp), keyEquivalent: "")
        removeItem.target = self
        removeItem.image = menuIcon("trash")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Vidp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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

        let playbackMenuItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        // Real key equivalents mirroring PlayerView.keyDown; they stay disabled
        // while a sheet/panel is open so they can't steal keystrokes (see
        // validateMenuItem).
        func playbackItem(_ title: String, _ key: String, _ action: Selector,
                          modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = self
            return item
        }
        let leftArrow = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
        let rightArrow = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        let upArrow = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let downArrow = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        playbackMenu.addItem(playbackItem("Play/Pause", " ", #selector(togglePlayPause)))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(playbackItem("Skip Forward 10 Seconds", rightArrow, #selector(skipForward)))
        playbackMenu.addItem(playbackItem("Skip Back 10 Seconds", leftArrow, #selector(skipBack)))
        playbackMenu.addItem(playbackItem("Skip Forward 30 Seconds", rightArrow, #selector(skipForward30), modifiers: .shift))
        playbackMenu.addItem(playbackItem("Skip Back 30 Seconds", leftArrow, #selector(skipBack30), modifiers: .shift))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(playbackItem("Increase Volume", upArrow, #selector(volumeUp)))
        playbackMenu.addItem(playbackItem("Decrease Volume", downArrow, #selector(volumeDown)))
        playbackMenu.addItem(playbackItem("Mute", "m", #selector(toggleMute)))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(playbackItem("Next Video", "l", #selector(playNext)))
        playbackMenu.addItem(playbackItem("Previous Video", "h", #selector(playPrev)))
        playbackMenu.addItem(playbackItem("Picture in Picture", "p", #selector(togglePiPFromMenu)))
        playbackMenu.addItem(.separator())
        playbackMenu.addItem(playbackItem("Close Video", "w", #selector(closeVideo), modifiers: .command))
        playbackMenuItem.submenu = playbackMenu
        mainMenu.addItem(playbackMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApplication.shared.windowsMenu = windowMenu

        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = NSMenu(title: "Help")
        mainMenu.addItem(helpMenuItem)
        NSApplication.shared.helpMenu = helpMenuItem.submenu

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

    // MARK: - Modal panels

    /// Set while runModalPaused holds playback, so a hold outliving its panel
    /// (an update download) can be handed back.
    private var pausedByModalPanel = false

    /// Alerts are app-modal but leave the video running behind them, so pause for
    /// the panel's lifetime and resume only if it was playing. `shouldResume` is
    /// read after close, letting a panel that leads into a relaunch keep the pause.
    @discardableResult
    private func runModalPaused<T>(shouldResume: () -> Bool = { true }, _ body: () -> T) -> T {
        // Read mpv live: the delegate's cached isPaused lags by a main-loop hop.
        let wasPlaying = playerView?.boolProperty("pause") == false
        if wasPlaying {
            playerView?.cyclePause()
            pausedByModalPanel = true
        }
        defer {
            if wasPlaying, shouldResume() {
                playerView?.unpause()
                pausedByModalPanel = false
            }
        }
        return body()
    }

    /// Hand playback back after a panel pause outlived its panel; safe when
    /// nothing is held.
    private func resumeAfterModalPanel() {
        guard pausedByModalPanel else { return }
        playerView?.unpause()
        pausedByModalPanel = false
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
        toggleSettingsSidebar()
    }

    private func toggleSettingsSidebar() {
        if isSettingsOpen {
            closeSettingsSidebar()
            return
        }
        guard hudOverlay?.isFileLoaded == true else { return }
        isSettingsOpen.toggle()
        settingsSplitItem.animator().isCollapsed = !isSettingsOpen
        if isSettingsOpen {
            settingsMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53, self?.isSettingsOpen == true else { return event }
                self?.closeSettingsSidebar()
                return nil
            }
        } else {
            removeSettingsMonitor()
        }
    }

    private func closeSettingsSidebar() {
        guard isSettingsOpen else { return }
        isSettingsOpen = false
        settingsSplitItem.animator().isCollapsed = true
        removeSettingsMonitor()
    }

    private func removeSettingsMonitor() {
        guard let settingsMonitor else { return }
        NSEvent.removeMonitor(settingsMonitor)
        self.settingsMonitor = nil
    }

    // MARK: - Playback menu actions (mirror PlayerView.keyDown)

    @objc private func togglePlayPause() { playerView?.cyclePause() }
    @objc private func skipForward() { playerView?.seek(seconds: 10) }
    @objc private func skipBack() { playerView?.seek(seconds: -10) }
    @objc private func skipForward30() { playerView?.seek(seconds: 30) }
    @objc private func skipBack30() { playerView?.seek(seconds: -30) }
    @objc private func volumeUp() { playerView?.adjustVolume(delta: 1) }
    @objc private func volumeDown() { playerView?.adjustVolume(delta: -1) }
    @objc private func toggleMute() { playerView?.toggleMute() }
    @objc private func togglePiPFromMenu() { togglePiP() }
    @objc private func playNext() { playerDidRequestNext() }
    @objc private func playPrev() { playerDidRequestPrev() }
    @objc private func closeVideo() {
        guard window != nil, playerView != nil, hudOverlay != nil else { return }
        closeCurrentVideo()
    }

    // MARK: - PiP

    func togglePiP() {
        guard hudOverlay?.isFileLoaded ?? false else { return }
        if isPiPActive {
            exitPiP()
        } else {
            enterPiP()
        }
    }

    private func enterPiP() {
        guard !isPiPActive, pipController == nil else { return }
        isPiPActive = true

        let pip = PIPViewController()
        pip.delegate = self
        let aspectRatio = currentVideoAspectRatio
            ?? playerView.frame.width / max(playerView.frame.height, 1)
        pip.aspectRatio = NSSize(width: aspectRatio, height: 1)
        pip.playing = !isPaused
        pipController = pip

        let vc = NSViewController()
        vc.view = playerView
        pipVideo = vc

        pip.presentAsPicture(inPicture: vc)
        window.orderOut(nil)
    }

    private func exitPiP() {
        guard isPiPActive, let pip = pipController else { return }
        isPiPActive = false

        if let vc = pipVideo {
            pip.dismiss(vc)
        }
        pipVideo = nil
        pipController = nil
        restoreWindowHierarchy()
    }

    /// Re-parents playerView / HUD / volume OSD back into the player column and
    /// brings the window forward. Shared by exitPiP and pipDidClose.
    private func restoreWindowHierarchy() {
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerContainer.addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.leadingAnchor.constraint(equalTo: playerContainer.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: playerContainer.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: playerContainer.topAnchor),
            playerView.bottomAnchor.constraint(equalTo: playerContainer.bottomAnchor),
        ])
        // HUD must be above playerView to receive mouse events.
        playerContainer.addSubview(hudOverlay)
        // Volume indicator must be above HUD so it's visible.
        if let volumeStack = hudOverlay.volumeStack {
            playerContainer.addSubview(volumeStack)
            volumeStack.alphaValue = 0
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: PIPViewControllerDelegate

    func pipWillClose(_ pip: PIPViewController) {
        pip.replacementWindow = window
        pip.replacementRect = window.frame
    }

    func pipDidClose(_ pip: PIPViewController) {
        isPiPActive = false
        pipVideo = nil
        pipController = nil
        restoreWindowHierarchy()
    }

    func pipActionPlay(_ pip: PIPViewController) {
        playerView.unpause()
    }

    func pipActionPause(_ pip: PIPViewController) {
        if !isPaused {
            playerView.cyclePause()
        }
    }

    func pipActionStop(_ pip: PIPViewController) {
        if !isPaused {
            playerView.cyclePause()
        }
    }

    func pipAction(_ pip: PIPViewController, skipInterval interval: TimeInterval) {
        playerView.seek(seconds: interval)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Document panels cannot stack with another sheet or modal panel.
        switch menuItem.action {
        case #selector(openDocument):
            guard let window, window.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            return true
        default:
            break
        }
        if menuItem.action == #selector(showSettings) {
            return window != nil && (hudOverlay?.isFileLoaded ?? false) && NSApp.modalWindow == nil
        }
        if menuItem.action == #selector(toggleMute) {
            menuItem.title = (playerView?.boolProperty("mute") ?? false) ? "Unmute" : "Mute"
        }
        switch menuItem.action {
        case #selector(togglePlayPause),
             #selector(skipForward), #selector(skipBack),
             #selector(skipForward30), #selector(skipBack30),
             #selector(volumeUp), #selector(volumeDown),
             #selector(toggleMute),
             #selector(playNext), #selector(playPrev),
             #selector(togglePiPFromMenu),
             #selector(closeVideo):
            // Disabled items don't match key equivalents, which also keeps
            // single-letter shortcuts from firing while a sheet owns focus.
            guard window?.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
            return hudOverlay?.isFileLoaded ?? false
        default:
            return true
        }
    }

    /// First reveal of the window: cold-start opens stay hidden until here, so
    /// they appear once, directly at video size.
    private func revealHomepage() {
        guard !hasShownWindow else { return }
        if currentFilePath == nil {
            window.setContentSize(Self.homepageContentSize)
        }
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hasShownWindow = true
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
        alert.informativeText = "Vidp is now the default player for all supported video types."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        runModalPaused { alert.runModal() }
    }

    // MARK: - Uninstall

    @objc private func uninstallApp() {
        let alert = NSAlert()
        alert.messageText = "Remove Vidp?"
        alert.informativeText = "Choose how to remove Vidp from your system."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Full Cleanup")
        alert.addButton(withTitle: "Remove App Only")
        alert.addButton(withTitle: "Cancel")

        let response = runModalPaused { alert.runModal() }
        switch response {
        case .alertFirstButtonReturn:
            trashApp(wipeDefaults: true)
        case .alertSecondButtonReturn:
            trashApp(wipeDefaults: false)
        default:
            break
        }
    }

    /// Moves the bundle to the Trash, then quits — only once the bundle is really
    /// gone, so a failed Trash leaves the app open to retry. `wipeDefaults` also
    /// clears persisted settings, so a reinstall starts fresh.
    private func trashApp(wipeDefaults: Bool) {
        if wipeDefaults, let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        let appPath = Bundle.main.bundlePath
        NSWorkspace.shared.recycle([URL(fileURLWithPath: appPath)]) { _, error in
            DispatchQueue.main.async {
                guard let error else {
                    NSApp.terminate(nil)
                    return
                }
                NSLog("vidp: failed to remove app: \(error)")
                let errAlert = NSAlert()
                errAlert.messageText = "Could not remove Vidp"
                errAlert.informativeText = error.localizedDescription
                errAlert.alertStyle = .critical
                errAlert.addButton(withTitle: "OK")
                self.runModalPaused { errAlert.runModal() }
            }
        }
    }

    // MARK: - Version Check

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let alert = NSAlert()
        alert.messageText = "Vidp"
        alert.informativeText = version.isEmpty ? "" : "Version \(version)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        func center(_ view: NSView) {
            (view as? NSTextField)?.alignment = .center
            view.subviews.forEach(center)
        }
        if let content = alert.window.contentView { center(content) }
        runModalPaused { alert.runModal() }
    }

    @objc private func checkForUpdates() {
        performVersionCheck(showUpToDate: true)
    }

    @objc private func openSupportLink() {
        NSWorkspace.shared.open(Self.supportURL)
    }

    private func performVersionCheck(showUpToDate: Bool) {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else { return }
        let urlString = "https://api.github.com/repos/mdopeace/vidp/releases/latest"
        guard let url = URL(string: urlString) else { return }

        let task = URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if showUpToDate {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Couldn't Check for Updates"
                        alert.informativeText = "Couldn't reach the update server. You're still on Vidp v\(currentVersion)."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        self.runModalPaused { alert.runModal() }
                    }
                }
                return
            }

            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard latestVersion != currentVersion else {
                if showUpToDate {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "You're up to date"
                        alert.informativeText = "Vidp v\(currentVersion) is the latest version."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        self.runModalPaused { alert.runModal() }
                    }
                }
                return
            }

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Update Available"
                let playingNote = (self.hudOverlay?.isFileLoaded ?? false)
                    ? " Your video will be closed and reopened where you left off."
                    : ""
                alert.informativeText = "A new version of Vidp is available: v\(latestVersion) (you have v\(currentVersion)).\(playingNote)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Later")
                self.runModalPaused {
                    if alert.runModal() == .alertFirstButtonReturn {
                        self.downloadAndInstallUpdate(from: json, version: latestVersion)
                    }
                }
            }
        }
        task.resume()
    }

    private func downloadAndInstallUpdate(from release: [String: Any], version: String) {
        guard let assets = release["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == "vidp.app.zip" }),
              let checksumAsset = assets.first(where: { $0["name"] as? String == "vidp.app.zip.sha256" }),
              let urlString = asset["browser_download_url"] as? String,
              let checksumURLString = checksumAsset["browser_download_url"] as? String,
              let url = URL(string: urlString) else {
            showUpdateError("This release does not contain a downloadable app archive.")
            return
        }
        guard let checksumURL = URL(string: checksumURLString) else {
            showUpdateError("This release does not contain a valid app checksum.")
            return
        }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("vidp-update-\(UUID().uuidString)", isDirectory: true)
        let archiveURL = temporaryDirectory.appendingPathComponent("vidp.app.zip")
        let extractedURL = temporaryDirectory.appendingPathComponent("vidp.app", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        } catch {
            showUpdateError("Could not prepare the update: \(error.localizedDescription)")
            return
        }

        URLSession.shared.dataTask(with: checksumURL) { [weak self] checksumData, _, checksumError in
            guard let self else { return }
            guard let checksumData, checksumError == nil,
                  let checksumText = String(data: checksumData, encoding: .utf8),
                  let expectedChecksum = checksumText.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }).first,
                  expectedChecksum.count == 64 else {
                self.finishUpdateFailure(temporaryDirectory, message: "The app checksum could not be downloaded.")
                return
            }

            let task = URLSession.shared.downloadTask(with: url) { downloadedURL, _, error in
                guard let downloadedURL, error == nil else {
                    self.finishUpdateFailure(temporaryDirectory, message: error?.localizedDescription ?? "The download failed.")
                    return
                }

                do {
                    try FileManager.default.moveItem(at: downloadedURL, to: archiveURL)
                    try self.verifyChecksum(of: archiveURL, expected: String(expectedChecksum))
                    try self.extractUpdate(archiveURL: archiveURL, extractedURL: extractedURL)
                    try self.validateUpdate(at: extractedURL, version: version)
                    try self.installUpdate(from: extractedURL, temporaryDirectory: temporaryDirectory, version: version)
                } catch {
                    self.finishUpdateFailure(temporaryDirectory, message: error.localizedDescription)
                }
            }
            task.resume()
        }
        .resume()
    }

    private func verifyChecksum(of archiveURL: URL, expected: String) throws {
        let data = try Data(contentsOf: archiveURL)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw NSError(domain: "vidp.update", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "The downloaded app checksum does not match."])
        }
    }

    private func extractUpdate(archiveURL: URL, extractedURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extractedURL.deletingLastPathComponent().path]
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "vidp.update", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "The app archive could not be extracted." : output])
        }
    }

    private func validateUpdate(at appURL: URL, version: String) throws {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let executableURL = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executableURL.path),
              let installedVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
              installedVersion == version else {
            throw NSError(domain: "vidp.update", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The downloaded app archive is invalid."])
        }
    }

    private func installUpdate(from appURL: URL, temporaryDirectory: URL, version: String) throws {
        let fileManager = FileManager.default
        let backupURL = URL(fileURLWithPath: "/Applications/.vidp.app.previous", isDirectory: true)

        if fileManager.fileExists(atPath: applicationPath.path) {
            guard let existingBundle = Bundle(url: applicationPath),
                  existingBundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
                throw NSError(domain: "vidp.update", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "/Applications/vidp.app belongs to another app."])
            }
            try fileManager.moveItem(at: applicationPath, to: backupURL)
        }

        do {
            try fileManager.moveItem(at: appURL, to: applicationPath)
        } catch {
            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.moveItem(at: backupURL, to: applicationPath)
            }
            throw error
        }

        try? fileManager.removeItem(at: backupURL)
        try? fileManager.removeItem(at: temporaryDirectory)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.showUpdateReady(version: version)
        }
    }

    private func showUpdateReady(version: String) {
        let alert = NSAlert()
        alert.messageText = "Update Ready to Restart"
        alert.informativeText = "Vidp v\(version) has been installed. Restart now to use the update, or choose Later to keep using this session."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Restart")
        alert.addButton(withTitle: "Later")

        var response: NSApplication.ModalResponse = .alertSecondButtonReturn
        runModalPaused(shouldResume: { response == .alertSecondButtonReturn }) {
            response = alert.runModal()
        }

        if response == .alertFirstButtonReturn {
            // Flush position now; the periodic save may not have run yet.
            savePosition()
            let reopenPath = currentFilePath
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            // Reopen the current video; its saved position resumes playback.
            relaunch.arguments = reopenPath.map { ["-n", applicationPath.path, "--args", $0] }
                ?? ["-n", applicationPath.path]
            do {
                try relaunch.run()
            } catch {
                showUpdateError("The update was installed but the app could not be reopened: \(error.localizedDescription)")
                return
            }
            NSApp.terminate(nil)
        } else {
            resumeAfterModalPanel()
        }
    }

    private func finishUpdateFailure(_ temporaryDirectory: URL, message: String) {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        DispatchQueue.main.async { [weak self] in
            self?.showUpdateError(message)
        }
    }

    private func showUpdateError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Update Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        runModalPaused { alert.runModal() }
        // Failures never reach the relaunch that normally ends a Download hold.
        resumeAfterModalPanel()
    }

    func playerView(_ playerView: PlayerView, didReceiveFile path: String) {
        open(path: path)
    }

    private func open(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            NSLog("vidp: no such file: \(path)")
            // Cold-start with a bad path must still show the homepage.
            revealHomepage()
            return
        }
        savePosition()
        // Capture the homepage size only when opening from it while windowed;
        // overwriting here with a video-sized or fullscreen frame is what leaked
        // the video size into the homepage.
        if savedWindowSize == nil, !window.styleMask.contains(.fullScreen) {
            savedWindowSize = hasShownWindow
                ? (window.contentView?.bounds.size ?? Self.homepageContentSize)
                : Self.homepageContentSize
        }
        hudOverlay?.setFileLoaded(false)
        currentVideoAspectRatio = nil
        let filename = URL(fileURLWithPath: path).lastPathComponent
        let parsed = MediaNameParser.parse(filename: filename)
        hudOverlay?.setTitle(parsed.title, meta: parsed.metaLine)
        // Synchronous: a cold-start open must never flash the homepage while
        // mpv decodes the first frame.
        playerView.hideOverlay()
        // Deferred cold-start: the first video-size event shows the window at
        // video size (see playerDidUpdateVideoSize).
        if hasShownWindow {
            window.makeKeyAndOrderFront(nil)
        }
        currentFilePath = path
        homepageView.setPlaybackActive(true)
        playerView.load(path: path)
        startPositionTimer()
    }

    private func closeCurrentVideo() {
        savePosition()
        saveVolume()
        positionTimer?.invalidate()
        playerView.stop()
        closeSettingsSidebar()
        hudOverlay.setFileLoaded(false)
        currentFilePath = nil
        homepageView.setPlaybackActive(false)
        // Fullscreen can't resize in place. Exit it only when the homepage was
        // windowed; windowDidExitFullScreen restores its size.
        if window.styleMask.contains(.fullScreen) {
            if savedWindowSize != nil {
                // Hide the transition: AppKit restores the pre-fullscreen frame
                // before windowDidExitFullScreen resizes, flashing the wrong size.
                window.alphaValue = 0
                window.toggleFullScreen(nil)
            }
            return
        }
        if let size = savedWindowSize {
            window.setContentSize(size)
            window.center()
        }
        savedWindowSize = nil
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        // Un-hide regardless of why we exited (alpha is 1 in normal paths).
        window.alphaValue = 1
        // Back was hit while fullscreen: restore the deferred homepage size.
        guard currentFilePath == nil, let size = savedWindowSize else { return }
        window.setContentSize(size)
        window.center()
        savedWindowSize = nil
    }

    // Takes NSWindow, not Notification, or AppKit never calls it — and a mismatch
    // only warns. Kept in the class body so that warning stays the signal.
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        window.alphaValue = 1
    }

    /// Safety net: AppKit can fail a fullscreen exit silently, leaving
    /// closeCurrentVideo's `alphaValue = 0` with no visible window.
    ///
    /// ponytail: only catches failures involving a focus change; if the window was
    /// already key, recovery needs a Cmd+Tab away and back. A timeout would cover
    /// the rest but can unmask mid-animation — if that trade is worth revisiting,
    /// gate it on an NSWindowDidResize signal instead.
    func windowDidBecomeKey(_ notification: Notification) {
        guard window.alphaValue < 1 else { return }
        window.alphaValue = 1
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
            self?.updateNowPlayingInfo()
        }
    }

    private func saveVolume() {
        guard let playerView else { return }
        if let vol = playerView.doubleProperty("volume") {
            UserDefaults.standard.set(Int(vol), forKey: "volume")
        }
    }

    private func restoreVolume() {
        guard let playerView else { return }
        let vol = UserDefaults.standard.integer(forKey: "volume")
        guard vol > 0 else { return }
        playerView.setProperty("volume", "\(min(100, vol))")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !isPiPActive
    }

    func applicationWillTerminate(_ notification: Notification) {
        positionTimer?.invalidate()
        savePosition()
        saveVolume()
    }

    // MARK: PlayerDelegate

    func playerDidUpdateVideoSize(width: Int64, height: Int64) {
        // Straggler mpv size events after back must never resize the homepage.
        guard currentFilePath != nil else { return }
        guard width > 0, height > 0 else { return }
        currentVideoAspectRatio = CGFloat(width) / CGFloat(height)
        guard let screen = window.screen ?? NSScreen.main else { return }
        playerView.hideOverlay()
        // In fullscreen mpv letterboxes the new aspect ratio itself; resizing here
        // would shrink the fullscreen window to windowed size, leaving blank space.
        guard !window.styleMask.contains(.fullScreen) else { return }
        let sidebarWidth = isSettingsOpen
            ? settingsSplitItem.minimumThickness + splitViewDividerWidth
            : 0
        let maxW = max(320, screen.visibleFrame.width * 0.9 - sidebarWidth)
        let maxH = screen.visibleFrame.height * 0.9
        let aspect = CGFloat(width) / CGFloat(height)
        var size = CGSize(width: maxW, height: maxW / aspect)
        if size.height > maxH {
            size = CGSize(width: maxH * aspect, height: maxH)
        }
        window.setContentSize(NSSize(width: size.width + sidebarWidth, height: size.height))
        window.center()
        // Deferred cold-start open: appear once, directly at video size.
        revealHomepage()
    }

    private var splitViewDividerWidth: CGFloat {
        (window.contentViewController?.view as? NSSplitView)?.dividerThickness ?? 1
    }

    private func updateNowPlayingInfo() {
        guard let playerView, let path = currentFilePath else { return }
        let title = MediaNameParser.parse(filename: URL(fileURLWithPath: path).lastPathComponent).prettyTitle()
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        if let elapsed = playerView.doubleProperty("time-pos") {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        if let duration = playerView.doubleProperty("duration") {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPaused ? .paused : .playing
    }

    func playerDidUpdatePlaybackState(isPaused: Bool) {
        self.isPaused = isPaused
        pipController?.playing = !isPaused
        hudOverlay.setPaused(isPaused)
        updateSleepActivity(paused: isPaused)
        updateNowPlayingInfo()
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
        // Never leave a deferred cold-start open invisible.
        revealHomepage()
    }

    func playerDidEndFile() {
        guard currentFilePath != nil else {
            playerView.showOverlay()
            revealHomepage()
            return
        }
        guard playAdjacent(offset: 1) else {
            playerView.showOverlay()
            revealHomepage()
            return
        }
    }

    func playerDidRequestNext() {
        playAdjacent(offset: 1)
    }

    func playerDidRequestPrev() {
        playAdjacent(offset: -1)
    }

    func playerHasNext() -> Bool {
        guard let (files, idx) = adjacentFiles() else { return false }
        return files.indices.contains(idx + 1)
    }

    /// Plays the video `offset` slots away in the folder's natural-sorted list;
    /// false when there is no such file.
    @discardableResult
    private func playAdjacent(offset: Int) -> Bool {
        guard let (files, idx) = adjacentFiles(),
              files.indices.contains(idx + offset) else {
            return false
        }
        playerView.unpause()
        let dir = (currentFilePath! as NSString).deletingLastPathComponent
        open(path: dir + "/" + files[idx + offset])
        return true
    }

    /// Current folder's video files (natural-sorted) plus the open file's index.
    private func adjacentFiles() -> ([String], Int)? {
        guard let cur = currentFilePath else { return nil }
        let ns = cur as NSString
        let dir = ns.deletingLastPathComponent
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { vidExts.contains(($0 as NSString).pathExtension.lowercased()) }
            // localizedStandardCompare = Finder-style natural sort (ep2 < ep10)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let idx = files.firstIndex(of: ns.lastPathComponent) else { return nil }
        return (files, idx)
    }

    func playerDidFileLoad() {
        guard let path = currentFilePath else { return }
        hudOverlay.setFileLoaded(true)
        hudOverlay.refreshTrackButtons()
        hudOverlay.updateMuteIcon(muted: playerView.boolProperty("mute") ?? false)
        restorePosition(for: path)
        updateNowPlayingInfo()
        // Fallback when no size event arrives (audio-only); delayed so it can't
        // race the size event and reintroduce the flash.
        if !hasShownWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.currentFilePath != nil else { return }
                self.revealHomepage()
            }
        }
    }

    func playerDidAdjustVolume(_ volume: Int) {
        hudOverlay.updateMuteIcon(muted: playerView.boolProperty("mute") ?? false)
        hudOverlay.showVolumeIndicator(volume)
    }

    func playerDidSeek(seconds: Double) {
        hudOverlay.showSkipIndicator(seconds: seconds)
    }

    func playerDidToggleMute(_ muted: Bool) {
        hudOverlay.setMuted(muted)
    }
}
