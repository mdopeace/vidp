import Foundation

// MARK: - Routing (pure, unit-tested)

enum VideoKind: Equatable {
    case direct
    case remux
}

enum PlaybackRouter {
    static let directExtensions: Set<String> = ["mp4", "mov", "m4v"]
    static let subtitleExtensions: Set<String> = ["srt", "vtt"]

    static func kind(of url: URL) -> VideoKind {
        directExtensions.contains(ext(url)) ? .direct : .remux
    }

    static func ext(_ url: URL) -> String {
        url.pathExtension.lowercased()
    }

    /// Splits an open-selection into the feature video and co-selected subtitle sidecars.
    static func partition(_ urls: [URL]) -> (video: URL?, sidecars: [URL]) {
        let video = urls.first { !subtitleExtensions.contains(ext($0)) }
        let subs = urls.filter { subtitleExtensions.contains(ext($0)) }
        return (video, subs)
    }
}

// MARK: - Remux

struct RemuxError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct RemuxService: Sendable {
    let ffmpegPath: @Sendable () -> URL?

    init(ffmpegPath: @escaping @Sendable () -> URL? = locateFFmpeg) {
        self.ffmpegPath = ffmpegPath
    }

    // MARK: argv builder (pure, unit-tested)

    /// Stream-copy remux to fMP4. Sidecar streams are mapped FIRST so their
    /// output subtitle indices (s:0…n) are known regardless of how many
    /// subtitle streams the source embeds — that lets us set exact track titles.
    static func makeArgs(
        video: URL, sidecars: [URL], output: URL, includeSubtitles: Bool
    ) -> [String] {
        var args = ["-y", "-i", video.path]
        for s in sidecars { args += ["-i", s.path] }

        if includeSubtitles {
            if !sidecars.isEmpty {
                for i in 1...sidecars.count {
                    args += ["-map", "\(i):0"]
                }
            }
            args += ["-map", "0:v?", "-map", "0:a?", "-map", "0:s?"]
        } else {
            args += ["-map", "0:v?", "-map", "0:a?"]
        }
        if includeSubtitles {
            for (idx, s) in sidecars.enumerated() {
                args += [
                    "-metadata:s:s:\(idx)",
                    "title=\(s.deletingPathExtension().lastPathComponent)",
                ]
            }
        }
        if includeSubtitles {
            args += ["-c:v", "copy", "-c:a", "copy", "-c:s", "mov_text"]
        } else {
            args += ["-c:v", "copy", "-c:a", "copy"]
        }
        args += ["-movflags", "+faststart", "-f", "mp4", output.path]
        return args
    }

    // MARK: cascade

    /// Remux with subtitles; on failure retry without them (PGS / exotic text
    /// codecs abort the whole mux). Throws after both attempts.
    func remux(video: URL, sidecars: [URL]) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("VidP-\(UUID().uuidString).mp4")
        do {
            return try await run(video: video, sidecars: sidecars, output: output, subs: true)
        } catch {
            return try await run(video: video, sidecars: [], output: output, subs: false)
        }
    }

    private func run(video: URL, sidecars: [URL], output: URL, subs: Bool) async throws -> URL {
        guard let ff = ffmpegPath() else {
            throw RemuxError(
                message: "ffmpeg helper not found. Run Scripts/fetch-ffmpeg.sh first.")
        }
        let args = Self.makeArgs(video: video, sidecars: sidecars, output: output, includeSubtitles: subs)
        try await Self.execute(ff, args)
        let attrs = try? FileManager.default.attributesOfItem(atPath: output.path)
        guard (attrs?[.size] as? Int64) ?? 0 > 0 else {
            throw RemuxError(message: "ffmpeg produced no output.")
        }
        return output
    }

    /// Runs ffmpeg, rejecting non-zero exits with a trimmed stderr tail for alerts.
    static func execute(_ executable: URL, _ arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments

            let stderrPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = Pipe()

            // ponytail: blocking readDataToEndOfFile on one detached thread —
            // fine for short-lived CLI runs; switch to async reads if stderr grows huge.
            try process.run()
            let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                let tail = String(data: stderr.suffix(2000), encoding: .utf8) ?? ""
                throw RemuxError(
                    message: """
                    ffmpeg exited with status \(process.terminationStatus).
                    \(tail.trimmingCharacters(in: .whitespacesAndNewlines))
                    """)
            }
        }.value
    }

    // MARK: helper location

    /// Search order: app bundle → FFMPEG_PATH env → repo Resources/ (dev runs).
    static func locateFFmpeg() -> URL? {
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil) {
            return bundled
        }
        if let env = ProcessInfo.processInfo.environment["FFMPEG_PATH"] {
            return URL(fileURLWithPath: env)
        }
        var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0...5 {
            let candidate = dir.appendingPathComponent("Resources/ffmpeg")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            dir.deleteLastPathComponent()
        }
        return nil
    }

    // MARK: temp hygiene

    /// Removes VidP-* remux artifacts from tmp (stale sweep + close/quit purge).
    static func purgeTempFiles() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent.hasPrefix("VidP-") {
            try? FileManager.default.removeItem(at: item)
        }
    }
}
