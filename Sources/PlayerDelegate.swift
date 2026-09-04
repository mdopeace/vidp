import AppKit

protocol PlayerDelegate: AnyObject {
    func playerDidUpdateVideoSize(width: Int64, height: Int64)
    func playerDidUpdatePlaybackState(isPaused: Bool)
    func playerDidEncounterError(_ message: String)
    func playerDidEndFile()
    func playerDidFileLoad()
    func playerDidRequestNext()
    func playerDidRequestPrev()
    func playerView(_ playerView: PlayerView, didReceiveFile path: String)
    func playerDidAdjustVolume(_ volume: Int)
}

// C callbacks must be top-level functions.

func glGetProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return CFBundleGetFunctionPointerForName(
        CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
        String(cString: name) as CFString)
}

func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let view = Unmanaged<PlayerView>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { view.playerLayer?.setNeedsDisplay() }
}
