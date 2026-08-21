import AVFoundation
import AppKit
import SwiftUI

/// NSView adopting the controller's AVPlayerLayer; handles clicks and
/// mouse-activity tracking for chrome show/hide.
final class PlayerLayerHostView: NSView {
    private let controller: PlaybackController

    init(layer: CALayer, controller: PlaybackController) {
        self.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        self.layer = layer
        addGestureRecognizer(NSClickGestureRecognizer(
            target: self, action: #selector(singleClick)))
        let dbl = NSClickGestureRecognizer(
            target: self, action: #selector(doubleClick))
        dbl.numberOfClicksRequired = 2
        addGestureRecognizer(dbl)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        controller.noteActivity()
    }

    override func mouseDragged(with event: NSEvent) {
        controller.noteActivity()
    }

    @objc private func singleClick() {
        controller.chromeVisible.toggle()
        controller.noteActivity()
    }

    @objc private func doubleClick() {
        window?.toggleFullScreen(nil)
    }
}

struct VideoView: NSViewRepresentable {
    let controller: PlaybackController

    func makeNSView(context: Context) -> PlayerLayerHostView {
        PlayerLayerHostView(layer: controller.layer, controller: controller)
    }

    func updateNSView(_ view: PlayerLayerHostView, context: Context) {}
}
