import AppKit

final class SettingsSidebarView: NSView {
    var onDone: (() -> Void)?

    private var hudFontPopup: NSPopUpButton!
    private var hudSystemCheck: NSButton!
    private var hudBoldCheck: NSButton!
    private var hudItalicCheck: NSButton!
    private var hudBorderInput: BoundedNumberInput!
    private var progressColorWell: NSColorWell!
    private var progressSystemCheck: NSButton!
    private var subFontPopup: NSPopUpButton!
    private var subSystemCheck: NSButton!
    private var subBoldCheck: NSButton!
    private var subItalicCheck: NSButton!
    private var subSizeInput: BoundedNumberInput!
    private var subColorWell: NSColorWell!
    private var subBorderColorWell: NSColorWell!
    private var subBorderInput: BoundedNumberInput!
    private var subShadowInput: BoundedNumberInput!
    private var overrideCheck: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        let background = NSVisualEffectView()
        background.material = .windowBackground
        background.state = .active
        background.blendingMode = .behindWindow
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let fonts = NSFontManager.shared.availableFontFamilies.sorted()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        // Each section owns a vertical stack.
        let osdRows = NSStackView()
        osdRows.orientation = .vertical
        osdRows.distribution = .fill
        osdRows.spacing = 8
        let subRows = NSStackView()
        subRows.orientation = .vertical
        subRows.distribution = .fill
        subRows.spacing = 8

        // Title section
        let hudRow = makeFontRow(fonts: fonts, selected: AppSettings.hudFontName)
        hudFontPopup = hudRow.popup
        hudSystemCheck = hudRow.check
        hudFontPopup.target = self
        hudFontPopup.action = #selector(hudFontChanged)
        hudSystemCheck.target = self
        hudSystemCheck.action = #selector(hudSystemToggled)
        osdRows.addArrangedSubview(hudRow.stack)

        hudBoldCheck = makeStyleCheck("Bold", #selector(hudBoldToggled), AppSettings.hudBold)
        hudItalicCheck = makeStyleCheck("Italic", #selector(hudItalicToggled), AppSettings.hudItalic)
        osdRows.addArrangedSubview(fillRow("Style", [hudSystemCheck!, hudBoldCheck!, hudItalicCheck!]))

        // Title outline (halo)
        let hudBorder = makeNumberRow(label: "Outline", value: AppSettings.hudBorderSize,
                                      range: 0...10) { AppSettings.setHudBorderSize($0) }
        hudBorderInput = hudBorder.input
        osdRows.addArrangedSubview(hudBorder.row)

        // Progress bar fill
        progressColorWell = colorWell(hex: AppSettings.progressColor.isEmpty ? "0.28/0.53/1.0/1.0" : AppSettings.progressColor)
        progressColorWell.target = self
        progressColorWell.action = #selector(progressColorChanged)
        progressColorWell.isEnabled = !AppSettings.progressColor.isEmpty
        progressSystemCheck = NSButton(checkboxWithTitle: "Automatic", target: self, action: #selector(progressSystemToggled))
        progressSystemCheck.state = AppSettings.progressColor.isEmpty ? .on : .off
        osdRows.addArrangedSubview(fillRow("Progress Bar", [progressColorWell, progressSystemCheck]))

        stack.addArrangedSubview(makeSectionHeading("On-Screen Display"))
        stack.addArrangedSubview(osdRows)
        stack.addArrangedSubview(makeSeparator())

        // Subtitles section
        // Sub font
        let subRow = makeFontRow(fonts: fonts, selected: AppSettings.subFontName)
        subFontPopup = subRow.popup
        subSystemCheck = subRow.check
        subFontPopup.target = self
        subFontPopup.action = #selector(subFontChanged)
        subSystemCheck.target = self
        subSystemCheck.action = #selector(subSystemToggled)
        subRows.addArrangedSubview(subRow.stack)

        subBoldCheck = makeStyleCheck("Bold", #selector(subBoldToggled), AppSettings.subBold)
        subItalicCheck = makeStyleCheck("Italic", #selector(subItalicToggled), AppSettings.subItalic)
        subRows.addArrangedSubview(fillRow("Style", [subSystemCheck!, subBoldCheck!, subItalicCheck!]))

        // Sub size
        let subSize = makeNumberRow(label: "Size", value: AppSettings.subFontSize,
                                    range: 16...90) { AppSettings.setSubFontSize($0) }
        subSizeInput = subSize.input
        subRows.addArrangedSubview(subSize.row)

        // Colors
        subColorWell = colorWell(hex: AppSettings.subColor)
        subColorWell.target = self
        subColorWell.action = #selector(subColorChanged)
        subBorderColorWell = colorWell(hex: AppSettings.subBorderColor)
        subBorderColorWell.target = self
        subBorderColorWell.action = #selector(subBorderColorChanged)
        subRows.addArrangedSubview(fillRow("Color", [
            makeLabel("Text", size: 12), subColorWell,
            makeLabel("Outline", size: 12), subBorderColorWell,
        ]))

        // Outline size
        let subBorder = makeNumberRow(label: "Outline", value: AppSettings.subBorderSize,
                                      range: 0...10) { AppSettings.setSubBorderSize($0) }
        subBorderInput = subBorder.input
        subRows.addArrangedSubview(subBorder.row)

        // Shadow
        let subShadow = makeNumberRow(label: "Shadow", value: AppSettings.subShadowOffset,
                                      range: 0...10) { AppSettings.setSubShadowOffset($0) }
        subShadowInput = subShadow.input
        subRows.addArrangedSubview(subShadow.row)

        // Override ASS
        overrideCheck = NSButton(checkboxWithTitle: "Override styled subtitles", target: self, action: #selector(overrideChanged))
        overrideCheck.state = AppSettings.subOverrideASS ? .on : .off
        subRows.addArrangedSubview(overrideWrap(overrideCheck))

        stack.addArrangedSubview(makeSectionHeading("Subtitles"))
        stack.addArrangedSubview(subRows)

        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(verticalFlexSpacer())

        // Reset + Done
        let resetBtn = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTapped))
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneTapped))
        doneBtn.keyEquivalent = "\r"
        // Trailing-align actions with Done as the default button.
        let bottomRow = NSStackView(views: [flexSpacer(), resetBtn, doneBtn])
        bottomRow.spacing = 8
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        stack.addArrangedSubview(bottomRow)

        // Let section and action rows fill the content width.
        for case let row as NSStackView in stack.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        for case let separator as NSBox in stack.arrangedSubviews {
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -24).isActive = true
        }
        for case let row as NSStackView in osdRows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: osdRows.widthAnchor).isActive = true
        }
        for case let row as NSStackView in subRows.arrangedSubviews {
            row.widthAnchor.constraint(equalTo: subRows.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
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

    private func makeSectionHeading(_ text: String) -> NSTextField {
        makeLabel(text, size: 13, weight: .semibold, color: .secondaryLabelColor)
    }

    private func rowLabel(_ text: String) -> NSTextField {
        let l = makeLabel(text, size: 12)
        l.alignment = .right
        l.translatesAutoresizingMaskIntoConstraints = false
        l.widthAnchor.constraint(equalToConstant: 70).isActive = true
        return l
    }

    /// HIG form row: right-aligned label, controls, trailing slack absorber.
    /// `spacer: false` lets the controls themselves stretch — the font popup is
    /// sized by its item titles, so it should fill the row.
    private func fillRow(_ label: String, _ views: [NSView], spacer: Bool = true) -> NSStackView {
        var rowViews = [rowLabel(label)] + views
        if spacer { rowViews.append(flexSpacer()) }
        let row = NSStackView(views: rowViews)
        row.spacing = 8
        row.alignment = .centerY
        row.distribution = .fill
        return row
    }

    private func makeNumberRow(label: String, value: Double, range: ClosedRange<Double>,
                               onChange: @escaping (Double) -> Void) -> (row: NSStackView, input: BoundedNumberInput) {
        let input = BoundedNumberInput(value: value, range: range)
        input.onChange = onChange
        return (fillRow(label, [input], spacer: false), input)
    }

    private func colGuard() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: 70).isActive = true
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
    /// hugging priority wins the slack.
    private func flexSpacer() -> NSView {
        let v = NSView()
        v.setContentHuggingPriority(.init(1), for: .horizontal)
        v.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        return v
    }

    private func makeStyleCheck(_ title: String, _ action: Selector, _ on: Bool) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: self, action: action)
        check.state = on ? .on : .off
        return check
    }

    private func makeFontRow(fonts: [String], selected: String) -> (stack: NSStackView, popup: NSPopUpButton, check: NSButton) {
        let popup = NSPopUpButton()
        popup.addItems(withTitles: fonts)
        popup.font = .systemFont(ofSize: 12)
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        popup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        if let idx = fonts.firstIndex(of: selected) { popup.selectItem(at: idx) }
        popup.isEnabled = !selected.isEmpty

        let check = NSButton(checkboxWithTitle: "System Font", target: nil, action: nil)
        check.state = selected.isEmpty ? .on : .off

        return (fillRow("Font", [popup], spacer: false), popup, check)
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func verticalFlexSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .vertical)
        spacer.setContentCompressionResistancePriority(.init(1), for: .vertical)
        return spacer
    }

    private func colorWell(hex: String) -> NSColorWell {
        let well = PinnedColorWell()
        well.color = AppSettings.color(fromMPV: hex) ?? .white
        well.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 36),
            well.heightAnchor.constraint(equalToConstant: 24),
        ])
        return well
    }

    private func toMPV(_ color: NSColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        let c = color.usingColorSpace(.deviceRGB) ?? color
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.2f/%.2f/%.2f/%.2f", r, g, b, a)
    }

    // MARK: - Actions

    @objc private func subFontChanged() {
        let name = subFontPopup.titleOfSelectedItem ?? ""
        AppSettings.setSubFontName(name)
    }

    @objc private func subColorChanged() {
        AppSettings.setSubColor(toMPV(subColorWell.color))
    }

    @objc private func subBorderColorChanged() {
        AppSettings.setSubBorderColor(toMPV(subBorderColorWell.color))
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
        hudBorderInput.setValue(AppSettings.hudBorderSize)
        progressSystemCheck.state = AppSettings.progressColor.isEmpty ? .on : .off
        progressColorWell.isEnabled = !AppSettings.progressColor.isEmpty
        if !AppSettings.progressColor.isEmpty {
            progressColorWell.color = AppSettings.color(fromMPV: AppSettings.progressColor) ?? .white
        }

        // Sub
        let subSystem = AppSettings.subFontName.isEmpty
        subSystemCheck.state = subSystem ? .on : .off
        subFontPopup.isEnabled = !subSystem
        if let idx = fonts.firstIndex(of: AppSettings.subFontName) { subFontPopup.selectItem(at: idx) }
        subBoldCheck.state = AppSettings.subBold ? .on : .off
        subItalicCheck.state = AppSettings.subItalic ? .on : .off
        subSizeInput.setValue(AppSettings.subFontSize)
        subColorWell.color = AppSettings.color(fromMPV: AppSettings.subColor) ?? .white
        subBorderColorWell.color = AppSettings.color(fromMPV: AppSettings.subBorderColor) ?? .white
        subBorderInput.setValue(AppSettings.subBorderSize)
        subShadowInput.setValue(AppSettings.subShadowOffset)
        overrideCheck.state = AppSettings.subOverrideASS ? .on : .off
    }
}

private final class BoundedNumberInput: NSStackView, NSTextFieldDelegate {
    var onChange: ((Double) -> Void)?

    private let range: ClosedRange<Double>
    private let field = NSTextField()
    private let stepper = NSStepper()
    private var currentValue: Double

    init(value: Double, range: ClosedRange<Double>) {
        self.range = range
        currentValue = min(max(value, range.lowerBound), range.upperBound)
        super.init(frame: .zero)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: range.lowerBound)
        formatter.maximum = NSNumber(value: range.upperBound)
        field.formatter = formatter
        field.alignment = .right
        field.font = .systemFont(ofSize: 12)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 44).isActive = true
        field.target = self
        field.action = #selector(fieldChanged)
        field.delegate = self

        stepper.minValue = range.lowerBound
        stepper.maxValue = range.upperBound
        stepper.increment = 1
        stepper.valueWraps = false
        stepper.target = self
        stepper.action = #selector(stepperChanged)

        let rangeLabel = NSTextField(labelWithString: "\(Int(range.lowerBound))–\(Int(range.upperBound))")
        rangeLabel.font = .systemFont(ofSize: 11)
        rangeLabel.textColor = .secondaryLabelColor
        rangeLabel.toolTip = "Allowed range"

        orientation = .horizontal
        alignment = .centerY
        spacing = 4
        addArrangedSubview(field)
        addArrangedSubview(stepper)
        addArrangedSubview(rangeLabel)
        setValue(value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ value: Double) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        currentValue = clamped
        field.doubleValue = clamped
        stepper.doubleValue = clamped
    }

    @objc private func fieldChanged() {
        updateValue(field.doubleValue)
    }

    @objc private func stepperChanged() {
        updateValue(stepper.doubleValue)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        fieldChanged()
    }

    private func updateValue(_ value: Double) {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let changed = currentValue != clamped
        setValue(clamped)
        if changed { onChange?(clamped) }
    }
}

// No anchor API for the shared NSColorPanel, so position it beside the color well.
private final class PinnedColorWell: NSColorWell {
    override func activate(_ exclusive: Bool) {
        super.activate(exclusive)
        guard let win = window, let visibleFrame = win.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let r = win.convertToScreen(convert(bounds, to: nil))
        DispatchQueue.main.async {
            let panel = NSColorPanel.shared
            let panelFrame = panel.frame
            let x = min(r.maxX + 8, visibleFrame.maxX - panelFrame.width)
            let y = min(max(r.maxY - panelFrame.height, visibleFrame.minY), visibleFrame.maxY - panelFrame.height)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}