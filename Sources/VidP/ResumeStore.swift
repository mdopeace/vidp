import Foundation

struct ResumeEntry: Codable, Equatable {
    var position: Double
    var duration: Double
    var updatedAt: Date
}

/// Persists last playback position per file in UserDefaults.
/// Keyed by standardized file path — moving a file resets its position (v1 trade-off).
struct ResumeStore {
    private let defaults: UserDefaults
    private let key = "vidp.resume.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Threshold rules (pure, unit-tested)

    static let minimumWatched: Double = 30

    /// Resume only if meaningfully watched and not effectively finished.
    static func shouldResume(_ entry: ResumeEntry) -> Bool {
        guard entry.duration > 0, entry.position > 0 else { return false }
        return entry.position > minimumWatched && entry.position < entry.duration * 0.95
    }

    // MARK: - Persistence

    func entry(for url: URL) -> ResumeEntry? {
        load()[url.standardizedFileURL.path]
    }

    func save(position: Double, duration: Double, for url: URL) {
        guard duration > 0 else { return }
        var table = load()
        table[url.standardizedFileURL.path] = ResumeEntry(
            position: position, duration: duration, updatedAt: Date())
        store(table)
    }

    func clear(for url: URL) {
        var table = load()
        guard table.removeValue(forKey: url.standardizedFileURL.path) != nil else { return }
        store(table)
    }

    private func load() -> [String: ResumeEntry] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: ResumeEntry].self, from: data)) ?? [:]
    }

    private func store(_ table: [String: ResumeEntry]) {
        defaults.set((try? JSONEncoder().encode(table)) ?? Data(), forKey: key)
    }
}
