import XCTest
@testable import VidP

final class ChromeLogicTests: XCTestCase {
    // MARK: time formatting

    func testClockFormatting() {
        XCTAssertEqual(TimeFormatting.clock(0), "0:00")
        XCTAssertEqual(TimeFormatting.clock(5), "0:05")
        XCTAssertEqual(TimeFormatting.clock(61), "1:01")
        XCTAssertEqual(TimeFormatting.clock(3661), "1:01:01")
        XCTAssertEqual(TimeFormatting.clock(-61), "-1:01")
        XCTAssertEqual(TimeFormatting.clock(3599.9), "1:00:00")  // rounds
    }

    // MARK: chrome auto-hide policy

    private let t0: TimeInterval = 1000

    func testChromeStaysVisibleWhilePaused() {
        XCTAssertFalse(ChromePolicy.shouldAutoHide(
            now: t0 + 60, lastActivity: t0, isPlaying: false))
    }

    func testChromeHidesAfterIdleWhilePlaying() {
        XCTAssertFalse(ChromePolicy.shouldAutoHide(
            now: t0 + 2.9, lastActivity: t0, isPlaying: true))
        XCTAssertTrue(ChromePolicy.shouldAutoHide(
            now: t0 + 3, lastActivity: t0, isPlaying: true))
    }

    // MARK: seek clamping

    func testSeekClamping() {
        XCTAssertEqual(clampSeek(current: 50, delta: -100, duration: 600), 0)
        XCTAssertEqual(clampSeek(current: 590, delta: 10, duration: 600), 600)
        XCTAssertEqual(clampSeek(current: 50, delta: 10, duration: 600), 60)
        XCTAssertEqual(clampSeek(current: 50, delta: 10, duration: 0), 50)  // no duration → no-op
    }

    // MARK: track option naming / dedupe / selection

    func testTrackOptionsDedupeAndSelect() {
        let opts = trackOptions(
            named: ["English", "English", "My Subs"], selectedName: "English 2")
        XCTAssertEqual(opts.map(\.name), ["English", "English 2", "My Subs"])
        XCTAssertEqual(opts.first(where: \.isSelected)?.name, "English 2")
        XCTAssertEqual(opts.map(\.id), [0, 1, 2], "ids map to source indices")
    }

    func testTrackOptionsNoSelection() {
        let opts = trackOptions(named: ["AAC"], selectedName: nil)
        XCTAssertFalse(opts[0].isSelected)
    }
}
