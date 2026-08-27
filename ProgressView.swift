import AppKit

// MARK: - Apple TV-style Progress View

final class ProgressView: NSView {
    var value: Double = 0 { didSet { needsDisplay = true } }
    var onScrub: ((Double) -> Void)?
    private var isHovering = false
    private var isDragging = false

    private let trackHeight: CGFloat = 6
    private let thumbDiameter: CGFloat = 14

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 18)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        for area in trackingAreas where area.owner === self {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }

    override var acceptsFirstResponder: Bool { false }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        scrub(to: event)
    }

    override func mouseDragged(with event: NSEvent) {
        scrub(to: event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
    }

    private func scrub(to event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ratio = max(0, min(1, point.x / bounds.width))
        value = ratio
        onScrub?(ratio)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let barY = (bounds.height - trackHeight) / 2
        let barRect = NSRect(x: 0, y: barY, width: bounds.width, height: trackHeight)

        // Track background
        NSColor(white: 1, alpha: 0.2).setFill()
        let bgPath = NSBezierPath(roundedRect: barRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        bgPath.fill()

        // Progress fill
        let fillRect = NSRect(x: 0, y: barY, width: bounds.width * value, height: trackHeight)
        NSColor.white.setFill()
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2)
        fillPath.fill()

        // Thumb — capsule, always visible
        let thumbW: CGFloat = 20
        let thumbH: CGFloat = 14
        let thumbX = bounds.width * value
        let thumbRect = NSRect(
            x: thumbX - thumbW / 2,
            y: (bounds.height - thumbH) / 2,
            width: thumbW, height: thumbH)
        NSColor.white.setFill()
        let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: thumbH / 2, yRadius: thumbH / 2)
        thumbPath.fill()
    }
}
