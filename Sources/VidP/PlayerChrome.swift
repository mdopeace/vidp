import AVKit
import SwiftUI

// MARK: - Metrics (measured from the macOS TV app player)

enum TVMetrics {
    static let pauseCircle: CGFloat = 64
    static let skipCircle: CGFloat = 43
    static let smallCircle: CGFloat = 27
    static let pillHeight: CGFloat = 22
    static let margin: CGFloat = 28
    static let centerGap: CGFloat = 13
    static let scrubberBottomInset: CGFloat = 24
}

// MARK: - Glass helper (native Liquid Glass on macOS 26+, material fallback)

extension View {
    @ViewBuilder
    func tvGlass<C: Shape>(in shape: C, interactive: Bool = true) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }
}

// MARK: - Overlay

/// The full TV-app-style control overlay, faded by chrome visibility.
struct PlayerOverlayView: View {
    @ObservedObject var controller: PlaybackController

    var body: some View {
        ZStack {
            centerCluster
            topRow
            bottomArea
            glyphFlash
        }
        .opacity(controller.chromeVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: controller.chromeVisible)
        .allowsHitTesting(controller.chromeVisible)
    }

    // MARK: center cluster

    private var centerCluster: some View {
        HStack(spacing: TVMetrics.centerGap) {
            circleButton(TVMetrics.skipCircle, "gobackward.10", scale: 0.5) {
                controller.seek(by: -10)
            }
            circleButton(TVMetrics.pauseCircle,
                         controller.isPlaying ? "pause.fill" : "play.fill",
                         scale: 0.45) {
                controller.togglePlay()
            }
            circleButton(TVMetrics.skipCircle, "goforward.10", scale: 0.5) {
                controller.seek(by: 10)
            }
        }
    }

    // MARK: top row

    private var topRow: some View {
        VStack {
            HStack(alignment: .top) {
                pipPill
                Spacer()
                volumePill
            }
            .padding(.top, TVMetrics.margin - 6)
            .padding(.horizontal, TVMetrics.margin)
            Spacer()
        }
    }

    private var pipPill: some View {
        HStack(spacing: 2) {
            pillButton("pip")
                .disabled(!(controller.pipController?.isPictureInPicturePossible ?? false))
        }
        .padding(4)
        .tvGlass(in: Capsule())
    }

    private var volumePill: some View {
        HStack(spacing: 8) {
            Slider(value: $controller.volume, in: 0...1)
                .frame(width: 60)
            Image(systemName: speakerSymbol)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 14)
        }
        .padding(.horizontal, 12)
        .frame(height: TVMetrics.pillHeight + 8)
        .tvGlass(in: Capsule())
    }

    private var speakerSymbol: String {
        switch controller.volume {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.4: return "speaker.wave.1.fill"
        case ..<0.75: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    // MARK: bottom area

    private var bottomArea: some View {
        VStack(spacing: 6) {
            Spacer()
            HStack(alignment: .bottom) {
                infoBlock
                Spacer()
                trackButtons
            }
            .padding(.horizontal, TVMetrics.margin)
            ScrubberView(
                currentTime: controller.currentTime,
                duration: controller.duration,
                onScrub: { controller.scrub(to: $0) })
                .padding(.horizontal, TVMetrics.margin)
                .padding(.bottom, TVMetrics.scrubberBottomInset)
        }
    }

    private var infoBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let year = controller.year {
                Text(year)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(controller.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    private var trackButtons: some View {
        HStack(spacing: 3) {
            smallMenuButton(
                symbol: "captions.bubble",
                options: controller.subtitleOptions + [offOption],
                selection: { controller.selectSubtitle($0) })
            smallMenuButton(
                symbol: "speaker.wave.2",
                options: controller.audioOptions,
                selection: { controller.selectAudio($0) })
        }
    }

    private var offOption: TrackOption {
        TrackOption(id: -1, name: "Off", isSelected: false)
    }

    // MARK: pieces

    private func circleButton(
        _ diameter: CGFloat, _ symbol: String, scale: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * scale, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: diameter, height: diameter)
        }
        .buttonStyle(.plain)
        .tvGlass(in: Circle())
    }

    private func pillButton(_ symbol: String) -> some View {
        Button(action: { controller.togglePiP() }) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 30, height: TVMetrics.pillHeight)
        }
        .buttonStyle(.plain)
    }

    private func smallMenuButton(
        symbol: String,
        options: [TrackOption],
        selection: @escaping (TrackOption) -> Void
    ) -> some View {
        Menu {
            ForEach(options) { option in
                Button(option.name) { selection(option) }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: TVMetrics.smallCircle * 0.42, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: TVMetrics.smallCircle, height: TVMetrics.smallCircle)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(options.count < 2)
        .tvGlass(in: Circle())
    }

    // MARK: transient center glyph on play/pause toggle

    @State private var flashVisible = false

    private var glyphFlash: some View {
        Group {
            if flashVisible {
                Image(systemName: controller.isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 110, height: 110)
                    .background(Circle().fill(.black.opacity(0.35)))
                    .transition(.scale(scale: 1.25).combined(with: .opacity))
            }
        }
        .onChange(of: controller.flashGlyph) { _, _ in
            withAnimation(.easeOut(duration: 0.08)) { flashVisible = true }
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                withAnimation(.easeIn(duration: 0.25)) { flashVisible = false }
            }
        }
        .allowsHitTesting(false)
    }
}
