import AppKit
import OpenGL.GL3
import OpenGL.GL
import CoreVideo
import MediaPlayer
import UniformTypeIdentifiers
import CMPV

protocol PlayerDelegate: AnyObject {
    func playerDidUpdateVideoSize(width: Int64, height: Int64)
    func playerDidUpdatePlaybackState(isPaused: Bool)
    func playerDidEncounterError(_ message: String)
    func playerDidEndFile()
    func playerDidFileLoad()
    func playerView(_ playerView: PlayerView, didReceiveFile path: String)
}

// C callbacks must be top-level functions.

private func glGetProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return CFBundleGetFunctionPointerForName(
        CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
        String(cString: name) as CFString)
}

private func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let view = Unmanaged<PlayerView>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { view.playerLayer?.setNeedsDisplay() }
}


/// CAOpenGLLayer that renders mpv frames into its own drawable.
final class PlayerLayer: CAOpenGLLayer {
    weak var player: PlayerView?
    var renderCtx: OpaquePointer?
    private(set) var cglCtx: CGLContextObj?
    private(set) var cglPf: CGLPixelFormatObj?

    override init() {
        super.init()
        isAsynchronous = false
        isOpaque = false

        // Eagerly create THE pixel format + context we'll use everywhere,
        // so mpv's render context binds to the exact context CA draws with.
        let nspf = NSOpenGLPixelFormat(attributes: [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersionLegacy),
            UInt32(NSOpenGLPFADoubleBuffer),
            0,
        ])
        if let obj = nspf?.cglPixelFormatObj {
            cglPf = obj
            var ctx: CGLContextObj?
            CGLCreateContext(obj, nil, &ctx)
            cglCtx = ctx
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    // Superclass implementation flushes the drawable; call after mpv renders.
    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let player, let renderCtx, player.fileLoaded else {
            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

        let b = player.bounds
        let scale = player.window?.backingScaleFactor ?? 2
        let w = Int32(max(1, b.width * scale))
        let h = Int32(max(1, b.height * scale))
        var flipY: CInt = 1
        // CAOpenGLLayer backs itself with an internal IOSurface FBO — render into THAT,
        // not FBO 0 (which has no drawable here).
        var boundFbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &boundFbo)
        var fbo = mpv_opengl_fbo(fbo: Int32(boundFbo), w: w, h: h, internal_format: 0)
        withUnsafeMutableBytes(of: &fbo) { fboBuf in
            withUnsafeMutableBytes(of: &flipY) { flipBuf in
                guard let fboPtr = fboBuf.baseAddress, let flipPtr = flipBuf.baseAddress else { return }
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param(),
                ]
                _ = mpv_render_context_render(renderCtx, &params)
            }
        }
        super.draw(inCGLContext: ctx, pixelFormat: pixelFormat, forLayerTime: t, displayTime: ts)
        mpv_render_context_report_swap(renderCtx)
    }

    // Always hand back the exact pixel format + context mpv was created with.
    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPf!
    }

    override func releaseCGLPixelFormat(_ pf: CGLPixelFormatObj) {}

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglCtx!
    }

    override func releaseCGLContext(_ ctx: CGLContextObj) {}
}

final class PlayerView: NSView {
    private(set) var mpv: OpaquePointer?
    private(set) var renderCtx: OpaquePointer?
    private(set) var playerLayer: PlayerLayer?
    weak var delegate: PlayerDelegate?
    private(set) var fileLoaded = false

    private var overlayView: NSView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var cursorHideTimer: Timer?

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        autoresizingMask = [.width, .height]
        let layer = PlayerLayer()
        layer.player = self
        self.layer = layer
        playerLayer = layer

        setupOverlay()
        registerForDraggedTypes([.fileURL])

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(enteredFullScreen),
                           name: NSWindow.didEnterFullScreenNotification, object: nil)
        center.addObserver(self, selector: #selector(exitedFullScreen),
                           name: NSWindow.didExitFullScreenNotification, object: nil)
    }

    // MARK: - Cursor Auto-Hide (QuickTime-style)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        scheduleCursorHide()
    }

    private func scheduleCursorHide() {
        cursorHideTimer?.invalidate()
        cursorHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self, let window else { return }
            if window.styleMask.contains(.fullScreen),
               fileLoaded,
               boolProperty("pause") == false {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    @objc private func enteredFullScreen(_ note: Notification) {
        guard note.object as? NSWindow === window else { return }
        scheduleCursorHide()
    }

    @objc private func exitedFullScreen(_ note: Notification) {
        guard note.object as? NSWindow === window else { return }
        cursorHideTimer?.invalidate()
        NSCursor.setHiddenUntilMouseMoves(false)
    }

    private func setupOverlay() {
        overlayView = NSView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlayView)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "arrow.down.doc", accessibilityDescription: "Drop a video file")
        iconView.contentTintColor = NSColor(white: 1, alpha: 0.5)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        overlayView.addSubview(iconView)

        titleLabel = NSTextField(labelWithString: "Drag & drop a video to play")
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.85)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(titleLabel)

        subtitleLabel = NSTextField(labelWithString: "or press \u{2318}O to browse files")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor(white: 1, alpha: 0.45)
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(subtitleLabel)

        NSLayoutConstraint.activate([
            overlayView.centerXAnchor.constraint(equalTo: centerXAnchor),
            overlayView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.topAnchor.constraint(equalTo: overlayView.topAnchor),
            iconView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 14),
            titleLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            subtitleLabel.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            subtitleLabel.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor),
        ])
    }

    func showOverlay() {
        overlayView.isHidden = false
    }

    func hideOverlay() {
        overlayView.isHidden = true
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasValidFile(sender: sender) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.overlayView.animator().wantsLayer = true
                self.overlayView.animator().layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.6).cgColor
                self.overlayView.animator().layer?.cornerRadius = 16
            }
            return .copy
        }
        return []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.overlayView.animator().layer?.backgroundColor = NSColor.clear.cgColor
        }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hasValidFile(sender: sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        overlayView.layer?.borderWidth = 0
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: ["public.movie"]
        ]
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL],
              let url = urls.first else { return false }
        delegate?.playerView(self, didReceiveFile: url.path)
        return true
    }

    private func hasValidFile(sender: NSDraggingInfo) -> Bool {
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingContentsConformToTypes: ["public.movie"]
        ]
        return sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: opts)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            playerLayer?.contentsScale = window.backingScaleFactor
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 124: // →
            seek(seconds: event.modifierFlags.contains(.shift) ? 30 : 10)
        case 123: // ←
            seek(seconds: event.modifierFlags.contains(.shift) ? -30 : -10)
        default:
            switch event.characters {
            case "f":
                window?.toggleFullScreen(nil)
            case " ":
                cyclePause()
            case "l":
                nextTrack()
            case "h":
                prevTrack()
            default:
                super.keyDown(with: event)
            }
        }
    }

    func cyclePause() {
        guard let mpv else { return }
        "cycle".withCString { cmd in
            "pause".withCString { prop in
                var args: [UnsafePointer<CChar>?] = [cmd, prop, nil]
                mpv_command(mpv, &args)
            }
        }
    }

    func nextTrack() {
        guard let mpv else { return }
        "playlist-next".withCString { cmd in
            var args: [UnsafePointer<CChar>?] = [cmd, nil]
            mpv_command(mpv, &args)
        }
    }

    func prevTrack() {
        guard let mpv else { return }
        "playlist-prev".withCString { cmd in
            var args: [UnsafePointer<CChar>?] = [cmd, nil]
            mpv_command(mpv, &args)
        }
    }

    func unpause() {
        guard let mpv else { return }
        "set".withCString { cmd in
            "pause".withCString { prop in
                "no".withCString { val in
                    var args: [UnsafePointer<CChar>?] = [cmd, prop, val, nil]
                    mpv_command(mpv, &args)
                }
            }
        }
    }

    func seek(seconds: Double) {
        guard let mpv else { return }
        String(seconds).withCString { val in
            "seek".withCString { cmd in
                "relative".withCString { flag in
                    var args: [UnsafePointer<CChar>?] = [cmd, val, flag, nil]
                    mpv_command(mpv, &args)
                }
            }
        }
    }

    func boolProperty(_ name: String) -> Bool? {
        guard let mpv else { return nil }
        var value: Int32 = 0
        return mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &value) >= 0 ? value != 0 : nil
    }

    /// Initializes mpv + its render context. Returns an error message on failure.
    func setup() -> String? {
        guard let layer = playerLayer, let glctx = layer.cglCtx else { return "no OpenGL context" }
        CGLSetCurrentContext(glctx)
        defer { CGLSetCurrentContext(nil) }

        guard let mpv = mpv_create() else { return "mpv_create() failed" }

        // Must be set before mpv_initialize().
        mpv_set_option_string(mpv, "vo", "libmpv")
        mpv_set_option_string(mpv, "hwdec", "videotoolbox")
        mpv_set_option_string(mpv, "keep-open", "always")
        mpv_set_option_string(mpv, "save-position-on-quit", "yes")

        guard mpv_initialize(mpv) >= 0 else {
            mpv_destroy(mpv)
            return "mpv_initialize() failed"
        }
        self.mpv = mpv

        var initParams = mpv_opengl_init_params(
            get_proc_address: glGetProcAddress,
            get_proc_address_ctx: nil)

        MPV_RENDER_API_TYPE_OPENGL.withCString { apiType in
            withUnsafeMutableBytes(of: &initParams) { initBuf in
                guard let initPtr = initBuf.baseAddress else { return }
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                     data: UnsafeMutableRawPointer(mutating: apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPtr),
                    mpv_render_param(),
                ]
                var ctx: OpaquePointer?
                guard mpv_render_context_create(&ctx, mpv, &params) >= 0, let ctx else {
                    mpv_destroy(mpv)
                    self.mpv = nil
                    return
                }
                self.renderCtx = ctx
                layer.renderCtx = ctx
                mpv_render_context_set_update_callback(
                    ctx, mpvUpdateCallback, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        guard renderCtx != nil else {
            mpv_destroy(mpv)
            self.mpv = nil
            return "mpv_render_context_create() failed"
        }

        mpv_observe_property(mpv, 0, "width", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "height", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        // Natural EOF never sends END_FILE under keep-open=always;
        // eof-reached flipping true is the real end-of-file signal.
        mpv_observe_property(mpv, 0, "eof-reached", MPV_FORMAT_FLAG)

        listenForEvents()
        return nil
    }

    func load(path: String) {
        guard let mpv else { return }
        fileLoaded = true
        scheduleCursorHide()
        "loadfile".withCString { cmd in
            path.withCString { p in
                var args: [UnsafePointer<CChar>?] = [cmd, p, nil]
                if mpv_command(mpv, &args) < 0 {
                    DispatchQueue.main.async {
                        self.delegate?.playerDidEncounterError("Could not load \(path)")
                    }
                }
            }
        }
    }

    func doubleProperty(_ name: String) -> Double? {
        guard let mpv else { return nil }
        var value: Double = 0
        return mpv_get_property(mpv, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    private func intProperty(_ name: String) -> Int64? {
        guard let mpv else { return nil }
        var value: Int64 = 0
        return mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    private func listenForEvents() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let mpv = self?.mpv {
                let event = mpv_wait_event(mpv, -1).pointee
                switch event.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    if let prop = event.data?.assumingMemoryBound(to: mpv_event_property.self) {
                        let name = String(cString: prop.pointee.name)
                        if name == "width" || name == "height" {
                            let w = self?.intProperty("width") ?? 0
                            let h = self?.intProperty("height") ?? 0
                            DispatchQueue.main.async {
                                self?.delegate?.playerDidUpdateVideoSize(width: w, height: h)
                            }
                        } else if name == "pause" {
                            let paused = self?.boolProperty("pause") ?? false
                            DispatchQueue.main.async {
                                self?.delegate?.playerDidUpdatePlaybackState(isPaused: paused)
                            }
                        } else if name == "eof-reached" {
                            if self?.boolProperty("eof-reached") == true {
                                DispatchQueue.main.async {
                                    self?.delegate?.playerDidEndFile()
                                }
                            }
                        }
                    }
                case MPV_EVENT_END_FILE:
                    if let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) {
                        // Only errors surface here; natural EOF arrives via eof-reached,
                        // and END_FILE(stop) just means a new file replaced this one.
                        if endFile.pointee.reason == MPV_END_FILE_REASON_ERROR {
                            let msg = String(cString: mpv_error_string(endFile.pointee.error))
                            DispatchQueue.main.async {
                                self?.fileLoaded = false
                                self?.delegate?.playerDidEncounterError(msg)
                            }
                        }
                    }
                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async {
                        self?.delegate?.playerDidFileLoad()
                    }
                case MPV_EVENT_SHUTDOWN:
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                    return
                default:
                    break
                }
            }
        }
    }

    deinit {
        if let renderCtx { mpv_render_context_free(renderCtx) }
        if let mpv { mpv_destroy(mpv) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, PlayerDelegate {
    var window: NSWindow!
    private var playerView: PlayerView!
    private var isPaused = true
    private var currentFilePath: String?
    private var positionTimer: Timer?
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
        window.title = "OTV"
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
            NSLog("OTV setup failed: \(error)")
        }
        playerView.delegate = self

        setupRemoteCommands()

        window.center()
        window.makeKeyAndOrderFront(nil)

        // CLI fallback: OTV.app/Contents/MacOS/OTV <file>
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let first = args.first {
            open(path: first)
        }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About OTV", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit OTV", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open\u{2026}", action: #selector(openDocument), keyEquivalent: "o")
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

        center.changePlaybackPositionCommand.addTarget { _ in
            return .commandFailed
        }
    }

    // Finder "Open With" sends files here (odoc Apple Event).
    func application(_ application: NSApplication, openFiles files: [String]) {
        open(path: files[0])
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

    func playerView(_ playerView: PlayerView, didReceiveFile path: String) {
        open(path: path)
    }

    private func open(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            NSLog("OTV: no such file: \(path)")
            return
        }
        savePosition()
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
            String(saved).withCString { val in
                "seek".withCString { cmd in
                    "absolute".withCString { flag in
                        var args: [UnsafePointer<CChar>?] = [cmd, val, flag, nil]
                        mpv_command(playerView.mpv, &args)
                    }
                }
            }
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
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: window.title,
            MPNowPlayingInfoPropertyPlaybackRate: isPaused ? 0.0 : 1.0,
        ]
        center.playbackState = isPaused ? .paused : .playing
    }

    func playerDidEncounterError(_ message: String) {
        NSLog("OTV playback error: \(message)")
        playerView.showOverlay()
    }

    func playerDidEndFile() {
        guard let cur = currentFilePath else {
            playerView.showOverlay()
            return
        }
        let ns = cur as NSString
        let dir = ns.deletingLastPathComponent
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { vidExts.contains(($0 as NSString).pathExtension.lowercased()) }
            // localizedStandardCompare = Finder-style natural sort (ep2 < ep10)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let idx = files.firstIndex(of: ns.lastPathComponent), idx + 1 < files.count else {
            playerView.showOverlay()
            return
        }
        playerView.unpause()
        open(path: dir + "/" + files[idx + 1])
    }

    func playerDidFileLoad() {
        guard let path = currentFilePath else { return }
        restorePosition(for: path)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
