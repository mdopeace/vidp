import SwiftUI

/// Full-width thin scrubber row: elapsed · bar+thumb · remaining (TV-app style).
/// Click-to-swap between elapsed and remaining display on the left label.
struct ScrubberView: View {
    let currentTime: Double
    let duration: Double
    let onScrub: (Double) -> Void

    @State private var dragging = false
    @State private var dragValue: Double = 0
    @State private var showRemainingOnLeft = false

    private var effectiveValue: Double { dragging ? dragValue : currentTime }

    var body: some View {
        HStack(spacing: 16) {
            Text(TimeFormatting.clock(showRemainingOnLeft && duration > 0
                ? effectiveValue - duration : effectiveValue))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let frac = duration > 0 ? min(max(effectiveValue / duration, 0), 1) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: 2)
                    Capsule()
                        .fill(.white)
                        .frame(width: max(w * frac, 0), height: 2)
                    Circle()
                        .fill(.white)
                        .frame(width: dragging || isHovering ? 11 : 9,
                               height: dragging || isHovering ? 11 : 9)
                        .shadow(radius: 1.5)
                        .offset(x: w * frac - (dragging || isHovering ? 5.5 : 4.5))
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            let f = min(max(g.location.x / w, 0), 1)
                            dragValue = f * duration
                            onScrub(dragValue)
                        }
                        .onEnded { _ in dragging = false }
                )
            }
            .frame(height: 20)

            Text("-" + TimeFormatting.clock(max(duration - effectiveValue, 0)))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.95))
        }
        .font(.system(size: 12))
    }

    @State private var isHovering = false
}
