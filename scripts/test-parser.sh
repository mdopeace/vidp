#!/bin/bash
# Runs the MediaNameParser cases (no XCTest target: the app builds via
# `swiftc Sources/*.swift`, so tests live here, not in Sources/).
set -euo pipefail
cd "$(dirname "$0")/.."

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
cat > "$TMPDIR/main.swift" <<'EOF'
import Foundation
var failures = 0
func check(_ got: String, _ want: String, _ name: String) {
    if got == want { print("PASS \(name): \(got)") }
    else { failures += 1; print("FAIL \(name): got=\(got) want=\(want)") }
}
check(MediaNameParser.parse(filename: "Dune.Part.Two.2024.2160p.WEB-DL.mkv").prettyTitle(), "Dune Part Two (2024)", "movie-dots")
check(MediaNameParser.parse(filename: "Breaking.Bad.S01E02.mp4").prettyTitle(), "Breaking Bad S01E02", "tv-s01e02")
check(MediaNameParser.parse(filename: "Show.1x02.mkv").prettyTitle(), "Show S01E02", "tv-1x02")
check(MediaNameParser.parse(filename: "Avatar (2009).mp4").prettyTitle(), "Avatar (2009)", "movie-paren-year")
check(MediaNameParser.parse(filename: "Some Random Video.mkv").prettyTitle(), "Some Random Video", "fallback")
check(MediaNameParser.parse(filename: "Breaking-Bad-S01E01.mkv").prettyTitle(), "Breaking Bad S01E01", "tv-dash")
check(MediaNameParser.parse(filename: "Spider-Man.No.Way.Home.2021.mkv").prettyTitle(), "Spider-Man No Way Home (2021)", "movie-hyphen-kept")
check(MediaNameParser.parse(filename: "Blade Runner (Final Cut) 2007.mkv").prettyTitle(), "Blade Runner (Final Cut) (2007)", "movie-edition")
check(MediaNameParser.parse(filename: "Some.Movie.2020.[x265].mkv").prettyTitle(), "Some Movie (2020)", "movie-codec-bracket")
check(MediaNameParser.parse(filename: "Some.Movie.1080p.BluRay.mkv").prettyTitle(), "Some Movie", "fallback-codec-words")
check(MediaNameParser.parse(filename: "Some.Movie.HDTV.mkv").prettyTitle(), "Some Movie", "fallback-hdtv")
check(MediaNameParser.parse(filename: "Some.Movie.HDR.x264.mkv").prettyTitle(), "Some Movie", "fallback-hdr")
check(MediaNameParser.parse(filename: "Show.2012.S01E02.mkv").prettyTitle(), "Show (2012) S01E02", "tv-year")
check(MediaNameParser.parse(filename: "Breaking.Bad.S01E02.mp4").metaLine ?? "nil", "S01E02", "meta-tv")
check(MediaNameParser.parse(filename: "Dune.Part.Two.2024.mkv").metaLine ?? "nil", "2024", "meta-movie")
check(MediaNameParser.parse(filename: "Show.2012.S01E02.mkv").metaLine ?? "nil", "2012 · S01E02", "meta-tv-year")
check(MediaNameParser.parse(filename: "Some Random Video.mkv").metaLine ?? "nil", "nil", "meta-none")
if failures > 0 { print("\(failures) FAILURES"); exit(1) }
print("ALL PASS")
EOF
swiftc Sources/MediaNameParser.swift "$TMPDIR/main.swift" -o "$TMPDIR/test_parser"
"$TMPDIR/test_parser"
