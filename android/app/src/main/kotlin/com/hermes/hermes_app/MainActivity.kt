package com.hermes.hermes_app

import android.content.Intent
import android.os.Build
import android.view.RoundedCorner
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var audioRoute: AudioRoute? = null
    private var modelImport: ModelImport? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val importChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frank/model_import")
        val importer = ModelImport(this, importChannel).also { modelImport = it }
        importChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pick" -> {
                    val args = call.arguments as Map<*, *>
                    importer.pick(
                        args["target"] as String,
                        (args["folders"] as List<*>).map { it as String },
                        result,
                    )
                }
                else -> result.notImplemented()
            }
        }
        val callChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frank/call")
        CallService.onEndFromNotification = {
            runOnUiThread { callChannel.invokeMethod("endCall", null) }
        }
        callChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        CallService.start(this, call.arguments as? String ?: "Hermsy")
                        result.success(true)
                    } catch (error: Exception) {
                        // No mic permission, or Android refused: the call
                        // still works while Frank is on screen.
                        result.success(false)
                    }
                }
                "stop" -> {
                    CallService.stop(this)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        val routeChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frank/audio_route")
        val route = AudioRoute(this, routeChannel).also { audioRoute = it }
        routeChannel.setMethodCallHandler { call, result ->
            val purpose = call.arguments as? String ?: "call"
            when (call.method) {
                "begin" -> route.begin(purpose) { picked -> result.success(picked) }
                "end" -> {
                    route.end(purpose)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "frank/display")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "cornerRadii" -> result.success(cornerRadii())
                    // The phone's time zone, e.g. "Europe/London", for job times.
                    "timeZone" -> result.success(java.util.TimeZone.getDefault().id)
                    "setSecure" -> {
                        setSecure(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("The folder picker answers here.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (modelImport?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        CallService.onEndFromNotification = null
        CallService.stop(this)
        audioRoute?.end("call")
        audioRoute?.end("dictation")
        super.onDestroy()
    }

    // Physical-pixel radii of the screen's rounded corners, so the edge glow
    // can hug the real glass. Empty before Android 12 (no API, Dart keeps a
    // typical radius); null while the window is not attached yet (Dart asks
    // again later).
    private fun cornerRadii(): Map<String, Int>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            return emptyMap()
        }
        val insets = window?.decorView?.rootWindowInsets ?: return null
        fun radius(position: Int) = insets.getRoundedCorner(position)?.radius ?: 0
        return mapOf(
            "topLeft" to radius(RoundedCorner.POSITION_TOP_LEFT),
            "topRight" to radius(RoundedCorner.POSITION_TOP_RIGHT),
            "bottomLeft" to radius(RoundedCorner.POSITION_BOTTOM_LEFT),
            "bottomRight" to radius(RoundedCorner.POSITION_BOTTOM_RIGHT),
        )
    }

    // "Hide in app switcher": blank the recents preview and block
    // screenshots while the setting is on.
    private fun setSecure(secure: Boolean) {
        val window = window ?: return
        if (secure) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
