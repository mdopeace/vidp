import AVFoundation
import AVKit
import Combine
import SwiftUI

// MARK: - Pure helpers (unit-tested)

enum TimeFormatting {
    /// 5 → "0:05", 61 → "1:01", 3661 → "1:01:01". Negative values keep sign
    /// (used for remaining-time labels).
    static func clock(_ t: Double) -> String {
        let total = Int(abs(t.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return t < 0 ? "-" + core(h, m, s) : core(h, m, s)
    }
    private static func core(_ h: Int, _ m: Int, _ s: Int) -> String {
        h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
              : String(format: "%d:%02d", m, s)
    }
}

/// Chrome stays visible while paused; while playing it hides after idle delay.
enum ChromePolicy {
    static let idleHideDelay: TimeInterval = 3
    static func shouldAutoHide(
        now: TimeInterval, lastActivity: TimeInterval, isPlaying: Bool
    ) -> Bool {
        guard isPlaying else { return false }
        return now - lastActivity >= idleHideDelay
    }
}

func clampSeek(current: Double, delta: Double, duration: Double) -> Double {
    guard duration > 0 else { return current }
    return min(max(current + delta, 0), duration)
}

/// Builds subtitle/audio picker entries from localized display names,
/// de-duplicating repeats ("English" → "English 2") and marking selection.
/// `id` = source index so selection maps back exactly.
func trackOptions(named names: [String], selectedName: String?) -> [TrackOption] {
    var counts: [String: Int] = [:]
    return names.enumerated().map { idx, raw in
        let n = counts[raw, default: 0] + 1
        counts[raw] = n
        let name = n == 1 ? raw : "\(raw) \(n)"
        return TrackOption(id: idx, name: name, isSelected: name == selectedName)
    }
}

struct TrackOption: Identifiable, Equatable {
    let id: Int
    let name: String
    let isSelected: Bool
}

// MARK: - Controller

@MainActor
final class PlaybackController: ObservableObject {
    @Published var player: AVPlayer? { didSet { layer.player = player } }
    @Published var title = "VidP"
    @Published var year: String?
    @Published var preparing = false
    @Published var errorMessage: String?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying = false
    @Published var volume: Double = 1 { didSet { player?.volume = Float(volume) } }
    @Published var chromeVisible = true
    @Published var subtitleOptions: [TrackOption] = []
    @Published var audioOptions: [TrackOption] = []
    @Published var flashGlyph = false

    let layer = AVPlayerLayer()
    private(set) var pipController: AVPictureInPictureController?

    private let resume = ResumeStore()
    private let remuxService = RemuxService()
    private var currentURL: URL?
    private var currentRemuxOutput: URL?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastActivity = Date.timeIntervalSinceReferenceDate
    private var savedSecondMark = -1
    private var subtitleGroup: AVMediaSelectionGroup?
    private var audioGroup: AVMediaSelectionGroup?

    init() {
        layer.videoGravity = .resizeAspect
        layer.backgroundColor = CGColor.black
    }

    // MARK: - Open

    func open(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let (video, sidecars) = PlaybackRouter.partition(urls)
        guard let video else {
            errorMessage = "No playable video in selection."
            return
        }
        teardown()
        currentURL = video
        title = video.lastPathComponentWithoutExtension
        year = Self.creationYear(of: video)

        switch PlaybackRouter.kind(of: video) {
        case .direct:
            finishOpen(AVPlayerItem(url: video))
        case .remux:
            beginPreparingIndicator()
            Task { [weak self] in
                do {
                    guard let self else { return }
                    let output = try await self.remuxService.remux(
                        video: video, sidecars: sidecars)
                    self.preparing = false
                    self.currentRemuxOutput = output
                    self.finishOpen(AVPlayerItem(url: output))
                } catch {
                    guard let self else { return }
                    self.preparing = false
                    self.errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private func finishOpen(_ item: AVPlayerItem) {
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.volume = Float(volume)
        player = newPlayer
        currentTime = 0
        duration = 0
        savedSecondMark = -1
        noteActivity()

        if let url = currentURL,
            let entry = resume.entry(for: url),
            ResumeStore.shouldResume(entry)
        {
            newPlayer.seek(
                to: CMTime(seconds: entry.position, preferredTimescale: 600),
                toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = entry.position
        }

        pipController = AVPictureInPictureController(playerLayer: layer)
        addObservers(item)
        loadTrackOptions(item)
        newPlayer.play()
    }

    // MARK: - Transport

    func togglePlay() {
        guard let player else { return }
        noteActivity()
        flashGlyph.toggle()
        player.timeControlStatus == .playing ? player.pause() : player.play()
    }

    func seek(by delta: Double) {
        guard let player, duration > 0 else { return }
        let target = clampSeek(
            current: currentTime, delta: delta, duration: duration)
        currentTime = target
        noteActivity()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.05, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.05, preferredTimescale: 600))
    }

    func scrub(to target: Double) {
        guard let player else { return }
        currentTime = target
        noteActivity()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePiP() {
        guard let pip = pipController, pip.isPictureInPicturePossible else { return }
        if pip.isPictureInPictureActive { pip.stopPictureInPicture() } else { pip.startPictureInPicture() }
    }

    // MARK: - Chrome state

    func noteActivity() {
        lastActivity = Date.timeIntervalSinceReferenceDate
        if !chromeVisible {
            chromeVisible = true
        }
    }

    private func evaluateAutoHide(now: TimeInterval) {
        if chromeVisible,
            ChromePolicy.shouldAutoHide(
                now: now, lastActivity: lastActivity, isPlaying: isPlaying)
        {
            chromeVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
        if !chromeVisible, !isPlaying {
            chromeVisible = true  // paused → always show controls
        }
    }

    // MARK: - Observers

    private func addObservers(_ item: AVPlayerItem) {
        guard let player, let url = currentURL else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 1),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = max(time.seconds, 0)
                self.isPlaying = self.player?.timeControlStatus == .playing
                let now = Date.timeIntervalSinceReferenceDate
                self.evaluateAutoHide(now: now)
                let mark = Int(self.currentTime / 10)
                if mark != self.savedSecondMark, self.isPlaying {
                    self.savedSecondMark = mark
                    self.savePosition()
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.resume.clear(for: url)
                self?.chromeVisible = true
            }
        }

        Task {
            if let d = try? await item.asset.load(.duration).seconds, d.isFinite {
                duration = d
            }
        }
    }

    private func savePosition() {
        guard let url = currentURL, duration > 0 else { return }
        resume.save(position: currentTime, duration: duration, for: url)
    }

    // MARK: - Track pickers

    private func loadTrackOptions(_ item: AVPlayerItem) {
        Task { [weak self] in
            let asset = item.asset
            guard let characteristics = try? await asset.load(
                .availableMediaCharacteristicsWithMediaSelectionOptions)
            else { return }
            for characteristic in characteristics {
                guard let group = try? await asset.loadMediaSelectionGroup(
                    for: characteristic) else { continue }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if characteristic == AVMediaCharacteristic.legible {
                        self.subtitleGroup = group
                        self.subtitleOptions = trackOptions(
                            named: group.options.map(\.displayName),
                            selectedName: self.selectedName(item, group))
                    } else if characteristic == AVMediaCharacteristic.audible {
                        self.audioGroup = group
                        self.audioOptions = trackOptions(
                            named: group.options.map(\.displayName),
                            selectedName: self.selectedName(item, group))
                    }
                }
            }
        }
    }

    private func selectedName(_ item: AVPlayerItem, _ group: AVMediaSelectionGroup) -> String? {
        item.currentMediaSelection.selectedMediaOption(in: group)?.displayName
    }

    func selectSubtitle(_ option: TrackOption) {
        applySelection(option, group: &subtitleGroup, options: \.subtitleOptions)
    }

    func selectAudio(_ option: TrackOption) {
        applySelection(option, group: &audioGroup, options: \.audioOptions)
    }

    private func applySelection(
        _ option: TrackOption,
        group: inout AVMediaSelectionGroup?,
        options: ReferenceWritableKeyPath<PlaybackController, [TrackOption]>
    ) {
        guard let playerItem = player?.currentItem, let g = group,
              (0..<g.options.count).contains(option.id) else { return }
        // "Off" is represented by selecting nil.
        let target = option.name == "Off" ? nil : g.options[option.id]
        playerItem.select(target, in: g)
        self[keyPath: options] = trackOptions(
            named: g.options.map(\.displayName),
            selectedName: target?.displayName)
    }

    // MARK: - Teardown

    func teardown() {
        preparingTask?.cancel()
        preparing = false

        savePosition()

        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil

        player?.pause()
        player = nil
        pipController = nil
        subtitleOptions = []
        audioOptions = []
        subtitleGroup = nil
        audioGroup = nil
        isPlaying = false
        chromeVisible = true

        if let output = currentRemuxOutput {
            try? FileManager.default.removeItem(at: output)
            currentRemuxOutput = nil
        }
        currentURL = nil
        duration = 0
        currentTime = 0
    }

    static func cleanup() {
        RemuxService.purgeTempFiles()
    }

    // MARK: - Preparing indicator (>300 ms only)

    private var preparingTask: Task<Void, Never>?

    private func beginPreparingIndicator() {
        preparingTask?.cancel()
        preparing = false
        preparingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            if !Task.isCancelled { self?.preparing = true }
        }
    }

    // MARK: - Misc

    private static func creationYear(of url: URL) -> String? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attrs?[.creationDate] as? Date else { return nil }
        let comps = Calendar.current.dateComponents([.year], from: date)
        return comps.year.map(String.init)
    }

    /// Installs the global playback key handler (space / arrows / JKL).
    func installKeyboardMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
            switch event.keyCode {
            case 49 where chars == " ":  // space
                self.togglePlay(); return nil
            case 123:  // left arrow
                self.seek(by: -10); return nil
            case 124:  // right arrow
                self.seek(by: 10); return nil
            case _ where chars == "j":
                let r = self.player?.rate ?? 0
                self.player?.rate = r < 0 ? max(r * 2, -8) : -1
                return nil
            case _ where chars == "k":
                self.player?.pause(); return nil
            case _ where chars == "l":
                let r = self.player?.rate ?? 0
                self.player?.rate = r <= 0 ? 1 : min(r * 2, 8)
                return nil
            default:
                return event
            }
        }
    }
}

extension URL {
    var lastPathComponentWithoutExtension: String {
        deletingPathExtension().lastPathComponent
    }
}
