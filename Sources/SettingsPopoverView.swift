import AppKit

final class SettingsPopoverView: NSView {
    var onDone: (() -> Void)?

    private var hudFontPopup: NSPopUpButton!
    private var hudSystemCheck: NSButton!
    private var hudBoldCheck: NSButton!
    private var hudItalicCheck: NSButton!
    private var hudBorderSlider: NSSlider!
    private var hudBorderLabel: NSTextField!
    private var progressColorWell: NSColorWell!
    private var progressSystemCheck: NSButton!
    private var subFontPopup: NSPopUpButton!
    private var subSystemCheck: NSButton!
    private var subBoldCheck: NSButton!
    private var subItalicCheck: NSButton!
    private var subSizeSlider: NSSlider!
    private var subSizeLabel: NSTextField!
    private var subColorWell: NSColorWell!
    private var subBorderColorWell: NSColorWell!
    private var subBorderSlider: NSSlider!
    private var subBorderLabel: NSTextField!
    private var subShadowSlider: NSSlider!
    private var subShadowLabel: NSTextField!
    private var overrideCheck: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.state = .active
        blur.blendingMode = .behindWindow
        blur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blur)
        NSLayoutConstraint.activate([
            blur.leadingAnchor.constraint(equalTo: leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: trailingAnchor),
            blur.topAnchor.constraint(equalTo: topAnchor),
            blur.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let fonts = NSFontManager.shared.availableFontFamilies.sorted()

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let container = NSView()
        scroll.documentView = container
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        // Grouped rows: each box owns a vertical stack; the boxes join
        // the column where the old flat rows + text headers used to be.
        // (The sheet titlebar already says Settings, so no in-content header.)
        let osdRows = NSStackView()
        osdRows.orientation = .vertical
        osdRows.spacing = 8
        let subRows = NSStackView()
        subRows.orientation = .vertical
        subRows.spacing = 8

        // Title section
        let hudRow = makeFontRow(fonts: fonts, selected: AppSettings.hudFontName)
        hudFontPopup = hudRow.popup
        hudSystemCheck = hudRow.check
        hudFontPopup.target = self
        hudFontPopup.action = #selector(hudFontChanged)
        hudSystemCheck.target = self
        hudSystemCheck.action = #selector(hudSystemToggled)
        osdRows.addArrangedSubview(makeRow(hudRow.stack))

        hudBoldCheck = makeStyleCheck("Bold", #selector(hudBoldToggled), AppSettings.hudBold)
        hudItalicCheck = makeStyleCheck("Italic", #selector(hudItalicToggled), AppSettings.hudItalic)
        osdRows.addArrangedSubview(makeStyleRow(hudSystemCheck, hudBoldCheck, hudItalicCheck))

        // Title outline (halo)
        let hudBorderRow = NSStackView()
        hudBorderRow.spacing = 8
        hudBorderRow.alignment = .centerY
        hudBorderRow.distribution = .fill
        hudBorderRow.addArrangedSubview(rowLabel("Outline"))
        hudBorderSlider = NSSlider(value: AppSettings.hudBorderSize, minValue: 0, maxValue: 10,
                                   target: self, action: #selector(hudBorderChanged))
        flexSlider(hudBorderSlider)
        hudBorderRow.addArrangedSubview(hudBorderSlider)
        hudBorderLabel = makeLabel(String(Int(AppSettings.hudBorderSize)), size: 12)
        hudBorderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([hudBorderLabel.widthAnchor.constraint(equalToConstant: 28)])
        hudBorderRow.addArrangedSubview(hudBorderLabel)
        osdRows.addArrangedSubview(makeRow(hudBorderRow))

        // Progress bar fill
        let progressRow = NSStackView()
        progressRow.spacing = 8
        progressRow.alignment = .centerY
        progressRow.distribution = .fill
        progressRow.addArrangedSubview(rowLabel("Progress Bar"))
        progressColorWell = colorWell(hex: AppSettings.progressColor.isEmpty ? "0.28/0.53/1.0/1.0" : AppSettings.progressColor)
        progressColorWell.target = self
        progressColorWell.action = #selector(progressColorChanged)
        progressColorWell.isEnabled = !AppSettings.progressColor.isEmpty
        progressRow.addArrangedSubview(progressColorWell)
        progressSystemCheck = NSButton(checkboxWithTitle: "Automatic", target: self, action: #selector(progressSystemToggled))
        progressSystemCheck.state = AppSettings.progressColor.isEmpty ? .on : .off
        progressRow.addArrangedSubview(progressSystemCheck)
        progressRow.addArrangedSubview(flexSpacer())
        osdRows.addArrangedSubview(makeRow(progressRow))

        // Box titles can't breathe (AppKit draws them tight to the border),
        // so the boxes go untitled and plain labels own the spacing.
        stack.addArrangedSubview(makeLabel("On-Screen Display", size: 13, weight: .semibold))
        let osdBox = NSBox()
        osdBox.titlePosition = .noTitle
        osdBox.boxType = .primary
        osdBox.contentViewMargins = NSSize(width: 8, height: 6)
        osdBox.contentView = osdRows
        stack.addArrangedSubview(osdBox)

        // Subtitles section
        // Sub font
        let subRow = makeFontRow(fonts: fonts, selected: AppSettings.subFontName)
        subFontPopup = subRow.popup
        subSystemCheck = subRow.check
        subFontPopup.target = self
        subFontPopup.action = #selector(subFontChanged)
        subSystemCheck.target = self
        subSystemCheck.action = #selector(subSystemToggled)
        subRows.addArrangedSubview(makeRow(subRow.stack))

        subBoldCheck = makeStyleCheck("Bold", #selector(subBoldToggled), AppSettings.subBold)
        subItalicCheck = makeStyleCheck("Italic", #selector(subItalicToggled), AppSettings.subItalic)
        subRows.addArrangedSubview(makeStyleRow(subSystemCheck, subBoldCheck, subItalicCheck))

        // Sub size
        let sizeRow = NSStackView()
        sizeRow.spacing = 8
        sizeRow.alignment = .centerY
        sizeRow.distribution = .fill
        sizeRow.addArrangedSubview(rowLabel("Size"))
        subSizeSlider = NSSlider(value: AppSettings.subFontSize, minValue: 16, maxValue: 90,
                                  target: self, action: #selector(subSizeChanged))
        flexSlider(subSizeSlider)
        sizeRow.addArrangedSubview(subSizeSlider)
        subSizeLabel = makeLabel(String(Int(AppSettings.subFontSize)), size: 12)
        subSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subSizeLabel.widthAnchor.constraint(equalToConstant: 28)])
        sizeRow.addArrangedSubview(subSizeLabel)
        subRows.addArrangedSubview(makeRow(sizeRow))

        // Colors
        let colorRow = NSStackView()
        colorRow.spacing = 8
        colorRow.alignment = .centerY
        colorRow.distribution = .fill
        colorRow.addArrangedSubview(rowLabel("Color"))
        colorRow.addArrangedSubview(makeLabel("Text", size: 12, color: .secondaryLabelColor))
        subColorWell = colorWell(hex: AppSettings.subColor)
        subColorWell.target = self
        subColorWell.action = #selector(subColorChanged)
        colorRow.addArrangedSubview(subColorWell)
        colorRow.addArrangedSubview(makeLabel("Outline", size: 12, color: .secondaryLabelColor))
        subBorderColorWell = colorWell(hex: AppSettings.subBorderColor)
        subBorderColorWell.target = self
        subBorderColorWell.action = #selector(subBorderColorChanged)
        colorRow.addArrangedSubview(subBorderColorWell)
        colorRow.addArrangedSubview(flexSpacer())
        subRows.addArrangedSubview(makeRow(colorRow))

        // Outline size
        let borderRow = NSStackView()
        borderRow.spacing = 8
        borderRow.alignment = .centerY
        borderRow.distribution = .fill
        borderRow.addArrangedSubview(rowLabel("Outline"))
        subBorderSlider = NSSlider(value: AppSettings.subBorderSize, minValue: 0, maxValue: 10,
                                    target: self, action: #selector(subBorderChanged))
        flexSlider(subBorderSlider)
        borderRow.addArrangedSubview(subBorderSlider)
        subBorderLabel = makeLabel(String(Int(AppSettings.subBorderSize)), size: 12)
        subBorderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subBorderLabel.widthAnchor.constraint(equalToConstant: 28)])
        borderRow.addArrangedSubview(subBorderLabel)
        subRows.addArrangedSubview(makeRow(borderRow))

        // Shadow
        let shadowRow = NSStackView()
        shadowRow.spacing = 8
        shadowRow.alignment = .centerY
        shadowRow.distribution = .fill
        shadowRow.addArrangedSubview(rowLabel("Shadow"))
        subShadowSlider = NSSlider(value: AppSettings.subShadowOffset, minValue: 0, maxValue: 10,
                                    target: self, action: #selector(subShadowChanged))
        flexSlider(subShadowSlider)
        shadowRow.addArrangedSubview(subShadowSlider)
        subShadowLabel = makeLabel(String(Int(AppSettings.subShadowOffset)), size: 12)
        subShadowLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subShadowLabel.widthAnchor.constraint(equalToConstant: 28)])
        shadowRow.addArrangedSubview(subShadowLabel)
        subRows.addArrangedSubview(makeRow(shadowRow))

        // Override ASS
        overrideCheck = NSButton(checkboxWithTitle: "Override styled subtitles", target: self, action: #selector(overrideChanged))
        overrideCheck.state = AppSettings.subOverrideASS ? .on : .off
        subRows.addArrangedSubview(makeRow(overrideWrap(overrideCheck)))

        stack.addArrangedSubview(makeLabel("Subtitles", size: 13, weight: .semibold))
        let subBox = NSBox()
        subBox.titlePosition = .noTitle
        subBox.boxType = .primary
        subBox.contentViewMargins = NSSize(width: 8, height: 6)
        subBox.contentView = subRows
        stack.addArrangedSubview(subBox)

        spacer(stack)

        // Reset + Done
        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.keyEquivalent = "\r"
        // Native sheets trailing-align actions (default button last).
        let bottomRow = NSStackView(views: [flexSpacer(), resetBtn, doneBtn])
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        stack.addArrangedSubview(makeRow(bottomRow))

        // Constraints
        // Rows hug content by default, leaving the column's right side
        // empty — pin the boxes (the only non-row views added directly)
        // to the column width minus the 20pt edge insets, and pin each
        // row wrapper inside the boxes to its box's rows stack, so
        // sliders and flex spacers absorb the slack instead. Done here,
        // once all anchors share the hierarchy.
        for case let row as NSStackView in stack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        }
        osdBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        subBox.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        for case let row as NSStackView in osdRows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: osdRows.widthAnchor).isActive = true
        }
        for case let row as NSStackView in subRows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: subRows.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.bottomAnchor.constraint(equalTo: scroll.contentView.bottomAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            NSColorPanel.shared.orderOut(nil)
        }
    }

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                           color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    // HIG form labels: right-aligned, sentence case, trailing colon —
    // the colon edge forms the column the controls hang off. 84pt fits
    // the widest label ("Progress Bar:"); sliders absorb the difference
    // so total width is unchanged.
    private func rowLabel(_ text: String) -> NSTextField {
        let l = makeLabel(text.hasSuffix(":") ? text : text + ":", size: 12, color: .secondaryLabelColor)
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 84).isActive = true
        return l
    }

    private func colGuard() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 84).isActive = true
        return v
    }

    private func overrideWrap(_ check: NSButton) -> NSStackView {
        check.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSStackView(views: [colGuard(), check, flexSpacer()])
        wrap.spacing = 8
        wrap.alignment = .centerY
        wrap.distribution = .fill
        return wrap
    }

    /// Trailing absorber for all-fixed rows under a fill parent: the lowest
    /// hugging priority wins the slack deterministically.
    private func flexSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    /// Sliders are the only stretchable view in their rows, so they absorb
    /// the slack deterministically (labels/wells/values carry fixed widths).
    private func flexSlider(_ slider: NSSlider) {
        slider.setContentHuggingPriority(.init(1), for: .horizontal)
    }

    private func makeStyleCheck(_ title: String, _ action: Selector, _ on: Bool) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: self, action: action)
        check.state = on ? .on : .off
        return check
    }

    // HIG checkbox groups get an introductory label aligned with the row.
    private func makeStyleRow(_ checks: NSButton...) -> NSStackView {
        let row = NSStackView(views: [rowLabel("Style")] + checks + [flexSpacer()])
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        return makeRow(row)
    }

    private func makeFontRow(fonts: [String], selected: String) -> (stack: NSStackView, popup: NSPopUpButton, check: NSButton) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: fonts)
        popup.font = .systemFont(ofSize: 12)
        if let idx = fonts.firstIndex(of: selected) { popup.selectItem(at: idx) }
        popup.isEnabled = !selected.isEmpty

        let check = NSButton(checkboxWithTitle: "System Font", target: nil, action: nil)
        check.state = selected.isEmpty ? .on : .off

        let row = NSStackView(views: [rowLabel("Font"), popup])
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        return (row, popup, check)
    }

    private func makeRow(_ view: NSView) -> NSStackView {
        let row = NSStackView(views: [view])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        return row
    }

    private func spacer(_ stack: NSStackView) {
        let s = NSView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(s)
    }

    private func colorWell(hex: String) -> NSColorWell {
        let well = PinnedColorWell()
        well.color = colorFromMPV(hex)
        well.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 36),
            well.heightAnchor.constraint(equalToConstant: 24),
        ])
        return well
    }

    private func colorFromMPV(_ str: String) -> NSColor {
        let parts = str.split(separator: "/").compactMap { Double($0) }
        guard parts.count >= 3 else { return .white }
        let r = CGFloat(parts[0]), g = CGFloat(parts[1]), b = CGFloat(parts[2])
        let a = parts.count >= 4 ? CGFloat(parts[3]) : 1.0
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }

    private func toMPV(_ color: NSColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let c = color.usingColorSpace(.deviceRGB) ?? color
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.2f/%.2f/%.2f/%.2f", r, g, b, a)
    }

    // MARK: - Actions

    @objc private func subFontChanged() {
        let name = subFontPopup.titleOfSelectedItem ?? "Helvetica"
        AppSettings.setSubFontName(name)
    }

    @objc private func subSizeChanged() {
        let val = subSizeSlider.doubleValue
        subSizeLabel.stringValue = String(Int(val))
        AppSettings.setSubFontSize(val)
    }

    @objc private func subColorChanged() {
        AppSettings.setSubColor(toMPV(subColorWell.color))
    }

    @objc private func subBorderColorChanged() {
        AppSettings.setSubBorderColor(toMPV(subBorderColorWell.color))
    }

    @objc private func subBorderChanged() {
        let val = subBorderSlider.doubleValue
        subBorderLabel.stringValue = String(Int(val))
        AppSettings.setSubBorderSize(val)
    }

    @objc private func subShadowChanged() {
        let val = subShadowSlider.doubleValue
        subShadowLabel.stringValue = String(Int(val))
        AppSettings.setSubShadowOffset(val)
    }

    @objc private func overrideChanged() {
        AppSettings.setSubOverrideASS(overrideCheck.state == .on)
    }

    @objc private func hudFontChanged() {
        AppSettings.setHudFontName(hudFontPopup.titleOfSelectedItem ?? "")
    }

    @objc private func hudSystemToggled() {
        let useSystem = hudSystemCheck.state == .on
        hudFontPopup.isEnabled = !useSystem
        AppSettings.setHudFontName(useSystem ? "" : (hudFontPopup.titleOfSelectedItem ?? ""))
    }

    @objc private func subSystemToggled() {
        let useSystem = subSystemCheck.state == .on
        subFontPopup.isEnabled = !useSystem
        AppSettings.setSubFontName(useSystem ? "" : (subFontPopup.titleOfSelectedItem ?? ""))
    }

    @objc private func hudBoldToggled() {
        AppSettings.setHudBold(hudBoldCheck.state == .on)
    }

    @objc private func hudBorderChanged() {
        let val = hudBorderSlider.doubleValue
        hudBorderLabel.stringValue = String(Int(val))
        AppSettings.setHudBorderSize(val)
    }

    @objc private func hudItalicToggled() {
        AppSettings.setHudItalic(hudItalicCheck.state == .on)
    }

    @objc private func progressColorChanged() {
        AppSettings.setProgressColor(toMPV(progressColorWell.color))
    }

    @objc private func progressSystemToggled() {
        let useSystem = progressSystemCheck.state == .on
        progressColorWell.isEnabled = !useSystem
        AppSettings.setProgressColor(useSystem ? "" : toMPV(progressColorWell.color))
    }

    @objc private func subBoldToggled() {
        AppSettings.setSubBold(subBoldCheck.state == .on)
    }

    @objc private func subItalicToggled() {
        AppSettings.setSubItalic(subItalicCheck.state == .on)
    }

    @objc private func resetTapped() {
        AppSettings.resetAll()
        refreshControls()
    }

    @objc private func doneTapped() {
        onDone?()
    }

    private func refreshControls() {
        let fonts = NSFontManager.shared.availableFontFamilies.sorted()

        // Title
        let useSystem = AppSettings.hudFontName.isEmpty
        hudSystemCheck.state = useSystem ? .on : .off
        hudFontPopup.isEnabled = !useSystem
        if let idx = fonts.firstIndex(of: AppSettings.hudFontName) { hudFontPopup.selectItem(at: idx) }
        hudBoldCheck.state = AppSettings.hudBold ? .on : .off
        hudItalicCheck.state = AppSettings.hudItalic ? .on : .off
        hudBorderSlider.doubleValue = AppSettings.hudBorderSize
        hudBorderLabel.stringValue = String(Int(AppSettings.hudBorderSize))
        progressSystemCheck.state = AppSettings.progressColor.isEmpty ? .on : .off
        progressColorWell.isEnabled = !AppSettings.progressColor.isEmpty
        if !AppSettings.progressColor.isEmpty {
            progressColorWell.color = colorFromMPV(AppSettings.progressColor)
        }

        // Sub
        let subSystem = AppSettings.subFontName.isEmpty
        subSystemCheck.state = subSystem ? .on : .off
        subFontPopup.isEnabled = !subSystem
        if let idx = fonts.firstIndex(of: AppSettings.subFontName) { subFontPopup.selectItem(at: idx) }
        subBoldCheck.state = AppSettings.subBold ? .on : .off
        subItalicCheck.state = AppSettings.subItalic ? .on : .off
        subSizeSlider.doubleValue = AppSettings.subFontSize
        subSizeLabel.stringValue = String(Int(AppSettings.subFontSize))
        subColorWell.color = colorFromMPV(AppSettings.subColor)
        subBorderColorWell.color = colorFromMPV(AppSettings.subBorderColor)
        subBorderSlider.doubleValue = AppSettings.subBorderSize
        subBorderLabel.stringValue = String(Int(AppSettings.subBorderSize))
        subShadowSlider.doubleValue = AppSettings.subShadowOffset
        subShadowLabel.stringValue = String(Int(AppSettings.subShadowOffset))
        overrideCheck.state = AppSettings.subOverrideASS ? .on : .off
    }
}

// ponytail: no anchor API for shared NSColorPanel, so pin manually; clamp if off-screen issues appear
private final class PinnedColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        guard let win = window else { return }
        let r = win.convertToScreen(convert(bounds, to: nil))
        DispatchQueue.main.async {
            NSColorPanel.shared.setFrameOrigin(NSPoint(x: r.maxX + 8, y: r.maxY - NSColorPanel.shared.frame.height))
        }
    }
}