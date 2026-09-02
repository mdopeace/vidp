import AppKit
import CMPV

final class PlayerView: NSView {
    private(set) var mpv: OpaquePointer?
    private(set) var renderCtx: OpaquePointer?
    private(set) var playerLayer: PlayerLayer?
    weak var delegate: PlayerDelegate?
    var onPiPToggle: (() -> Void)?
    private(set) var fileLoaded = false
    private(set) var currentPath: String?

    private var overlayView: NSView!
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
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

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .appSettingsDidChange, object: nil)
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
        titleLabel.font = .systemFont(ofSize: 20)
        titleLabel.textColor = NSColor(white: 1, alpha: 0.85)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        overlayView.addSubview(titleLabel)

        subtitleLabel = NSTextField(labelWithString: "or press \u{2318}O to browse files")
        subtitleLabel.font = .systemFont(ofSize: 13)
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
            case "p":
                onPiPToggle?()
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
        delegate?.playerDidRequestNext()
    }

    func prevTrack() {
        delegate?.playerDidRequestPrev()
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

    func seekAbsolute(_ seconds: Double) {
        guard let mpv else { return }
        String(seconds).withCString { val in
            "seek".withCString { cmd in
                "absolute".withCString { flag in
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
        AppSettings.applyOptions(to: mpv)

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
        currentPath = path
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

    func trackList() -> [[String: Any]] {
        guard let mpv else { return [] }
        var node = mpv_node()
        guard mpv_get_property(mpv, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return [] }
        defer { mpv_free_node_contents(&node) }
        guard let list = node.u.list else { return [] }
        var results: [[String: Any]] = []
        for i in 0..<Int(list.pointee.num) {
            let entry = list.pointee.values[i]
            guard entry.format == MPV_FORMAT_NODE_MAP else { continue }
            guard let map = entry.u.list else { continue }
            var dict: [String: Any] = [:]
            for j in 0..<Int(map.pointee.num) {
                guard let keyPtr = map.pointee.keys?[j] else { continue }
                let val = map.pointee.values![j]
                let key = String(cString: keyPtr)
                switch val.format {
                case MPV_FORMAT_INT64:
                    dict[key] = val.u.int64
                case MPV_FORMAT_FLAG:
                    dict[key] = val.u.flag != 0 ? Int64(1) : Int64(0)
                case MPV_FORMAT_STRING:
                    if let s = val.u.string { dict[key] = String(cString: s) }
                default:
                    break
                }
            }
            results.append(dict)
        }
        return results
    }

    func setProperty(_ name: String, _ value: String) {
        guard let mpv else { return }
        name.withCString { n in
            value.withCString { v in
                mpv_set_property_string(mpv, n, v)
            }
        }
    }

    func setTrack(_ property: String, id: Int) {
        guard let mpv else { return }
        let value = id == 0 ? "no" : "\(id)"
        "set".withCString { cmd in
            property.withCString { prop in
                value.withCString { val in
                    var args: [UnsafePointer<CChar>?] = [cmd, prop, val, nil]
                    mpv_command(mpv, &args)
                }
            }
        }
    }

    private func restoreSavedTracks() {
        guard let path = currentPath else { return }
        let defaults = UserDefaults.standard
        if let sub = defaults.object(forKey: "sid:\(path)") as? Int {
            setTrack("sid", id: sub)
        }
        if let audio = defaults.object(forKey: "aid:\(path)") as? Int {
            setTrack("aid", id: audio)
        }
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
                        self?.restoreSavedTracks()
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

    @objc private func settingsDidChange() {
        guard let mpv else { return }
        AppSettings.applySubtitle(to: mpv)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        if let renderCtx { mpv_render_context_free(renderCtx) }
        if let mpv { mpv_destroy(mpv) }
    }
}
