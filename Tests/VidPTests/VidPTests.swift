import XCTest
@testable import VidP

final class RemuxServiceTests: XCTestCase {
    private let video = URL(fileURLWithPath: "/tmp/movie.mkv")
    private let out = URL(fileURLWithPath: "/tmp/out.mp4")

    func testArgsWithoutSidecars() {
        let args = RemuxService.makeArgs(
            video: video, sidecars: [], output: out, includeSubtitles: true)
        XCTAssertEqual(args, [
            "-y", "-i", "/tmp/movie.mkv",
            "-map", "0:v?", "-map", "0:a?", "-map", "0:s?",
            "-c:v", "copy", "-c:a", "copy", "-c:s", "mov_text",
            "-movflags", "+faststart", "-f", "mp4", "/tmp/out.mp4",
        ])
    }

    func testSidecarsMappedBeforeEmbeddedSoTitlesAreDeterministic() {
        let subs = [
            URL(fileURLWithPath: "/tmp/My Subs.srt"),
            URL(fileURLWithPath: "/tmp/Commentary.vtt"),
        ]
        let args = RemuxService.makeArgs(
            video: video, sidecars: subs, output: out, includeSubtitles: true)

        // Sidecar inputs declared after the video input.
        XCTAssertTrue(args.contains("-i"), "inputs present")
        XCTAssertEqual(args[args.firstIndex(of: "-i")! + 1], "/tmp/movie.mkv")

        // Sidecar maps come first → deterministic output subtitle indices.
        let maps = args.enumerated().filter { $0.element == "-map" }.map { args[$0.offset + 1] }
        XCTAssertEqual(maps, ["1:0", "2:0", "0:v?", "0:a?", "0:s?"])

        // Titles pinned to those indices.
        XCTAssertTrue(args.contains("-metadata:s:s:0"))
        XCTAssertTrue(args.contains("title=My Subs"))
        XCTAssertTrue(args.contains("-metadata:s:s:1"))
        XCTAssertTrue(args.contains("title=Commentary"))
    }

    func testSubtitlesDroppedInSecondAttempt() {
        let subs = [URL(fileURLWithPath: "/tmp/My Subs.srt")]
        let args = RemuxService.makeArgs(
            video: video, sidecars: subs, output: out, includeSubtitles: false)
        XCTAssertFalse(args.contains("-c:s"))
        XCTAssertFalse(args.contains("title=My Subs"))
        let maps = args.enumerated().filter { $0.element == "-map" }.map { args[$0.offset + 1] }
        XCTAssertEqual(maps, ["0:v?", "0:a?"])
    }

    func testLocateFFmpegFindsRepoBuild() {
        // Dev-run resolution walks up from CWD; from repo root it must find Resources/ffmpeg.
        let fm = FileManager.default
        let original = fm.currentDirectoryPath
        fm.changeCurrentDirectoryPath(
            URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().path)
        defer { fm.changeCurrentDirectoryPath(original) }
        XCTAssertNotNil(RemuxService.locateFFmpeg())
    }

    func testPurgeTempFilesRemovesOnlyVidPPrefix() throws {
        let tmp = FileManager.default.temporaryDirectory
        let mine = tmp.appendingPathComponent("VidP-test-\(UUID()).mp4")
        let other = tmp.appendingPathComponent("unrelated-\(UUID()).mp4")
        try Data([0x01]).write(to: mine)
        try Data([0x02]).write(to: other)
        defer { try? FileManager.default.removeItem(at: other) }

        RemuxService.purgeTempFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: mine.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.path))
    }
}

final class PlaybackRouterTests: XCTestCase {
    func testKindRouting() {
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.MP4")), .direct)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.mov")), .direct)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.m4v")), .direct)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.mkv")), .remux)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.avi")), .remux)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.webm")), .remux)
        XCTAssertEqual(PlaybackRouter.kind(of: URL(fileURLWithPath: "/a/b.ts")), .remux)
    }

    func testPartitionSelection() {
        let urls = [
            URL(fileURLWithPath: "/m/My Subs.srt"),
            URL(fileURLWithPath: "/m/film.mkv"),
            URL(fileURLWithPath: "/m/film.en.srt"),
            URL(fileURLWithPath: "/m/notes.txt"),
        ]
        let (video, sidecars) = PlaybackRouter.partition(urls)
        XCTAssertEqual(video, URL(fileURLWithPath: "/m/film.mkv"))
        XCTAssertEqual(sidecars.map(\.lastPathComponent), ["My Subs.srt", "film.en.srt"])
    }

    func testPartitionVideoOnly() {
        let (video, sidecars) = PlaybackRouter.partition([
            URL(fileURLWithPath: "/m/film.mp4"),
        ])
        XCTAssertEqual(video?.pathExtension, "mp4")
        XCTAssertTrue(sidecars.isEmpty)
    }
}
