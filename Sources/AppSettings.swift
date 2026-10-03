import AppKit
import CMPV

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("appSettingsDidChange")
}

enum AppSettings {
    private static let d = UserDefaults.standard

    // MARK: - Keys
    private enum K {
        static let hudFontName = "hudFontName"
        static let hudBold = "hudBold"
        static let hudItalic = "hudItalic"
        static let hudBorderSize = "hudBorderSize"
        static let progressColor = "progressColor"
        static let subFontName = "subFontName"
        static let subBold = "subBold"
        static let subItalic = "subItalic"
        static let subFontSize = "subFontSize"
        static let subColor = "subColor"
        static let subBorderColor = "subBorderColor"
        static let subBorderSize = "subBorderSize"
        static let subShadowOffset = "subShadowOffset"
        static let subOverrideASS = "subOverrideASS"
    }

    // MARK: - Defaults
    // Registration domain: the typed accessors below need no fallback logic,
    // and registered values are volatile so they never reach disk. Called once
    // from main.swift, before anything reads a setting.
    static func registerDefaults() {
        d.register(defaults: [
            K.hudFontName: "",
            K.hudBold: true,
            K.hudItalic: false,
            K.hudBorderSize: 1.0,
            K.progressColor: "1.0/1.0/1.0/1.0",
            K.subFontName: "",
            K.subBold: true,
            K.subItalic: true,
            K.subFontSize: 30.0,
            K.subColor: "1.0/1.0/1.0/1.0",
            K.subBorderColor: "0.0/0.0/0.0/1.0",
            K.subBorderSize: 3.0,
            K.subShadowOffset: 0.0,
            K.subOverrideASS: true,
        ])
    }

    // MARK: - Read
    static var hudFontName: String { d.string(forKey: K.hudFontName) ?? "" }
    static var hudBold: Bool { d.bool(forKey: K.hudBold) }
    static var hudItalic: Bool { d.bool(forKey: K.hudItalic) }
    static var hudBorderSize: Double { d.double(forKey: K.hudBorderSize) }
    static var progressColor: String { d.string(forKey: K.progressColor) ?? "" }
    static var subFontName: String { d.string(forKey: K.subFontName) ?? "" }
    static var subBold: Bool { d.bool(forKey: K.subBold) }
    static var subItalic: Bool { d.bool(forKey: K.subItalic) }
    static var subFontSize: Double { d.double(forKey: K.subFontSize) }
    static var subColor: String { d.string(forKey: K.subColor) ?? "" }
    static var subBorderColor: String { d.string(forKey: K.subBorderColor) ?? "" }
    static var subBorderSize: Double { d.double(forKey: K.subBorderSize) }
    static var subShadowOffset: Double { d.double(forKey: K.subShadowOffset) }
    static var subOverrideASS: Bool { d.bool(forKey: K.subOverrideASS) }

    // MARK: - Write
    static func setHudFontName(_ v: String) { d.set(v, forKey: K.hudFontName); notify() }
    static func setHudBold(_ v: Bool) { d.set(v, forKey: K.hudBold); notify() }
    static func setHudItalic(_ v: Bool) { d.set(v, forKey: K.hudItalic); notify() }
    static func setHudBorderSize(_ v: Double) { d.set(v, forKey: K.hudBorderSize); notify() }
    static func setProgressColor(_ v: String) { d.set(v, forKey: K.progressColor); notify() }
    static func setSubFontName(_ v: String) { d.set(v, forKey: K.subFontName); notify() }
    static func setSubBold(_ v: Bool) { d.set(v, forKey: K.subBold); notify() }
    static func setSubItalic(_ v: Bool) { d.set(v, forKey: K.subItalic); notify() }
    static func setSubFontSize(_ v: Double) { d.set(v, forKey: K.subFontSize); notify() }
    static func setSubColor(_ v: String) { d.set(v, forKey: K.subColor); notify() }
    static func setSubBorderColor(_ v: String) { d.set(v, forKey: K.subBorderColor); notify() }
    static func setSubBorderSize(_ v: Double) { d.set(v, forKey: K.subBorderSize); notify() }
    static func setSubShadowOffset(_ v: Double) { d.set(v, forKey: K.subShadowOffset); notify() }
    static func setSubOverrideASS(_ v: Bool) { d.set(v, forKey: K.subOverrideASS); notify() }

    // MARK: - Reset
    static func resetAll() {
        for key in [K.hudFontName, K.hudBold, K.hudItalic, K.hudBorderSize, K.progressColor,
                    K.subFontName, K.subBold, K.subItalic, K.subFontSize, K.subColor,
                    K.subBorderColor, K.subBorderSize, K.subShadowOffset, K.subOverrideASS] {
            d.removeObject(forKey: key)
        }
        notify()
    }

    // MARK: - Font helpers
    static var progressNSColor: NSColor? { color(fromMPV: progressColor) }

    /// Parses mpv's "r/g/b/a" color notation (alpha optional). Nil when
    /// unparseable — and no empty-string special case is needed, since ""
    /// splits to zero parts and falls out of the same guard.
    static func color(fromMPV str: String) -> NSColor? {
        let parts = str.split(separator: "/").compactMap { Double($0) }
        guard parts.count >= 3 else { return nil }
        return NSColor(red: CGFloat(parts[0]), green: CGFloat(parts[1]),
                       blue: CGFloat(parts[2]),
                       alpha: parts.count >= 4 ? CGFloat(parts[3]) : 1.0)
    }

    static func hudFont(named name: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        var font = name.isEmpty ? .systemFont(ofSize: size) : (NSFont(name: name, size: size) ?? .systemFont(ofSize: size))
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty { font = NSFontManager.shared.convert(font, toHaveTrait: traits) }
        return font
    }

    // MARK: - mpv options (before mpv_initialize)
    static func applyOptions(to mpv: OpaquePointer) {
        for (key, value) in subProps {
            mpv_set_option_string(mpv, key, value)
        }
    }

    // MARK: - mpv properties (live, after mpv_initialize)
    static func applySubtitle(to mpv: OpaquePointer) {
        for (key, value) in subProps {
            mpv_set_property_string(mpv, key, value)
        }
    }

    private static var subProps: [(String, String)] {
        [
            ("sub-font", subFontName.isEmpty ? "Helvetica Neue" : subFontName),
            ("sub-font-size", String(Int(subFontSize))),
            ("sub-bold", subBold ? "yes" : "no"),
            ("sub-italic", subItalic ? "yes" : "no"),
            ("sub-color", subColor),
            ("sub-border-color", subBorderColor),
            ("sub-border-size", String(Int(subBorderSize))),
            ("sub-shadow-offset", String(Int(subShadowOffset))),
            ("sub-ass-override", subOverrideASS ? "force" : "no"),
        ]
    }

    private static func notify() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }
}
