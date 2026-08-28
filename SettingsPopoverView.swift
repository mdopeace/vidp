import AppKit

final class SettingsPopoverView: NSView {
    var onDone: (() -> Void)?

    private var hudFontPopup: NSPopUpButton!
    private var hudSystemCheck: NSButton!
    private var hudBoldCheck: NSButton!
    private var hudItalicCheck: NSButton!
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

    private static let accent = NSColor.systemBlue

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.state = .active
        blur.blendingMode = .withinWindow
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

        // Header
        let header = makeLabel("Settings", size: 22, weight: .bold, color: .white)
        stack.addArrangedSubview(header)
        spacer(stack)

        // Title section
        stack.addArrangedSubview(makeLabel("Title", size: 13, weight: .semibold, color: .white))
        let hudRow = makeFontRow(fonts: fonts, selected: AppSettings.hudFontName)
        hudFontPopup = hudRow.popup
        hudSystemCheck = hudRow.check
        hudFontPopup.target = self
        hudFontPopup.action = #selector(hudFontChanged)
        hudSystemCheck.target = self
        hudSystemCheck.action = #selector(hudSystemToggled)
        stack.addArrangedSubview(makeRow(hudRow.stack))

        hudBoldCheck = makeStyleCheck("Bold", #selector(hudBoldToggled), AppSettings.hudBold)
        hudItalicCheck = makeStyleCheck("Italic", #selector(hudItalicToggled), AppSettings.hudItalic)
        stack.addArrangedSubview(makeStyleRow(hudBoldCheck, hudItalicCheck))

        spacer(stack)

        // Subtitles section
        stack.addArrangedSubview(makeLabel("Subtitles", size: 13, weight: .semibold, color: .white))

        // Sub font
        let subRow = makeFontRow(fonts: fonts, selected: AppSettings.subFontName)
        subFontPopup = subRow.popup
        subSystemCheck = subRow.check
        subFontPopup.target = self
        subFontPopup.action = #selector(subFontChanged)
        subSystemCheck.target = self
        subSystemCheck.action = #selector(subSystemToggled)
        stack.addArrangedSubview(makeRow(subRow.stack))

        subBoldCheck = makeStyleCheck("Bold", #selector(subBoldToggled), AppSettings.subBold)
        subItalicCheck = makeStyleCheck("Italic", #selector(subItalicToggled), AppSettings.subItalic)
        stack.addArrangedSubview(makeStyleRow(subBoldCheck, subItalicCheck))

        // Sub size
        let sizeRow = NSStackView()
        sizeRow.spacing = 8
        sizeRow.alignment = .centerY
        sizeRow.addArrangedSubview(rowLabel("Size"))
        subSizeSlider = NSSlider(value: AppSettings.subFontSize, minValue: 16, maxValue: 90,
                                  target: self, action: #selector(subSizeChanged))
        subSizeSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        sizeRow.addArrangedSubview(subSizeSlider)
        subSizeLabel = makeLabel(String(Int(AppSettings.subFontSize)), size: 12, color: .white)
        subSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subSizeLabel.widthAnchor.constraint(equalToConstant: 28)])
        sizeRow.addArrangedSubview(subSizeLabel)
        stack.addArrangedSubview(makeRow(sizeRow))

        // Colors
        let colorRow = NSStackView()
        colorRow.spacing = 16
        colorRow.alignment = .centerY
        colorRow.addArrangedSubview(colGuard())
        colorRow.addArrangedSubview(makeLabel("Text", size: 12, color: NSColor(white: 1, alpha: 0.6)))
        subColorWell = colorWell(hex: AppSettings.subColor)
        subColorWell.target = self
        subColorWell.action = #selector(subColorChanged)
        colorRow.addArrangedSubview(subColorWell)
        colorRow.addArrangedSubview(makeLabel("Border", size: 12, color: NSColor(white: 1, alpha: 0.6)))
        subBorderColorWell = colorWell(hex: AppSettings.subBorderColor)
        subBorderColorWell.target = self
        subBorderColorWell.action = #selector(subBorderColorChanged)
        colorRow.addArrangedSubview(subBorderColorWell)
        stack.addArrangedSubview(makeRow(colorRow))

        // Border size
        let borderRow = NSStackView()
        borderRow.spacing = 8
        borderRow.alignment = .centerY
        borderRow.addArrangedSubview(rowLabel("Border"))
        subBorderSlider = NSSlider(value: AppSettings.subBorderSize, minValue: 0, maxValue: 10,
                                   target: self, action: #selector(subBorderChanged))
        subBorderSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        borderRow.addArrangedSubview(subBorderSlider)
        subBorderLabel = makeLabel(String(Int(AppSettings.subBorderSize)), size: 12, color: .white)
        subBorderLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subBorderLabel.widthAnchor.constraint(equalToConstant: 28)])
        borderRow.addArrangedSubview(subBorderLabel)
        stack.addArrangedSubview(makeRow(borderRow))

        // Shadow
        let shadowRow = NSStackView()
        shadowRow.spacing = 8
        shadowRow.alignment = .centerY
        shadowRow.addArrangedSubview(rowLabel("Shadow"))
        subShadowSlider = NSSlider(value: AppSettings.subShadowOffset, minValue: 0, maxValue: 10,
                                   target: self, action: #selector(subShadowChanged))
        subShadowSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        shadowRow.addArrangedSubview(subShadowSlider)
        subShadowLabel = makeLabel(String(Int(AppSettings.subShadowOffset)), size: 12, color: .white)
        subShadowLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([subShadowLabel.widthAnchor.constraint(equalToConstant: 28)])
        shadowRow.addArrangedSubview(subShadowLabel)
        stack.addArrangedSubview(makeRow(shadowRow))

        // Override ASS
        overrideCheck = NSButton(checkboxWithTitle: "Override ASS styles", target: self, action: #selector(overrideChanged))
        overrideCheck.state = AppSettings.subOverrideASS ? .on : .off
        overrideCheck.contentTintColor = .white
        stack.addArrangedSubview(makeRow(overrideWrap(overrideCheck)))

        spacer(stack)

        // Reset + Done
        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        resetBtn.contentTintColor = NSColor(white: 0.7, alpha: 1)
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.keyEquivalent = "\r"
        let bottomRow = NSStackView(views: [colGuard(), resetBtn, doneBtn])
        bottomRow.spacing = 8
        stack.addArrangedSubview(makeRow(bottomRow))

        // Constraints
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

    // MARK: - Helpers

    private func makeLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                           color: NSColor = .white) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }

    private func rowLabel(_ text: String) -> NSTextField {
        let l = makeLabel(text, size: 12, color: NSColor(white: 1, alpha: 0.6))
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return l
    }

    private func colGuard() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 56).isActive = true
        return v
    }

    private func overrideWrap(_ check: NSButton) -> NSStackView {
        check.translatesAutoresizingMaskIntoConstraints = false
        let wrap = NSStackView(views: [colGuard(), check])
        wrap.spacing = 8
        wrap.alignment = .centerY
        return wrap
    }

    private func makeStyleCheck(_ title: String, _ action: Selector, _ on: Bool) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: self, action: action)
        check.state = on ? .on : .off
        check.contentTintColor = NSColor(white: 0.8, alpha: 1)
        return check
    }

    private func makeStyleRow(_ bold: NSButton, _ italic: NSButton) -> NSStackView {
        let row = NSStackView(views: [colGuard(), bold, italic])
        row.spacing = 8
        row.alignment = .centerY
        return makeRow(row)
    }

    private func makeFontRow(fonts: [String], selected: String) -> (stack: NSStackView, popup: NSPopUpButton, check: NSButton) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: fonts)
        popup.font = .systemFont(ofSize: 12)
        if let idx = fonts.firstIndex(of: selected) { popup.selectItem(at: idx) }
        popup.isEnabled = !selected.isEmpty
        let wrap = wrapInBox(popup)
        wrap.widthAnchor.constraint(equalToConstant: 180).isActive = true

        let check = NSButton(checkboxWithTitle: "System", target: nil, action: nil)
        check.state = selected.isEmpty ? .on : .off
        check.contentTintColor = NSColor(white: 0.8, alpha: 1)

        let row = NSStackView(views: [rowLabel("Font"), wrap, check])
        row.spacing = 8
        row.alignment = .centerY
        return (row, popup, check)
    }

    private func wrapInBox(_ view: NSView) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor(white: 0.25, alpha: 1).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            view.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -8),
            view.topAnchor.constraint(equalTo: box.topAnchor, constant: 4),
            view.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -4),
            box.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
        return box
    }

    private func makeRow(_ view: NSView) -> NSStackView {
        let row = NSStackView(views: [view])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func spacer(_ stack: NSStackView) {
        let s = NSView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.heightAnchor.constraint(equalToConstant: 4).isActive = true
        stack.addArrangedSubview(s)
    }

    private func colorWell(hex: String) -> NSColorWell {
        let well = NSColorWell()
        well.color = colorFromMPV(hex)
        well.isBordered = false
        well.wantsLayer = true
        well.layer?.cornerRadius = 4
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
        applySubtitle()
    }

    @objc private func subSizeChanged() {
        let val = subSizeSlider.doubleValue
        subSizeLabel.stringValue = String(Int(val))
        AppSettings.setSubFontSize(val)
        applySubtitle()
    }

    @objc private func subColorChanged() {
        AppSettings.setSubColor(toMPV(subColorWell.color))
        applySubtitle()
    }

    @objc private func subBorderColorChanged() {
        AppSettings.setSubBorderColor(toMPV(subBorderColorWell.color))
        applySubtitle()
    }

    @objc private func subBorderChanged() {
        let val = subBorderSlider.doubleValue
        subBorderLabel.stringValue = String(Int(val))
        AppSettings.setSubBorderSize(val)
        applySubtitle()
    }

    @objc private func subShadowChanged() {
        let val = subShadowSlider.doubleValue
        subShadowLabel.stringValue = String(Int(val))
        AppSettings.setSubShadowOffset(val)
        applySubtitle()
    }

    @objc private func overrideChanged() {
        AppSettings.setSubOverrideASS(overrideCheck.state == .on)
        applySubtitle()
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
        applySubtitle()
    }

    @objc private func hudBoldToggled() {
        AppSettings.setHudBold(hudBoldCheck.state == .on)
    }

    @objc private func hudItalicToggled() {
        AppSettings.setHudItalic(hudItalicCheck.state == .on)
    }

    @objc private func subBoldToggled() {
        AppSettings.setSubBold(subBoldCheck.state == .on)
        applySubtitle()
    }

    @objc private func subItalicToggled() {
        AppSettings.setSubItalic(subItalicCheck.state == .on)
        applySubtitle()
    }

    @objc private func resetTapped() {
        AppSettings.resetAll()
        refreshControls()
        applySubtitle()
    }

    @objc private func doneTapped() {
        onDone?()
    }

    private func applySubtitle() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.applySubtitleSettings()
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

        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }
}