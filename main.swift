import AppKit
import OpenGL.GL3
import OpenGL.GL
import CoreVideo
import CMPV

protocol PlayerDelegate: AnyObject {
    func playerDidUpdateVideoSize(width: Int64, height: Int64)
    func playerDidEncounterError(_ message: String)
}

// C callbacks must be top-level functions.

private func glGetProcAddress(
    _ ctx: UnsafeMutableRawPointer?,
    _ name: UnsafePointer<CChar>?
) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    return CFBundleGetFunctionPointerForName(
        CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString),
        String(cString: name) as CFString)
}

private func mpvUpdateCallback(_ ctx: UnsafeMutableRawPointer?) {
    guard let ctx else { return }
    let view = Unmanaged<PlayerView>.fromOpaque(ctx).takeUnretainedValue()
    DispatchQueue.main.async { view.playerLayer?.setNeedsDisplay() }
}


/// CAOpenGLLayer that renders mpv frames into its own drawable.
final class PlayerLayer: CAOpenGLLayer {
    weak var player: PlayerView?
    var renderCtx: OpaquePointer?
    private(set) var cglCtx: CGLContextObj?
    private(set) var cglPf: CGLPixelFormatObj?

    override init() {
        super.init()
        isAsynchronous = false
        isOpaque = true

        // Eagerly create THE pixel format + context we'll use everywhere,
        // so mpv's render context binds to the exact context CA draws with.
        let nspf = NSOpenGLPixelFormat(attributes: [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersionLegacy),
            UInt32(NSOpenGLPFADoubleBuffer),
            0,
        ])
        if let obj = nspf?.cglPixelFormatObj {
            cglPf = obj
            var ctx: CGLContextObj?
            CGLCreateContext(obj, nil, &ctx)
            cglCtx = ctx
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func canDraw(inCGLContext ctx: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                          forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) -> Bool {
        true
    }

    // Superclass implementation flushes the drawable; call after mpv renders.
    override func draw(inCGLContext ctx: CGLContextObj, pixelFormat: CGLPixelFormatObj,
                       forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?) {
        guard let player, let renderCtx else { return }

        let b = player.bounds
        let scale = player.window?.backingScaleFactor ?? 2
        let w = Int32(max(1, b.width * scale))
        let h = Int32(max(1, b.height * scale))
        var flipY: CInt = 1
        // CAOpenGLLayer backs itself with an internal IOSurface FBO — render into THAT,
        // not FBO 0 (which has no drawable here).
        var boundFbo: GLint = 0
        glGetIntegerv(GLenum(GL_DRAW_FRAMEBUFFER_BINDING), &boundFbo)
        var fbo = mpv_opengl_fbo(fbo: Int32(boundFbo), w: w, h: h, internal_format: 0)
        withUnsafeMutableBytes(of: &fbo) { fboBuf in
            withUnsafeMutableBytes(of: &flipY) { flipBuf in
                guard let fboPtr = fboBuf.baseAddress, let flipPtr = flipBuf.baseAddress else { return }
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param(),
                ]
                _ = mpv_render_context_render(renderCtx, &params)
            }
        }
        super.draw(inCGLContext: ctx, pixelFormat: pixelFormat, forLayerTime: t, displayTime: ts)
        mpv_render_context_report_swap(renderCtx)
    }

    // Always hand back the exact pixel format + context mpv was created with.
    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        cglPf!
    }

    override func releaseCGLPixelFormat(_ pf: CGLPixelFormatObj) {}

    override func copyCGLContext(forPixelFormat pf: CGLPixelFormatObj) -> CGLContextObj {
        cglCtx!
    }

    override func releaseCGLContext(_ ctx: CGLContextObj) {}
}

final class PlayerView: NSView {
    private(set) var mpv: OpaquePointer?
    private(set) var renderCtx: OpaquePointer?
    private(set) var playerLayer: PlayerLayer?
    weak var delegate: PlayerDelegate?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        autoresizingMask = [.width, .height]
        let layer = PlayerLayer()
        layer.player = self
        self.layer = layer
        playerLayer = layer
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            playerLayer?.contentsScale = window.backingScaleFactor
        }
    }

    /// Initializes mpv + its render context. Returns an error message on failure.
    func setup() -> String? {
        guard let layer = playerLayer, let glctx = layer.cglCtx else { return "no OpenGL context" }
        CGLSetCurrentContext(glctx)
        defer { CGLSetCurrentContext(nil) }

        guard let mpv = mpv_create() else { return "mpv_create() failed" }

        // Must be set before mpv_initialize().
        mpv_set_option_string(mpv, "vo", "libmpv")
        mpv_set_option_string(mpv, "hwdec", "videotoolbox")
        mpv_set_option_string(mpv, "keep-open", "always")

        guard mpv_initialize(mpv) >= 0 else {
            mpv_destroy(mpv)
            return "mpv_initialize() failed"
        }
        self.mpv = mpv

        var initParams = mpv_opengl_init_params(
            get_proc_address: glGetProcAddress,
            get_proc_address_ctx: nil)

        MPV_RENDER_API_TYPE_OPENGL.withCString { apiType in
            withUnsafeMutableBytes(of: &initParams) { initBuf in
                guard let initPtr = initBuf.baseAddress else { return }
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE,
                                     data: UnsafeMutableRawPointer(mutating: apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPtr),
                    mpv_render_param(),
                ]
                var ctx: OpaquePointer?
                guard mpv_render_context_create(&ctx, mpv, &params) >= 0, let ctx else {
                    mpv_destroy(mpv)
                    self.mpv = nil
                    return
                }
                self.renderCtx = ctx
                layer.renderCtx = ctx
                mpv_render_context_set_update_callback(
                    ctx, mpvUpdateCallback, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        guard renderCtx != nil else {
            mpv_destroy(mpv)
            self.mpv = nil
            return "mpv_render_context_create() failed"
        }

        mpv_observe_property(mpv, 0, "width", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 0, "height", MPV_FORMAT_INT64)

        listenForEvents()
        return nil
    }

    func load(path: String) {
        guard let mpv else { return }
        "loadfile".withCString { cmd in
            path.withCString { p in
                var args: [UnsafePointer<CChar>?] = [cmd, p, nil]
                if mpv_command(mpv, &args) < 0 {
                    DispatchQueue.main.async {
                        self.delegate?.playerDidEncounterError("Could not load \(path)")
                    }
                }
            }
        }
    }

    private func intProperty(_ name: String) -> Int64? {
        guard let mpv else { return nil }
        var value: Int64 = 0
        return mpv_get_property(mpv, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    private func listenForEvents() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            while let mpv = self?.mpv {
                let event = mpv_wait_event(mpv, -1).pointee
                switch event.event_id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    if let prop = event.data?.assumingMemoryBound(to: mpv_event_property.self) {
                        let name = String(cString: prop.pointee.name)
                        if name == "width" || name == "height" {
                            let w = self?.intProperty("width") ?? 0
                            let h = self?.intProperty("height") ?? 0
                            DispatchQueue.main.async {
                                self?.delegate?.playerDidUpdateVideoSize(width: w, height: h)
                            }
                        }
                    }
                case MPV_EVENT_END_FILE:
                    if let endFile = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) {
                        if endFile.pointee.reason == MPV_END_FILE_REASON_ERROR {
                            let msg = String(cString: mpv_error_string(endFile.pointee.error))
                            DispatchQueue.main.async {
                                self?.delegate?.playerDidEncounterError(msg)
                            }
                        }
                    }
                case MPV_EVENT_SHUTDOWN:
                    DispatchQueue.main.async { NSApp.terminate(nil) }
                    return
                default:
                    break
                }
            }
        }
    }

    deinit {
        if let renderCtx { mpv_render_context_free(renderCtx) }
        if let mpv { mpv_destroy(mpv) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, PlayerDelegate {
    var window: NSWindow!
    private var playerView: PlayerView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        playerView = PlayerView(frame: .zero)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "OTV"
        window.contentView = playerView

        if let error = playerView.setup() {
            NSLog("OTV setup failed: \(error)")
        }
        playerView.delegate = self

        window.center()
        window.makeKeyAndOrderFront(nil)

        // CLI fallback: OTV.app/Contents/MacOS/OTV <file>
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        if let first = args.first {
            open(path: first)
        }
    }

    // Finder "Open With" sends files here (odoc Apple Event).
    func application(_ application: NSApplication, openFiles files: [String]) {
        open(path: files[0])
    }

    private func open(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            NSLog("OTV: no such file: \(path)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.window.makeKeyAndOrderFront(nil)
            self?.playerView.load(path: path)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: PlayerDelegate

    func playerDidUpdateVideoSize(width: Int64, height: Int64) {
        guard width > 0, height > 0, let screen = window.screen ?? NSScreen.main else { return }
        let maxW = screen.visibleFrame.width * 0.9
        let maxH = screen.visibleFrame.height * 0.9
        let aspect = CGFloat(width) / CGFloat(height)
        var size = CGSize(width: maxW, height: maxW / aspect)
        if size.height > maxH {
            size = CGSize(width: maxH * aspect, height: maxH)
        }
        window.setContentSize(size)
        window.center()
    }

    func playerDidEncounterError(_ message: String) {
        NSLog("OTV playback error: \(message)")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
