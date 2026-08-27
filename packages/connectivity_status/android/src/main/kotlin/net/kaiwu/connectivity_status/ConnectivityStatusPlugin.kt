package net.kaiwu.connectivity_status

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** Exposes the OS metered capability
 *  (`ConnectivityManager.isActiveNetworkMetered`, which reflects the
 *  underlying transport even when a VPN masks it) over the
 *  `net.kaiwu.connectivity_status/metered` MethodChannel.
 *
 *  Requires `android.permission.ACCESS_NETWORK_STATE`. Registered
 *  automatically by `GeneratedPluginRegistrant` — no manual call needed in
 *  a consuming app's `MainActivity`. */
class ConnectivityStatusPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "net.kaiwu.connectivity_status/metered",
        )
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        if (call.method != "isActiveNetworkMetered") {
            result.notImplemented()
            return
        }
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager
        if (manager == null) {
            result.error("METERED_QUERY_FAILED", "metered query failed", null)
            return
        }
        try {
            result.success(manager.isActiveNetworkMetered)
        } catch (e: SecurityException) {
            // Missing ACCESS_NETWORK_STATE → degrade to the Dart-side
            // heuristic. Any other exception is a genuine bug and is left
            // to propagate (no opaque catch-all masking it).
            result.error("METERED_QUERY_FAILED", "metered query failed", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
