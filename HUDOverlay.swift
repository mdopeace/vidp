import AppKit
import CMPV

// MARK: - HUD Overlay

/// Slider that reports when a scrub gesture begins and ends so the HUD can
/// pause on hold and resume on release.
final class ScrubSlider: NSSlider {
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onBegin?()
        super.mouseDown(with: event)
        onEnd?()
    }
}

final class NudgeUpLabel: NSTextField {
    var yNudge: CGFloat = 1
    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: yNudge, left: 0, bottom: -yNudge, right: 0)
    }
}

final class HUDOverlayView: NSView {
    private var hideTimer: Timer?
    private var displayTimer: Timer?
    private(set) var isPaused: Bool = false
    private(set) var isFileLoaded: Bool = false
    private let hideDelay: TimeInterval = 3.0
    weak var playerView: PlayerView?
    private var wasPlayingBeforeSettings = false

    private var playGlass: NSGlassEffectView!
    private var rewindGlass: NSGlassEffectView!
    private var forwardGlass: NSGlassEffectView!
    private var settingsGlass: NSGlassEffectView!
    private var settingsSheet: NSWindow?

    private var elapsedLabel: NSTextField!
    private var remainingLabel: NSTextField!
    private var progressBar: NSSlider!
    private var isScrubbing = false
    private var wasPlayingBeforeScrub = false
    private var titleLabel: NSTextField!
    private var smoothTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        alphaValue = 0

        rewindGlass = makeTransportButton(
            symbol: "gobackward.10", pointSize: 28, diameter: 60,
            action: #selector(rewindTapped))
        playGlass = makeTransportButton(
            symbol: "play.fill", pointSize: 42, diameter: 90,
            action: #selector(playTapped))
        forwardGlass = makeTransportButton(
            symbol: "goforward.10", pointSize: 28, diameter: 60,
            action: #selector(forwardTapped))

        let transportStack = NSStackView(views: [rewindGlass, playGlass, forwardGlass])
        transportStack.spacing = 44
        transportStack.alignment = .centerY
        transportStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(transportStack)

        NSLayoutConstraint.activate([
            transportStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            transportStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        // Top-right: subtitles + audio + settings pickers
        let subsGlass = makeTransportButton(
            symbol: "captions.bubble", pointSize: 15, diameter: 40,
            action: #selector(subtitleTapped))
        let audioGlass = makeTransportButton(
            symbol: "speaker.wave.2", pointSize: 15, diameter: 40,
            action: #selector(audioTapped))
        settingsGlass = makeTransportButton(
            symbol: "gearshape", pointSize: 15, diameter: 40,
            action: #selector(settingsTapped))
        let topRow = NSStackView(views: [audioGlass, subsGlass, settingsGlass])
        topRow.spacing = 12
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topRow)
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            topRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        // Title above progress bar, left-aligned
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = AppSettings.hudFont(named: AppSettings.hudFontName, size: 30,
                                          bold: AppSettings.hudBold, italic: AppSettings.hudItalic)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleLabel.setContentHuggingPriority(.required, for: .vertical)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        // Long titles must never push the window wider during layout passes
        // (fullscreen exit re-solves window fitting size; the <=0.7W cap scales
        // with the window, so only low compression resistance stops the growth).
        titleLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        titleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)

        // Bottom progress bar
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        elapsedLabel = NudgeUpLabel(labelWithString: "00:00:00")
        elapsedLabel.font = timeFont
        elapsedLabel.textColor = .white
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        remainingLabel = NudgeUpLabel(labelWithString: "-00:00:00")
        remainingLabel.font = timeFont
        remainingLabel.textColor = NSColor(white: 1, alpha: 0.6)
        remainingLabel.translatesAutoresizingMaskIntoConstraints = false

        progressBar = ScrubSlider(value: 0, minValue: 0, maxValue: 1,
                               target: self, action: #selector(scrubChanged))
        progressBar.isContinuous = true
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        (progressBar as? ScrubSlider)?.onBegin = { [weak self] in self?.scrubBegan() }
        (progressBar as? ScrubSlider)?.onEnd = { [weak self] in self?.scrubEnded() }

        let barRow = NSStackView(views: [elapsedLabel, progressBar, remainingLabel])
        barRow.spacing = 10
        barRow.alignment = .centerY
        barRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(barRow)
        NSLayoutConstraint.activate([
            barRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 36),
            barRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -36),
            barRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -36),
            titleLabel.leadingAnchor.constraint(equalTo: barRow.leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: barRow.topAnchor, constant: -8),
            titleLabel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.7),
            elapsedLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            remainingLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .appSettingsDidChange, object: nil)
    }

    override func layout() {
        super.layout()
        titleLabel.preferredMaxLayoutWidth = bounds.width * 0.7
        // Full 30pt at fullscreen width, scaled down proportionally in windowed mode
        let refWidth = window?.screen?.frame.width ?? bounds.width
        let size = max(18, 30 * min(1, bounds.width / refWidth))
        titleLabel.font = AppSettings.hudFont(named: AppSettings.hudFontName, size: size,
                                          bold: AppSettings.hudBold, italic: AppSettings.hudItalic)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Transport buttons

    private func makeTransportButton(symbol: String, pointSize: CGFloat,
                                     diameter: CGFloat, action: Selector) -> NSGlassEffectView {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) ?? NSImage()

        let button = NSButton(image: img, target: self, action: action)
        button.isBordered = false
        button.contentTintColor = .white
        button.wantsLayer = true

        let glass = NSGlassEffectView()
        glass.style = .regular
        glass.cornerRadius = diameter / 2
        glass.contentView = button
        glass.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glass.widthAnchor.constraint(equalToConstant: diameter),
            glass.heightAnchor.constraint(equalToConstant: diameter),
        ])

        return glass
    }

    @objc private func rewindTapped() { playerView?.seek(seconds: -10); resetHideTimer() }
    @objc private func playTapped()   { playerView?.cyclePause(); resetHideTimer() }
    @objc private func forwardTapped(){ playerView?.seek(seconds: 10); resetHideTimer() }

    private func showTrackMenu(type: String, property: String, for button: NSView) {
        guard let pv = playerView else { return }
        let tracks = pv.trackList().filter { ($0["type"] as? String) == type }
        guard !tracks.isEmpty else { return }
        let menu = NSMenu()
        let sel = #selector(trackMenuItemTapped(_:))
        if type == "sub" {
            let off = NSMenuItem(title: "Off", action: sel, keyEquivalent: "")
            off.target = self
            off.representedObject = property
            off.tag = 0
            let current = pv.trackList().first { ($0["type"] as? String) == type && ($0["selected"] as? Int64) == 1 }
            if current == nil { off.state = .on }
            menu.addItem(off)
        }
        for track in tracks {
            guard let id = track["id"] as? Int64 else { continue }
            let title = (track["title"] as? String) ?? "Track \(id)"
            let lang = (track["lang"] as? String) ?? ""
            let label = lang.isEmpty ? title : "\(lang.uppercased()) — \(title)"
            let item = NSMenuItem(title: label, action: sel, keyEquivalent: "")
            item.target = self
            item.representedObject = property
            item.tag = Int(id)
            if (track["selected"] as? Int64) == 1 { item.state = .on }
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent ?? NSApplication.shared.currentEvent!, for: button)
        resetHideTimer()
    }

    @objc private func subtitleTapped() {
        showTrackMenu(type: "sub", property: "sid", for: senderView())
    }

    @objc private func audioTapped() {
        showTrackMenu(type: "audio", property: "aid", for: senderView())
    }

    @objc private func settingsTapped() {
        if settingsSheet != nil {
            closeSettings()
            return
        }
        wasPlayingBeforeSettings = !(playerView?.boolProperty("pause") ?? true)
        if wasPlayingBeforeSettings { playerView?.cyclePause() }

        let settingsView = SettingsPopoverView(frame: NSRect(x: 0, y: 0, width: 400, height: 420))
        settingsView.onDone = { [weak self] in self?.closeSettings() }
        let vc = NSViewController()
        vc.view = settingsView

        let sheet = NSWindow(contentViewController: vc)
        sheet.title = "Settings"
        sheet.styleMask = [.titled, .closable]
        sheet.isReleasedWhenClosed = false
        window?.beginSheet(sheet)
        settingsSheet = sheet
    }

    private func closeSettings() {
        guard let sheet = settingsSheet, let window else { return }
        window.endSheet(sheet)
        settingsSheet = nil
        if wasPlayingBeforeSettings { playerView?.cyclePause() }
        wasPlayingBeforeSettings = false
        resetHideTimer()
    }

    func showSettingsPopover() {
        alphaValue = 1
        startDisplayTimer()
        settingsTapped()
    }

    @objc private func settingsDidChange() {
        titleLabel.font = AppSettings.hudFont(
            named: AppSettings.hudFontName,
            size: max(18, 30 * min(1, bounds.width / (window?.screen?.frame.width ?? bounds.width))),
            bold: AppSettings.hudBold, italic: AppSettings.hudItalic)
        needsLayout = true
    }

    private func senderView() -> NSView {
        guard let event = NSApp.currentEvent else { return self }
        return hitTest(convert(event.locationInWindow, from: nil)) ?? self
    }

    @objc private func trackMenuItemTapped(_ sender: NSMenuItem) {
        guard let property = sender.representedObject as? String else { return }
        playerView?.setTrack(property, id: sender.tag)
        if let path = playerView?.currentPath {
            UserDefaults.standard.set(sender.tag, forKey: "\(property):\(path)")
        }
        resetHideTimer()
    }

    @objc private func scrubChanged() {
        guard let pv = playerView else { return }
        let duration = pv.doubleProperty("duration") ?? 0
        let target = progressBar.doubleValue * duration
        String(target).withCString { val in
            "seek".withCString { cmd in
                "absolute".withCString { flag in
                    var args: [UnsafePointer<CChar>?] = [cmd, val, flag, nil]
                    mpv_command(pv.mpv, &args)
                }
            }
        }
        resetHideTimer()
    }

    private func scrubBegan() {
        guard let pv = playerView else { return }
        isScrubbing = true
        // Pause on hold only if currently playing; if already paused, do nothing.
        wasPlayingBeforeScrub = !(pv.boolProperty("pause") ?? false)
        if wasPlayingBeforeScrub { pv.cyclePause() }
        // Sync the slider to the click position immediately so the jump is
        // instant rather than waiting for the next updateDisplay().
        let duration = pv.doubleProperty("duration") ?? 0
        let pos = pv.doubleProperty("time-pos") ?? 0
        if duration > 0 { progressBar.doubleValue = pos / duration }
    }

    private func scrubEnded() {
        if wasPlayingBeforeScrub {
            playerView?.unpause()
        }
        wasPlayingBeforeScrub = false
        isScrubbing = false
    }

    func updateDisplay() {
        guard let pv = playerView, !isScrubbing else { return }
        let pos = pv.doubleProperty("time-pos") ?? 0
        let dur = pv.doubleProperty("duration") ?? 0
        let target = dur > 0 ? pos / dur : 0
        elapsedLabel.stringValue = formatTime(pos)
        remainingLabel.stringValue = "-\(formatTime(dur - pos))"

        // Interpolate the knob toward the target at ~30fps so it glides
        // smoothly instead of jumping in 250ms steps.
        if target != progressBar.doubleValue {
            smoothTimer?.invalidate()
            smoothTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let current = self.progressBar.doubleValue
                let delta = target - current
                if abs(delta) < 0.0005 {
                    self.progressBar.doubleValue = target
                    self.smoothTimer?.invalidate()
                    self.smoothTimer = nil
                    return
                }
                self.progressBar.doubleValue = current + delta * 0.15
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00:00" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func resetHideTimer() {
        guard isFileLoaded, !isPaused else { return }
        startHideTimer()
    }

    func updatePlayIcon(paused: Bool) {
        let name = paused ? "play.fill" : "pause.fill"
        let config = NSImage.SymbolConfiguration(pointSize: 42, weight: .medium)
        (playGlass.contentView as? NSButton)?.image =
            NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        alphaValue > 0.01 ? super.hitTest(point) : nil
    }

    override func updateTrackingAreas() {
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        guard isFileLoaded, !isPaused else { return }
        showHUD()
        startHideTimer()
    }

    override func mouseExited(with event: NSEvent) {
        guard isFileLoaded, !isPaused else { return }
        hideHUD()
    }

    private func showHUD() {
        guard isFileLoaded else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 1.0
        }
        setSubPos(8)
        startDisplayTimer()
    }

    private func hideHUD() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            self.animator().alphaValue = 0.0
        }
        setSubPos(100)
        NSCursor.setHiddenUntilMouseMoves(true)
        stopDisplayTimer()
    }

    private func setSubPos(_ pos: Int) {
        guard isFileLoaded else { return }
        playerView?.setProperty("sub-pos", String(pos))
    }

    private func startHideTimer() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            guard let self, self.isFileLoaded, !self.isPaused else { return }
            self.hideHUD()
        }
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
        updateDisplay()
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
        smoothTimer?.invalidate()
        smoothTimer = nil
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        updatePlayIcon(paused: paused)
        guard isFileLoaded else {
            alphaValue = 0
            return
        }
        if paused {
            hideTimer?.invalidate()
            showHUD()
        } else {
            showHUD()
            startHideTimer()
        }
    }

    func setFileLoaded(_ loaded: Bool) {
        isFileLoaded = loaded
        if !loaded {
            hideTimer?.invalidate()
            stopDisplayTimer()
            alphaValue = 0
        }
    }

    func setTitle(_ title: String) {
        titleLabel.stringValue = title
        titleLabel.needsLayout = true
        needsLayout = true
    }
}
