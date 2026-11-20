package com.example.swifty_protein

import android.content.Context
import android.opengl.GLSurfaceView
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class MoleculeViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as Map<*, *>
        val renderer = MoleculeRenderer(
            params["coordinates"] as DoubleArray,
            params["colors"] as IntArray,
            params["radii"] as DoubleArray,
            params["elementGroups"] as IntArray,
            params["bonds"] as IntArray,
            params["background"] as Int,
            params["bond"] as Int,
        )
        return MoleculeView(context, renderer, MethodChannel(messenger, "swifty_protein/molecule/$viewId"))
    }
}

private class MoleculeView(
    context: Context,
    private val renderer: MoleculeRenderer,
    private val channel: MethodChannel,
) : PlatformView {
    private val mainThread = Handler(Looper.getMainLooper())
    private var capture: MethodChannel.Result? = null
    private val surface = GLSurfaceView(context).apply {
        setEGLContextClientVersion(3)
        setRenderer(renderer)
        renderMode = GLSurfaceView.RENDERMODE_WHEN_DIRTY
    }

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "highlight" -> {
                    val ids = call.arguments as List<*>
                    renderer.highlight = MoleculeRenderer.Highlight(
                        (ids[0] as Number).toInt(), (ids[1] as Number).toInt(),
                        (ids[2] as Number).toInt(), (ids[3] as Number).toInt(),
                    )
                    surface.requestRender()
                    result.success(null)
                }
                "model" -> {
                    val model = when (call.arguments) {
                        "ballAndStick" -> MoleculeRenderer.Model.BALL_AND_STICK
                        "spaceFilling" -> MoleculeRenderer.Model.SPACE_FILLING
                        "stick" -> MoleculeRenderer.Model.STICK
                        "wireframe" -> MoleculeRenderer.Model.WIREFRAME
                        else -> null
                    }
                    if (model == null) {
                        result.error("invalid_model", "Unknown visualization model.", null)
                    } else {
                        renderer.model = model
                        surface.requestRender()
                        result.success(null)
                    }
                }
                "pose" -> {
                    val pose = call.arguments as List<*>
                    renderer.pose = MoleculeRenderer.Pose(
                        (pose[0] as Number).toFloat(), (pose[1] as Number).toFloat(),
                        (pose[2] as Number).toFloat(), (pose[3] as Number).toFloat(),
                        (pose[4] as Number).toFloat(),
                    )
                    surface.requestRender()
                    result.success(null)
                }
                "palette" -> {
                    renderer.palette = MoleculeRenderer.Palette(
                        call.argument<Int>("background")!!, call.argument<Int>("bond")!!,
                    )
                    surface.requestRender()
                    result.success(null)
                }
                "pick" -> {
                    val point = call.arguments as List<*>
                    surface.queueEvent {
                        val hit = renderer.pick(
                            (point[0] as Number).toFloat(), (point[1] as Number).toFloat(),
                        )
                        mainThread.post { result.success(hit) }
                    }
                }
                "capture" -> {
                    val format = MoleculeImageFormat.fromKey(call.arguments)
                    if (format == null) {
                        result.error("invalid_format", "Unsupported image format.", null)
                    } else if (capture != null) {
                        result.error("capture_busy", "An image is already being captured.", null)
                    } else {
                        capture = result
                        renderer.capture = MoleculeRenderer.Capture(format) { image ->
                            mainThread.post {
                                if (capture === result) {
                                    capture = null
                                    if (image != null) result.success(image)
                                    else result.error("capture_failed", "Could not capture this frame.", null)
                                }
                            }
                        }
                        surface.requestRender()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun getView() = surface

    override fun dispose() {
        channel.setMethodCallHandler(null)
        renderer.capture = null
        capture?.error("view_closed", "The molecule view was closed.", null)
        capture = null
    }
}
