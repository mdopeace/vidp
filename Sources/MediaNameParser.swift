import Foundation

struct ParsedMedia {
    enum Kind { case movie, tv }
    var kind: Kind
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?

    func prettyTitle() -> String {
        if let s = season, let e = episode {
            return String(format: "%@ S%02dE%02d", title, s, e)
        }
        if let y = year {
            return "\(title) (\(y))"
        }
        return title
    }
}

enum MediaNameParser {
    static func parse(filename: String) -> ParsedMedia {
        let base = (filename as NSString).deletingPathExtension

        // TV: Show.S01E02 / Show_s1e2 / Show 1x02 — check before movie year.
        if let m = match(base, pattern: "^(.+?)[\\.\\s_\\-]+[Ss](\\d{1,2})[Ee](\\d{1,3})\\b") {
            return ParsedMedia(kind: .tv, title: clean(m[0]),
                               year: nil, season: Int(m[1]), episode: Int(m[2]))
        }
        if let m = match(base, pattern: "^(.+?)[\\.\\s_\\-]+(\\d{1,2})[xX](\\d{1,3})\\b") {
            return ParsedMedia(kind: .tv, title: clean(m[0]),
                               year: nil, season: Int(m[1]), episode: Int(m[2]))
        }
        // Movie: Title.2024 / Title (2009) / Title [2024]
        if let m = match(base, pattern: "^(.+?)[\\.\\s_\\-(\\[]+(19\\d{2}|20\\d{2})\\b") {
            return ParsedMedia(kind: .movie, title: clean(m[0]),
                               year: Int(m[1]), season: nil, episode: nil)
        }
        return ParsedMedia(kind: .movie, title: clean(base),
                           year: nil, season: nil, episode: nil)
    }

    private static func match(_ s: String, pattern: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let r = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<r.numberOfRanges).map { ns.substring(with: r.range(at: $0)) }
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        // Drop bracketed codec tags that leaked into the title part.
        if let re = try? NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^\\)]*\\)") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
        }
        if let re = try? NSRegularExpression(pattern: "\\s{2,}") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_.()[] "))
    }
}
