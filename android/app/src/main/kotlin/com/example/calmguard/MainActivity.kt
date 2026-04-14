package com.example.calmguard

import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity(), MessageClient.OnMessageReceivedListener {
    private val watchChannel = "calmguard/watch"
    private lateinit var methodChannel: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, watchChannel)
    }

    override fun onResume() {
        super.onResume()
        Wearable.getMessageClient(this).addListener(this)
    }

    override fun onPause() {
        Wearable.getMessageClient(this).removeListener(this)
        super.onPause()
    }

    override fun onMessageReceived(messageEvent: MessageEvent) {
        val path = messageEvent.path.trimStart('/')

        if (path == "watch_warning" || path == "watch_trigger" || path == "watch_reset") {
            runOnUiThread {
                methodChannel.invokeMethod(path, null)
            }
        }
    }
}