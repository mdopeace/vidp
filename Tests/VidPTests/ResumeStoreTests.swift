import XCTest
@testable import VidP

final class ResumeStoreTests: XCTestCase {
    private func makeStore() -> (ResumeStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: "vidp-tests-\(UUID())")!
        return (ResumeStore(defaults: defaults), defaults)
    }

    private let url = URL(fileURLWithPath: "/movies/film.mkv")

    func testRoundTrip() {
        let (store, _) = makeStore()
        store.save(position: 120, duration: 600, for: url)
        let entry = store.entry(for: url)
        XCTAssertEqual(entry?.position ?? -1, 120, accuracy: 0.001)
        XCTAssertEqual(entry?.duration ?? -1, 600, accuracy: 0.001)

        store.clear(for: url)
        XCTAssertNil(store.entry(for: url))
    }

    func testClearIsNoOpWhenAbsent() {
        let (store, _) = makeStore()
        store.clear(for: url)  // must not throw/crash
        XCTAssertNil(store.entry(for: url))
    }

    func testSaveIgnoresZeroDuration() {
        let (store, _) = makeStore()
        store.save(position: 50, duration: 0, for: url)
        XCTAssertNil(store.entry(for: url))
    }

    func testShouldResumeThresholds() {
        func entry(_ pos: Double, _ dur: Double) -> ResumeEntry {
            ResumeEntry(position: pos, duration: dur, updatedAt: Date())
        }
        XCTAssertFalse(ResumeStore.shouldResume(entry(10, 600)), "below minimum watched")
        XCTAssertTrue(ResumeStore.shouldResume(entry(31, 600)))
        XCTAssertFalse(ResumeStore.shouldResume(entry(570, 600)), ">=95% means finished")
        XCTAssertTrue(ResumeStore.shouldResume(entry(569, 600)))
        XCTAssertFalse(ResumeStore.shouldResume(entry(100, 0)), "invalid duration")
        XCTAssertFalse(ResumeStore.shouldResume(entry(0, 600)), "never started")
    }

    func testPersistenceAcrossInstances() {
        let (store, defaults) = makeStore()
        store.save(position: 42, duration: 300, for: url)
        let reloaded = ResumeStore(defaults: defaults)
        XCTAssertEqual(reloaded.entry(for: url)?.position ?? -1, 42, accuracy: 0.001)
    }

    func testStandardizingPathUnifiesVariants() {
        let (store, _) = makeStore()
        let variant = URL(fileURLWithPath: "/movies/./film.mkv").standardizedFileURL
        XCTAssertEqual(variant.path, url.path)
        store.save(position: 7, duration: 60, for: variant)
        XCTAssertEqual(store.entry(for: url)?.position ?? -1, 7, accuracy: 0.001)
    }
}
