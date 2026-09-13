import Foundation

struct ParsedMedia {
    let title: String
    let year: Int?
    let season: Int?
    let episode: Int?

    func prettyTitle() -> String {
        if let s = season, let e = episode {
            if let y = year {
                return String(format: "%@ (%d) S%02dE%02d", title, y, s, e)
            }
            return String(format: "%@ S%02dE%02d", title, s, e)
        }
        if let y = year {
            return "\(title) (\(y))"
        }
        return title
    }

    /// Small meta line for the HUD row above the title (S01E01 / year).
    var metaLine: String? {
        if let s = season, let e = episode {
            let ep = String(format: "S%02dE%02d", s, e)
            if let y = year { return "\(y) · \(ep)" }
            return ep
        }
        if let y = year { return "\(y)" }
        return nil
    }
}

enum MediaNameParser {
    private static let sxxexx = try! NSRegularExpression(pattern: "^(.+?)[.\\s_\\-]+[Ss](\\d{1,2})[Ee](\\d{1,3})\\b")
    private static let nxm = try! NSRegularExpression(pattern: "^(.+?)[.\\s_\\-]+(\\d{1,2})[xX](\\d{1,3})\\b")
    private static let yearPat = try! NSRegularExpression(pattern: "^(.+?)[.\\s_\\-(\\[]+(19\\d{2}|20\\d{2})\\b")
    private static let brackets = try! NSRegularExpression(pattern: "\\[[^\\]]*\\]|\\([^\\)]*\\)")
    private static let spaces = try! NSRegularExpression(pattern: "\\s{2,}")
    // Strictly technical tags — never edition words (Final Cut, Extended, …).
    private static let codecWords = try! NSRegularExpression(
        pattern: "(?i)\\b(2160p|1080p|720p|480p|576p|4k|hdr(10)?|dolby|x265|x264|h\\.?264|h\\.?265|hevc|web-?dl|webrip|blu-?ray|brrip|bdrip|dvdrip|dvdscr|screener|hdtv|hdrip|aac|ac3|ddp|dts|atmos|truehd|ts|tc|multi|proper|repack|rerepack|10bit|8bit|amzn|nf|dsnp|hulu|yify|rarbg)\\b")

    static func parse(filename: String) -> ParsedMedia {
        let base = (filename as NSString).deletingPathExtension

        // TV: Show.S01E02 / Show_s1e2 / Show 1x02 — check before movie year.
        if let m = match(base, sxxexx) {
            let (title, year) = splitYear(m[0])
            return ParsedMedia(title: clean(title),
                               year: year, season: Int(m[1]), episode: Int(m[2]))
        }
        if let m = match(base, nxm) {
            let (title, year) = splitYear(m[0])
            return ParsedMedia(title: clean(title),
                               year: year, season: Int(m[1]), episode: Int(m[2]))
        }
        // Movie: Title.2024 / Title (2009) / Title [2024]
        if let m = match(base, yearPat) {
            return ParsedMedia(title: clean(m[0]),
                               year: Int(m[1]), season: nil, episode: nil)
        }
        return ParsedMedia(title: clean(base),
                           year: nil, season: nil, episode: nil)
    }

    /// Trailing year inside a TV title part (Show.2012.S01E02) for remake disambiguation.
    private static func splitYear(_ s: String) -> (String, Int?) {
        if let m = match(s, yearPat), let y = Int(m[1]) {
            return (m[0], y)
        }
        return (s, nil)
    }

    private static func match(_ s: String, _ re: NSRegularExpression) -> [String]? {
        let ns = s as NSString
        guard let r = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        var out: [String] = []
        for i in 1..<r.numberOfRanges {
            let range = r.range(at: i)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: s) else { return nil }
            out.append(String(s[swiftRange]))
        }
        return out
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        // Dash-separated names (Breaking-Bad-S01E01) use dashes as separators;
        // hyphenated titles (Spider-Man.No.Way.Home) already contain spaces by now.
        if !t.contains(" ") {
            t = t.replacingOccurrences(of: "-", with: " ")
        }
        t = stripCodecBrackets(t)
        t = codecWords.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
        t = spaces.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: " ")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_. "))
    }

    /// Removes bracketed segments only when they hold technical tags ([x265],
    /// (1080p)); edition info ((Final Cut)) survives.
    private static func stripCodecBrackets(_ s: String) -> String {
        let ns = s as NSString
        let matches = brackets.matches(in: s, range: NSRange(location: 0, length: ns.length))
        var out = s
        for m in matches.reversed() {
            let inner = ns.substring(with: m.range)
            let innerNS = inner as NSString
            if codecWords.firstMatch(in: inner, range: NSRange(location: 0, length: innerNS.length)) != nil {
                out = (out as NSString).replacingCharacters(in: m.range, with: " ")
            }
        }
        return out
    }
}
