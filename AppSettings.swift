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
    private static let defaults: [String: Any] = [
        K.hudFontName: "",
        K.hudBold: true,
        K.hudItalic: true,
        K.subFontName: "",
        K.subBold: true,
        K.subItalic: true,
        K.subFontSize: 30.0,
        K.subColor: "1.0/1.0/1.0/1.0",
        K.subBorderColor: "0.0/0.0/0.0/1.0",
        K.subBorderSize: 3.0,
        K.subShadowOffset: 0.0,
        K.subOverrideASS: true,
    ]

    // MARK: - Read
    static var hudFontName: String { d.string(forKey: K.hudFontName) ?? defaults[K.hudFontName] as! String }
    static var hudBold: Bool { d.object(forKey: K.hudBold) as? Bool ?? defaults[K.hudBold] as! Bool }
    static var hudItalic: Bool { d.object(forKey: K.hudItalic) as? Bool ?? defaults[K.hudItalic] as! Bool }
    static var subFontName: String { d.string(forKey: K.subFontName) ?? defaults[K.subFontName] as! String }
    static var subBold: Bool { d.object(forKey: K.subBold) as? Bool ?? defaults[K.subBold] as! Bool }
    static var subItalic: Bool { d.object(forKey: K.subItalic) as? Bool ?? defaults[K.subItalic] as! Bool }
    static var subFontSize: Double { d.object(forKey: K.subFontSize) as? Double ?? defaults[K.subFontSize] as! Double }
    static var subColor: String { d.string(forKey: K.subColor) ?? defaults[K.subColor] as! String }
    static var subBorderColor: String { d.string(forKey: K.subBorderColor) ?? defaults[K.subBorderColor] as! String }
    static var subBorderSize: Double { d.object(forKey: K.subBorderSize) as? Double ?? defaults[K.subBorderSize] as! Double }
    static var subShadowOffset: Double { d.object(forKey: K.subShadowOffset) as? Double ?? defaults[K.subShadowOffset] as! Double }
    static var subOverrideASS: Bool { d.object(forKey: K.subOverrideASS) as? Bool ?? defaults[K.subOverrideASS] as! Bool }

    // MARK: - Write
    static func setHudFontName(_ v: String) { d.set(v, forKey: K.hudFontName); notify() }
    static func setHudBold(_ v: Bool) { d.set(v, forKey: K.hudBold); notify() }
    static func setHudItalic(_ v: Bool) { d.set(v, forKey: K.hudItalic); notify() }
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
        for key in [K.hudFontName, K.hudBold, K.hudItalic, K.subFontName, K.subBold, K.subItalic,
                    K.subColor, K.subBorderColor] {
            d.removeObject(forKey: key)
        }
        for key in [K.subFontSize, K.subBorderSize, K.subShadowOffset] {
            d.removeObject(forKey: key)
        }
        d.removeObject(forKey: K.subOverrideASS)
        notify()
    }

    // MARK: - Font helpers
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
        mpv_set_option_string(mpv, "sub-font", subFontName.isEmpty ? "Helvetica Neue" : subFontName)
        mpv_set_option_string(mpv, "sub-font-size", String(Int(subFontSize)))
        mpv_set_option_string(mpv, "sub-bold", subBold ? "yes" : "no")
        mpv_set_option_string(mpv, "sub-italic", subItalic ? "yes" : "no")
        mpv_set_option_string(mpv, "sub-color", subColor)
        mpv_set_option_string(mpv, "sub-border-color", subBorderColor)
        mpv_set_option_string(mpv, "sub-border-size", String(Int(subBorderSize)))
        mpv_set_option_string(mpv, "sub-shadow-offset", String(Int(subShadowOffset)))
        mpv_set_option_string(mpv, "sub-ass-override", subOverrideASS ? "force" : "no")
    }

    // MARK: - mpv properties (live, after mpv_initialize)
    static func applySubtitle(to mpv: OpaquePointer) {
        mpv_set_property_string(mpv, "sub-font", subFontName.isEmpty ? "Helvetica Neue" : subFontName)
        mpv_set_property_string(mpv, "sub-font-size", String(Int(subFontSize)))
        mpv_set_property_string(mpv, "sub-bold", subBold ? "yes" : "no")
        mpv_set_property_string(mpv, "sub-italic", subItalic ? "yes" : "no")
        mpv_set_property_string(mpv, "sub-color", subColor)
        mpv_set_property_string(mpv, "sub-border-color", subBorderColor)
        mpv_set_property_string(mpv, "sub-border-size", String(Int(subBorderSize)))
        mpv_set_property_string(mpv, "sub-shadow-offset", String(Int(subShadowOffset)))
        mpv_set_property_string(mpv, "sub-ass-override", subOverrideASS ? "force" : "no")
    }

    private static func notify() {
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil)
    }
}
