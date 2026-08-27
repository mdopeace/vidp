import AppKit
import OpenGL.GL3
import OpenGL.GL
import CoreVideo
import CMPV

/// CAOpenGLLayer that renders mpv frames into its own drawable.
final class PlayerLayer: CAOpenGLLayer {
    weak var player: PlayerView?
    var renderCtx: OpaquePointer?
    private(set) var cglCtx: CGLContextObj?
    private(set) var cglPf: CGLPixelFormatObj?

    override init() {
        super.init()
        isAsynchronous = false
        isOpaque = false

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
        guard let player, let renderCtx, player.fileLoaded else {
            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
            return
        }

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
